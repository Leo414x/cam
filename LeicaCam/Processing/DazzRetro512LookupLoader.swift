import CoreImage
import UIKit

enum DazzRetro512LookupError: Error {
    case notFound(String)
    case decodeFailed(String)
}

/// Decodes a 512×512 GPUImage-style lookup **atlas** into `CIColorCube` data.
/// This is a DIFFERENT format from the 256×16 Dazz/Kuji strip (`DazzLUTStripLoader`)
/// and must not be confused with it.
///
/// ```
///   512×512 atlas = 8×8 tiles, each tile 64×64  → 64³ cube
///   blue  selects the tile index (0...63)
///   red   maps to x inside the tile
///   green maps to y inside the tile
///   pixelX = (tile % 8) * 64 + red * 63
///   pixelY = (tile / 8) * 64 + green * 63
/// ```
enum DazzRetro512LookupLoader {
    static let atlasSize = 512
    static let tileGrid = 8
    static let tileSize = 64

    /// Builds interleaved RGBA Float32 cube data (0...1) in CIColorCube order:
    /// `index = ((b*size*size) + (g*size) + r) * 4`. The 64-tile atlas is
    /// trilinearly sampled (bilinear inside a tile, linear across blue tiles) so
    /// any `size` (we use 33) stays smooth.
    static func cubeData(resourceName: String, size: Int) throws -> Data {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path),
              let cg = image.cgImage else {
            throw DazzRetro512LookupError.notFound(resourceName)
        }
        let w = cg.width, h = cg.height
        guard w == atlasSize, h == atlasSize else {
            throw DazzRetro512LookupError.decodeFailed("\(resourceName): expected 512x512, got \(w)x\(h)")
        }

        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw DazzRetro512LookupError.decodeFailed("\(resourceName): bitmap context")
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let maxTile = tileGrid * tileGrid - 1     // 63
        let inner = Float(tileSize - 1)           // 63

        func bilinear(_ x: Float, _ y: Float) -> (Float, Float, Float) {
            let x0 = Int(x), y0 = Int(y)
            let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
            let dx = x - Float(x0), dy = y - Float(y0)
            func p(_ xx: Int, _ yy: Int) -> (Float, Float, Float) {
                let i = (yy * w + xx) * 4
                return (Float(px[i]) / 255, Float(px[i + 1]) / 255, Float(px[i + 2]) / 255)
            }
            func lp(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
                (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
            }
            return lp(lp(p(x0, y0), p(x1, y0), dx), lp(p(x0, y1), p(x1, y1), dx), dy)
        }
        func sampleTile(_ tile: Int, _ rn: Float, _ gn: Float) -> (Float, Float, Float) {
            let tx = tile % tileGrid, ty = tile / tileGrid
            return bilinear(Float(tx * tileSize) + rn * inner, Float(ty * tileSize) + gn * inner)
        }

        var cube = [Float](repeating: 0, count: size * size * size * 4)
        let last = Float(size - 1)
        for b in 0..<size {
            let bi = Float(b) / last * Float(maxTile)
            let t1 = Int(bi), t2 = min(Int(bi) + 1, maxTile), mix = bi - Float(t1)
            for g in 0..<size {
                let gn = Float(g) / last
                for r in 0..<size {
                    let rn = Float(r) / last
                    let c1 = sampleTile(t1, rn, gn)
                    let c2 = sampleTile(t2, rn, gn)
                    let idx = ((b * size * size) + (g * size) + r) * 4
                    cube[idx + 0] = c1.0 + (c2.0 - c1.0) * mix
                    cube[idx + 1] = c1.1 + (c2.1 - c1.1) * mix
                    cube[idx + 2] = c1.2 + (c2.2 - c1.2) * mix
                    cube[idx + 3] = 1
                }
            }
        }
        return cube.withUnsafeBytes { Data($0) }
    }
}

/// Applies a 512-atlas Polaroid LUT via `CIColorCube`, caching decoded cube data
/// by `resourceName + cubeSize` (decoded once, not per frame).
final class DazzRetroLUTFilter {
    static let shared = DazzRetroLUTFilter()
    private init() {}

    /// 33 keeps memory modest (8 cached cubes ≈ 4.6 MB) and the live video
    /// pipeline fast; the atlas is trilinearly resampled so quality holds.
    let cubeSize = 33

    private var cache: [String: Data] = [:]
    private let cacheQueue = DispatchQueue(label: "dazzretro.lut.cache")

    func apply(_ input: CIImage, resourceName: String, intensity: Float) -> CIImage {
        let key = "\(resourceName)-\(cubeSize)"
        let data: Data
        do {
            data = try cacheQueue.sync {
                if let cached = cache[key] { return cached }
                let d = try DazzRetro512LookupLoader.cubeData(resourceName: resourceName, size: cubeSize)
                cache[key] = d
                return d
            }
        } catch {
            return input   // never blank out on a missing/!valid asset
        }

        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(cubeSize, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        guard let out = filter.outputImage else { return input }

        let t = max(0, min(1, intensity))
        guard t < 1 else { return out }
        // mix(original, lut, t)
        let faded = out.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(t))
        ])
        return faded.composited(over: input)
    }
}
