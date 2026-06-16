import CoreImage
import Foundation

/// Generates / loads 3D LUTs and exposes them as a ready `CIColorCubeWithColorSpace`
/// filter. The procedural cubes bake the entire per-pixel color math (camera
/// calibration → HSL shifts → saturation compression → split toning → tone
/// curve, or monochrome conversion) so the live preview is a single GPU filter.
final class LUTFilter {

    /// In-memory cache keyed by style id so each cube is only built once.
    private static var cache: [String: Data] = [:]
    private static let cacheQueue = DispatchQueue(label: "lutfilter.cache")
    private static let defaultDimension = 33

    private let data: Data
    private let dimension: Int

    private init(data: Data, dimension: Int) {
        self.data = data
        self.dimension = dimension
    }

    // MARK: - Factory ------------------------------------------------------

    /// Procedural LUT for a style (cached by `style.id`).
    static func procedural(for style: LeicaStyle) -> LUTFilter {
        let data = cacheQueue.sync { () -> Data in
            if let cached = cache[style.id] { return cached }
            let built = generateLeicaLUT(style: style)
            cache[style.id] = built
            return built
        }
        return LUTFilter(data: data, dimension: defaultDimension)
    }

    /// Parse a `.cube` text file (3D, size 2...64). Returns nil on malformed input.
    static func load(cubeURL url: URL) -> LUTFilter? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var size = 0
        var values: [Float] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("TITLE") || line.hasPrefix("DOMAIN") { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                size = Int(line.split(separator: " ").last ?? "") ?? 0; continue
            }
            if line.hasPrefix("LUT_1D_SIZE") { return nil }
            let comps = line.split(separator: " ").compactMap { Float($0) }
            if comps.count == 3 { values.append(contentsOf: comps) }
        }
        guard size >= 2, values.count == size * size * size * 3 else { return nil }
        var rgba = [Float](repeating: 0, count: size * size * size * 4)
        for i in 0..<(size * size * size) {
            rgba[i * 4 + 0] = values[i * 3 + 0]
            rgba[i * 4 + 1] = values[i * 3 + 1]
            rgba[i * 4 + 2] = values[i * 3 + 2]
            rgba[i * 4 + 3] = 1.0
        }
        return LUTFilter(data: rgba.withUnsafeBytes { Data($0) }, dimension: size)
    }

    // MARK: - Application --------------------------------------------------

    func apply(to image: CIImage) -> CIImage {
        let filter = CIFilter(name: "CIColorCubeWithColorSpace")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        filter.setValue(CGColorSpaceCreateDeviceRGB(), forKey: "inputColorSpace")
        return filter.outputImage ?? image
    }

    // MARK: - Procedural cube generation ----------------------------------

    /// Builds a 33×33×33 RGBA float cube for `style`.
    static func generateLeicaLUT(style: LeicaStyle) -> Data {
        let size = defaultDimension
        let count = size * size * size * 4
        var cubeData = [Float](repeating: 0, count: count)
        let last = Float(size - 1)

        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    var rf = Float(r) / last
                    var gf = Float(g) / last
                    var bf = Float(b) / last

                    if style.isMonochrome {
                        // Color processing collapses to a weighted B&W conversion
                        // applied BEFORE the tone curve.
                        (rf, gf, bf) = applyMonochromConversion(rf, gf, bf, style: style)
                    } else {
                        (rf, gf, bf) = applyCameraCalibration(rf, gf, bf, style: style)   // 1
                        (rf, gf, bf) = applyHSLShifts(rf, gf, bf, style: style)            // 2
                        (rf, gf, bf) = applySaturationCompression(rf, gf, bf, style: style) // 3
                        (rf, gf, bf) = applySplitToning(rf, gf, bf, style: style)          // 4
                    }

                    rf = applyToneCurve(rf, style: style)                                  // 5
                    gf = applyToneCurve(gf, style: style)
                    bf = applyToneCurve(bf, style: style)

                    let index = (b * size * size + g * size + r) * 4
                    cubeData[index + 0] = clamp01(rf)
                    cubeData[index + 1] = clamp01(gf)
                    cubeData[index + 2] = clamp01(bf)
                    cubeData[index + 3] = 1.0
                }
            }
        }
        return cubeData.withUnsafeBytes { Data($0) }
    }

    // MARK: Step 1 — camera calibration

    private static func applyCameraCalibration(_ r: Float, _ g: Float, _ b: Float,
                                               style: LeicaStyle) -> (Float, Float, Float) {
        let rOut = r + style.calibrationR * r * (1 - r)
        let gOut = g + style.calibrationG * g * (1 - g)
        let bOut = b + style.calibrationB * b * (1 - b)
        return (rOut, gOut, bOut)
    }

    // MARK: Step 2 — per-band HSL shifts

    /// Hue-band centers (normalized turns) matching the 8 Lightroom HSL bands.
    private static let bandCenters: [Float] = [
        0.0,            // Red       0°
        30.0 / 360.0,   // Orange   30°
        60.0 / 360.0,   // Yellow   60°
        120.0 / 360.0,  // Green   120°
        180.0 / 360.0,  // Aqua    180°
        225.0 / 360.0,  // Blue    225°
        270.0 / 360.0,  // Purple  270°
        315.0 / 360.0   // Magenta 315°
    ]

    private static func applyHSLShifts(_ r: Float, _ g: Float, _ b: Float,
                                       style: LeicaStyle) -> (Float, Float, Float) {
        guard style.hslShifts.count == 8 else { return (r, g, b) }
        var (h, s, l) = rgbToHSL(r, g, b)

        // Smoothly crossfade between the two bands whose centers bracket `h`.
        let (i0, i1, t) = bracketingBands(for: h)
        let s0 = style.hslShifts[i0], s1 = style.hslShifts[i1]
        let hueShift = mix(s0.hueShift, s1.hueShift, t: t)
        let satMult  = mix(s0.satMult,  s1.satMult,  t: t)
        let lumOff   = mix(s0.lumOffset, s1.lumOffset, t: t)

        h = (h + hueShift).truncatingRemainder(dividingBy: 1.0)
        if h < 0 { h += 1 }
        s = clamp01(s * satMult)
        l = clamp01(l + lumOff)
        return hslToRGB(h, s, l)
    }

    /// Returns the indices of the two adjacent band centers bracketing `h`
    /// plus the interpolation factor between them (handles wraparound).
    private static func bracketingBands(for h: Float) -> (Int, Int, Float) {
        let n = bandCenters.count
        for i in 0..<n {
            let c0 = bandCenters[i]
            let c1 = (i + 1 < n) ? bandCenters[i + 1] : (bandCenters[0] + 1.0)
            if h >= c0 && h < c1 {
                return (i, (i + 1) % n, (h - c0) / (c1 - c0))
            }
        }
        // h below the first center (between Magenta wrap and Red) or exactly 1.0.
        let c0 = bandCenters[n - 1]            // magenta center
        let c1 = bandCenters[0] + 1.0          // red center, wrapped
        let hh = h < bandCenters[0] ? h + 1.0 : h
        return (n - 1, 0, (hh - c0) / (c1 - c0))
    }

    // MARK: Step 3 — global saturation compression

    private static func applySaturationCompression(_ r: Float, _ g: Float, _ b: Float,
                                                    style: LeicaStyle) -> (Float, Float, Float) {
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let f = style.globalSaturation
        return (luma + f * (r - luma), luma + f * (g - luma), luma + f * (b - luma))
    }

    // MARK: Step 4 — split toning

    private static func applySplitToning(_ r: Float, _ g: Float, _ b: Float,
                                         style: LeicaStyle) -> (Float, Float, Float) {
        guard style.highlightTintStrength > 0 || style.shadowTintStrength > 0 else {
            return (r, g, b)
        }
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

        // Tint colors derived from the style's hue wheel positions.
        let (hlR, hlG, hlB) = hslToRGB(style.highlightTintHue, 1.0, 0.5)
        let (shR, shG, shB) = hslToRGB(style.shadowTintHue, 1.0, 0.5)

        let hlWeight = smoothstep(0.5, 1.0, luma) * style.highlightTintStrength
        let shWeight = smoothstep(0.5, 0.0, luma) * style.shadowTintStrength

        let rOut = r + hlWeight * (hlR - r) + shWeight * (shR - r)
        let gOut = g + hlWeight * (hlG - g) + shWeight * (shG - g)
        let bOut = b + hlWeight * (hlB - b) + shWeight * (shB - b)
        return (rOut, gOut, bOut)
    }

    // MARK: Step 5 — tone curve

    private static func applyToneCurve(_ x: Float, style: LeicaStyle) -> Float {
        cubicHermiteInterpolate(style.toneCurvePoints, at: x)
    }

    // MARK: Monochrome conversion (before tone curve)

    private static func applyMonochromConversion(_ r: Float, _ g: Float, _ b: Float,
                                                 style: LeicaStyle) -> (Float, Float, Float) {
        let w = style.monochromeWeights ?? (r: 0.35, g: 0.50, b: 0.15)
        let luma = w.r * r + w.g * g + w.b * b
        return (luma, luma, luma)
    }
}

// MARK: - Color / math helpers (file-private to avoid global collisions)

private func clamp01(_ x: Float) -> Float { min(1, max(0, x)) }

func mix(_ a: Float, _ b: Float, t: Float) -> Float { a + t * (b - a) }

func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// Standard RGB → HSL. Hue in turns (0...1), saturation and lightness 0...1.
func rgbToHSL(_ r: Float, _ g: Float, _ b: Float) -> (h: Float, s: Float, l: Float) {
    let maxV = max(r, g, b), minV = min(r, g, b)
    let l = (maxV + minV) / 2
    guard maxV != minV else { return (0, 0, l) }   // achromatic
    let d = maxV - minV
    let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
    var h: Float
    if maxV == r {
        h = (g - b) / d + (g < b ? 6 : 0)
    } else if maxV == g {
        h = (b - r) / d + 2
    } else {
        h = (r - g) / d + 4
    }
    h /= 6
    return (h, s, l)
}

/// Standard HSL → RGB. Hue in turns (0...1).
func hslToRGB(_ h: Float, _ s: Float, _ l: Float) -> (r: Float, g: Float, b: Float) {
    guard s != 0 else { return (l, l, l) }         // achromatic
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s
    let p = 2 * l - q
    func hue2rgb(_ t0: Float) -> Float {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }
    return (hue2rgb(h + 1.0 / 3.0), hue2rgb(h), hue2rgb(h - 1.0 / 3.0))
}

/// Monotone cubic Hermite interpolation (Fritsch–Carlson) through `points`
/// (sorted by x, in 0...1). Avoids the overshoot a plain cubic spline would
/// introduce between tone-curve control points.
func cubicHermiteInterpolate(_ points: [(Float, Float)], at x: Float) -> Float {
    let n = points.count
    guard n > 1 else { return points.first?.1 ?? x }
    if x <= points[0].0 { return points[0].1 }
    if x >= points[n - 1].0 { return points[n - 1].1 }

    // Secant slopes between consecutive points.
    var delta = [Float](repeating: 0, count: n - 1)
    for i in 0..<(n - 1) {
        let dx = points[i + 1].0 - points[i].0
        delta[i] = dx != 0 ? (points[i + 1].1 - points[i].1) / dx : 0
    }

    // Tangents (Fritsch–Carlson monotone).
    var m = [Float](repeating: 0, count: n)
    m[0] = delta[0]
    m[n - 1] = delta[n - 2]
    for i in 1..<(n - 1) {
        if delta[i - 1] * delta[i] <= 0 {
            m[i] = 0
        } else {
            m[i] = (delta[i - 1] + delta[i]) / 2
        }
    }
    for i in 0..<(n - 1) where delta[i] == 0 {
        m[i] = 0; m[i + 1] = 0
    }

    // Locate the interval containing x.
    var k = 0
    for i in 0..<(n - 1) where x >= points[i].0 && x < points[i + 1].0 { k = i; break }

    let x0 = points[k].0, x1 = points[k + 1].0
    let y0 = points[k].1, y1 = points[k + 1].1
    let h = x1 - x0
    let t = (x - x0) / h
    let t2 = t * t, t3 = t2 * t
    let h00 = 2 * t3 - 3 * t2 + 1
    let h10 = t3 - 2 * t2 + t
    let h01 = -2 * t3 + 3 * t2
    let h11 = t3 - t2
    return h00 * y0 + h10 * h * m[k] + h01 * y1 + h11 * h * m[k + 1]
}
