import UIKit
import CoreGraphics

/// Result of a pre-analysis photo-quality check.
struct PhotoQuality {
    /// Variance of the Laplacian over a downsampled luminance buffer.
    /// Higher = sharper. Empirically < ~90 reads as blurry for roof close-ups.
    let blurScore: Double
    /// Mean luminance, 0–255.
    let brightnessScore: Double
    /// Composite verdict — safe to send to the analyzer.
    let isAcceptable: Bool
    /// Human-readable problems for the recapture sheet (empty when acceptable).
    let issues: [String]

    static let acceptable = PhotoQuality(blurScore: .greatestFiniteMagnitude,
                                         brightnessScore: 128,
                                         isAcceptable: true,
                                         issues: [])
}

/// Cheap, on-device photo-quality gate run before a captured frame is sent to
/// Gemini. Garbage-in is the single biggest source of bad AI analysis, so we
/// catch blurry / too-dark / blown-out frames and offer a recapture.
///
/// Implementation is plain CoreGraphics on a 256px downsample (≈65k px) so it's
/// fast, deterministic, and free of platform-imaging-API surprises.
enum PhotoQualityService {

    // Tunables — conservative so we only block clearly bad frames.
    static let blurThreshold: Double = 90        // variance-of-Laplacian floor
    static let darkThreshold: Double = 45        // mean luminance floor
    static let brightThreshold: Double = 222     // mean luminance ceiling
    private static let sampleEdge = 256

    static func evaluate(_ image: UIImage) -> PhotoQuality {
        guard let gray = luminanceBuffer(from: image, maxEdge: sampleEdge) else {
            // Can't read pixels — don't block the inspector; treat as acceptable.
            return .acceptable
        }

        let brightness = mean(gray.pixels)
        let blur = laplacianVariance(gray.pixels, width: gray.width, height: gray.height)

        var issues: [String] = []
        if blur < blurThreshold { issues.append("Photo looks blurry — hold steadier or move closer.") }
        if brightness < darkThreshold { issues.append("Too dark — find better light or move into the sun.") }
        if brightness > brightThreshold { issues.append("Overexposed — too much glare to read the surface.") }

        return PhotoQuality(blurScore: blur,
                            brightnessScore: brightness,
                            isAcceptable: issues.isEmpty,
                            issues: issues)
    }

    // MARK: - Pixel helpers

    private struct GrayBuffer { let pixels: [Double]; let width: Int; let height: Int }

    /// Downsample to `maxEdge` and return an 8-bit luminance buffer as Doubles.
    private static func luminanceBuffer(from image: UIImage, maxEdge: Int) -> GrayBuffer? {
        guard let cg = image.cgImage else { return nil }
        let srcW = cg.width, srcH = cg.height
        guard srcW > 0, srcH > 0 else { return nil }

        let scale = Double(maxEdge) / Double(max(srcW, srcH))
        let w = max(1, Int((Double(srcW) * scale).rounded()))
        let h = max(1, Int((Double(srcH) * scale).rounded()))

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bmp = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &rgba, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: bmp) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var lum = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Double(rgba[i * 4]); let g = Double(rgba[i * 4 + 1]); let b = Double(rgba[i * 4 + 2])
            // Rec. 601 luma.
            lum[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }
        return GrayBuffer(pixels: lum, width: w, height: h)
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Variance of the 3×3 Laplacian response — the standard sharpness metric.
    private static func laplacianVariance(_ p: [Double], width w: Int, height h: Int) -> Double {
        guard w > 2, h > 2 else { return .greatestFiniteMagnitude }
        var resp = [Double]()
        resp.reserveCapacity((w - 2) * (h - 2))
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = p[y * w + x]
                let up = p[(y - 1) * w + x]
                let down = p[(y + 1) * w + x]
                let left = p[y * w + (x - 1)]
                let right = p[y * w + (x + 1)]
                resp.append((up + down + left + right) - 4 * c)
            }
        }
        let m = mean(resp)
        let varc = resp.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(resp.count)
        return varc
    }
}
