import CoreImage
import Foundation

/// Loads / generates 3D LUTs and exposes them as a ready-to-use `CIFilter`
/// (`CIColorCubeWithColorSpace`). Procedural LUTs approximate Leica color
/// rendering without shipping any `.cube` files; real `.cube` files can be
/// loaded with `load(cubeURL:)`.
final class LUTFilter {

    enum Kind {
        case classic, monochrom, contemporary
    }

    /// In-memory cache so each cube is only built once.
    private static var cache: [String: Data] = [:]
    private static let cacheQueue = DispatchQueue(label: "lutfilter.cache")
    private static let dimension = 33

    private let data: Data
    private let dimension: Int

    private init(data: Data, dimension: Int) {
        self.data = data
        self.dimension = dimension
    }

    // MARK: - Factory ------------------------------------------------------

    static func procedural(_ kind: Kind) -> LUTFilter {
        let key = "proc-\(kind)"
        let data = cacheQueue.sync { () -> Data in
            if let cached = cache[key] { return cached }
            let built = makeCube(kind, dimension: dimension)
            cache[key] = built
            return built
        }
        return LUTFilter(data: data, dimension: dimension)
    }

    /// Parse a `.cube` text file (size 2..64). Returns nil on malformed input.
    static func load(cubeURL url: URL) -> LUTFilter? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var size = 0
        var values: [Float] = []
        values.reserveCapacity(33 * 33 * 33 * 3)

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("TITLE") || line.hasPrefix("DOMAIN") { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                size = Int(line.split(separator: " ").last ?? "") ?? 0
                continue
            }
            if line.hasPrefix("LUT_1D_SIZE") { return nil } // 1D unsupported
            let comps = line.split(separator: " ").compactMap { Float($0) }
            if comps.count == 3 { values.append(contentsOf: comps) }
        }

        guard size >= 2, values.count == size * size * size * 3 else { return nil }

        // .cube is R-fastest; CIColorCube wants RGBA, also R-fastest. Add alpha.
        var rgba = [Float](repeating: 0, count: size * size * size * 4)
        for i in 0..<(size * size * size) {
            rgba[i * 4 + 0] = values[i * 3 + 0]
            rgba[i * 4 + 1] = values[i * 3 + 1]
            rgba[i * 4 + 2] = values[i * 3 + 2]
            rgba[i * 4 + 3] = 1.0
        }
        let data = rgba.withUnsafeBytes { Data($0) }
        return LUTFilter(data: data, dimension: size)
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

    /// Builds an `N×N×N` RGBA float cube. The mapping is hand-tuned per kind to
    /// emulate the color science described in the spec.
    private static func makeCube(_ kind: Kind, dimension n: Int) -> Data {
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        let last = Float(n - 1)
        var offset = 0
        // Cube memory layout: blue is the slowest-varying axis, red the fastest.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    var rr = Float(r) / last
                    var gg = Float(g) / last
                    var bb = Float(b) / last
                    (rr, gg, bb) = shape(kind, rr, gg, bb)
                    cube[offset + 0] = clamp(rr)
                    cube[offset + 1] = clamp(gg)
                    cube[offset + 2] = clamp(bb)
                    cube[offset + 3] = 1.0
                    offset += 4
                }
            }
        }
        return cube.withUnsafeBytes { Data($0) }
    }

    /// Per-kind color transform applied to a normalized RGB triple.
    private static func shape(_ kind: Kind, _ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        switch kind {
        case .monochrom:
            // True luminance with a lifted black point and a gentle S-curve for
            // the "exceptional tonal gradation" look.
            var y = 0.30 * r + 0.59 * g + 0.11 * b
            y = filmCurve(y, shoulder: 0.7)
            y = 0.05 + y * 0.95                 // lift blacks to ~5%
            return (y, y, y)

        case .classic:
            var (nr, ng, nb) = (r, g, b)
            // Warm highlights, cool deep shadows.
            let lum = 0.30 * r + 0.59 * g + 0.11 * b
            let highlight = smoothstep(0.6, 1.0, lum)
            let shadow = 1.0 - smoothstep(0.0, 0.35, lum)
            nr += highlight * 0.04              // warm highlights (R/Y up)
            ng += highlight * 0.02
            nb += shadow * 0.03                 // cool deep shadows (B up)
            // Boost red luminance slightly for flattering skin.
            nr += 0.025 * (1.0 - abs(r - 0.6) * 1.4).clampedToZero
            // Shift yellow-greens toward warmer olive.
            if g > r && g > b { ng -= 0.03; nr += 0.015 }
            // Tame extreme blue/cyan saturation.
            if b > 0.5 && b > r { nb -= (b - 0.5) * 0.18; ng += (b - 0.5) * 0.04 }
            // Film highlight shoulder.
            nr = filmCurve(nr, shoulder: 0.78)
            ng = filmCurve(ng, shoulder: 0.78)
            nb = filmCurve(nb, shoulder: 0.78)
            return (nr, ng, nb)

        case .contemporary:
            var (nr, ng, nb) = (r, g, b)
            let lum = 0.30 * r + 0.59 * g + 0.11 * b
            // Slightly cooler, cleaner whites, mild desaturation.
            let mean = (nr + ng + nb) / 3.0
            nr = mix(nr, mean, 0.08)
            ng = mix(ng, mean, 0.06)
            nb = mix(nb, mean, 0.04)
            nb += smoothstep(0.5, 1.0, lum) * 0.015   // cool, clean highlights
            nr = filmCurve(nr, shoulder: 0.85)
            ng = filmCurve(ng, shoulder: 0.85)
            nb = filmCurve(nb, shoulder: 0.85)
            return (nr, ng, nb)
        }
    }

    // MARK: - Math helpers -------------------------------------------------

    /// Soft highlight-shoulder curve. `shoulder` is where compression begins.
    private static func filmCurve(_ x: Float, shoulder: Float) -> Float {
        if x <= shoulder { return x }
        let t = (x - shoulder) / (1.0 - shoulder)
        // ease-out: approaches but never blows fully to 1.0
        let compressed = 1.0 - (1.0 - t) * (1.0 - t)
        return shoulder + compressed * (1.0 - shoulder) * 0.92
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = ((x - edge0) / (edge1 - edge0)).clampedUnit
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    private static func clamp(_ x: Float) -> Float { min(1, max(0, x)) }
}

private extension Float {
    var clampedUnit: Float { Swift.min(1, Swift.max(0, self)) }
    var clampedToZero: Float { Swift.max(0, self) }
}
