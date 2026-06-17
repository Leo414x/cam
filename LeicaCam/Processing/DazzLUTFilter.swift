import CoreImage
import UIKit

enum DazzLUTError: Error {
    case resourceNotFound(String)
    case decodeFailed(String)
}

/// Decodes a Dazz-format LUT strip into `CIColorCube` float data.
///
/// The strip is a 256×16 image encoding a 16×16×16 cube:
/// ```
///   x tile        = blue index   (0...15)
///   x inside tile = red index    (0...15)
///   y             = green index  (0...15)
///   source pixel: x = blue * 16 + red,  y = green
/// ```
enum DazzLUTStripLoader {
    static let sourceSize = 16   // the strip encodes a 16-cube

    /// Returns interleaved RGBA Float32 cube data (0...1) in CIColorCube order:
    /// `index = ((b * size*size) + (g * size) + r) * 4`.
    /// For `size == 16` the strip is read directly; otherwise it is trilinearly
    /// resampled up to `size` (e.g. 33).
    static func cubeData(resourceName: String, size: Int) throws -> Data {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path),
              let cg = image.cgImage else {
            throw DazzLUTError.resourceNotFound(resourceName)
        }

        let w = cg.width, h = cg.height
        let expected = sourceSize * sourceSize          // 256 wide, 16 tall
        guard w == expected, h == sourceSize else {
            throw DazzLUTError.decodeFailed("\(resourceName): expected \(expected)x\(sourceSize), got \(w)x\(h)")
        }

        // Draw into a known RGBA8 buffer so we can read raw bytes.
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bmp = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs, bitmapInfo: bmp) else {
            throw DazzLUTError.decodeFailed("\(resourceName): could not create bitmap context")
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Sample one source texel of the 16-cube at integer (r,g,b).
        func sample(_ r: Int, _ g: Int, _ b: Int) -> (Float, Float, Float) {
            let x = b * sourceSize + r
            let y = g
            let i = (y * w + x) * 4
            return (Float(px[i]) / 255.0, Float(px[i + 1]) / 255.0, Float(px[i + 2]) / 255.0)
        }

        var cube = [Float](repeating: 0, count: size * size * size * 4)

        if size == sourceSize {
            for b in 0..<size {
                for g in 0..<size {
                    for r in 0..<size {
                        let (rr, gg, bb) = sample(r, g, b)
                        let idx = ((b * size * size) + (g * size) + r) * 4
                        cube[idx + 0] = rr; cube[idx + 1] = gg; cube[idx + 2] = bb; cube[idx + 3] = 1
                    }
                }
            }
        } else {
            // Trilinear resample the 16-cube up to `size`.
            let last = Float(size - 1)
            let srcMax = sourceSize - 1
            for b in 0..<size {
                for g in 0..<size {
                    for r in 0..<size {
                        let (rr, gg, bb) = trilinear(
                            rf: Float(r) / last * Float(srcMax),
                            gf: Float(g) / last * Float(srcMax),
                            bf: Float(b) / last * Float(srcMax),
                            sample: sample, srcMax: srcMax)
                        let idx = ((b * size * size) + (g * size) + r) * 4
                        cube[idx + 0] = rr; cube[idx + 1] = gg; cube[idx + 2] = bb; cube[idx + 3] = 1
                    }
                }
            }
        }

        return cube.withUnsafeBytes { Data($0) }
    }

    private static func trilinear(rf: Float, gf: Float, bf: Float,
                                  sample: (Int, Int, Int) -> (Float, Float, Float),
                                  srcMax: Int) -> (Float, Float, Float) {
        let r0 = Int(rf.rounded(.down)), g0 = Int(gf.rounded(.down)), b0 = Int(bf.rounded(.down))
        let r1 = min(r0 + 1, srcMax), g1 = min(g0 + 1, srcMax), b1 = min(b0 + 1, srcMax)
        let dr = rf - Float(r0), dg = gf - Float(g0), db = bf - Float(b0)

        func lerp(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
        let c000 = sample(r0, g0, b0), c100 = sample(r1, g0, b0)
        let c010 = sample(r0, g1, b0), c110 = sample(r1, g1, b0)
        let c001 = sample(r0, g0, b1), c101 = sample(r1, g0, b1)
        let c011 = sample(r0, g1, b1), c111 = sample(r1, g1, b1)
        let c00 = lerp(c000, c100, dr), c10 = lerp(c010, c110, dr)
        let c01 = lerp(c001, c101, dr), c11 = lerp(c011, c111, dr)
        let c0 = lerp(c00, c10, dg), c1 = lerp(c01, c11, dg)
        return lerp(c0, c1, db)
    }
}

/// Applies bundled Dazz LUTs via `CIColorCube`, caching decoded cube data so the
/// strip is parsed once (not per frame). Preview and export share this path.
final class DazzLUTFilter {
    static let shared = DazzLUTFilter()
    private init() {}

    /// Cube dimension fed to `CIColorCube`. 16 = exact source resolution.
    private let cubeSize = 16

    private var cache: [String: Data] = [:]
    private let cacheQueue = DispatchQueue(label: "dazzlut.cache")

    private func cube(for style: DazzSingleLUTStyle) throws -> Data {
        let key = "\(style.lutResourceName)-\(cubeSize)"
        return try cacheQueue.sync {
            if let cached = cache[key] { return cached }
            let data = try DazzLUTStripLoader.cubeData(resourceName: style.lutResourceName, size: cubeSize)
            cache[key] = data
            return data
        }
    }

    /// Applies the style's LUT. `intensity < 1` blends the LUT output back over
    /// the original — `output = mix(original, lutOutput, intensity)` — matching
    /// the reference shader's alpha mix.
    func applyDazzLUT(_ input: CIImage,
                      style: DazzSingleLUTStyle,
                      intensity: Float = 1.0) throws -> CIImage {
        let data = try cube(for: style)

        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(cubeSize, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        guard let lutOutput = filter.outputImage else { return input }

        let t = max(0, min(1, intensity))
        guard t < 1 else { return lutOutput }

        // mix(original, lutOutput, t): fade the LUT layer to alpha = t and
        // source-over the original beneath it.
        let faded = lutOutput.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(t))
        ])
        return faded.composited(over: input)
    }
}
