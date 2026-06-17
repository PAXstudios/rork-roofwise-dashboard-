import CoreImage
import UIKit

/// Stage 0 of the detection pipeline — a fully on-device image quality gate
/// that rejects photos too poor for reliable forensic analysis BEFORE any
/// (paid, slow) Gemini call is made. Catches blur, under/over-exposure, and
/// too-low resolution.
enum ImageQualityGate {

    // Tunable thresholds — conservative so we don't reject usable field photos.
    private static let minDimension: Int = 400
    private static let minBrightness: Double = 0.05
    private static let maxBrightness: Double = 0.97
    /// Mean edge energy below this is treated as out-of-focus.
    private static let minSharpness: Double = 0.012

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Evaluates an image on-device. Pure CPU/GPU work — no network.
    static func evaluate(_ image: UIImage) -> ImageQualityReport {
        let minDim = Int(min(image.size.width, image.size.height) * image.scale)

        guard let ciImage = CIImage(image: image) else {
            return ImageQualityReport(
                passed: false,
                sharpness: 0,
                brightness: 0,
                minDimension: minDim,
                reasons: ["Could not read the image."]
            )
        }

        let brightness = averageBrightness(ciImage)
        let sharpness = edgeEnergy(ciImage)

        var reasons: [String] = []
        if minDim < minDimension {
            reasons.append("Resolution too low — move closer or use a higher-quality photo.")
        }
        if brightness < minBrightness {
            reasons.append("Photo is too dark to analyze.")
        } else if brightness > maxBrightness {
            reasons.append("Photo is overexposed / washed out.")
        }
        if sharpness < minSharpness {
            reasons.append("Photo looks out of focus or blurry — hold steady and retake.")
        }

        return ImageQualityReport(
            passed: reasons.isEmpty,
            sharpness: sharpness,
            brightness: brightness,
            minDimension: minDim,
            reasons: reasons
        )
    }

    // MARK: - Metrics

    /// Mean luminance in 0-1 via CIAreaAverage on a grayscale conversion.
    private static func averageBrightness(_ image: CIImage) -> Double {
        guard let mono = CIFilter(name: "CIPhotoEffectMono", parameters: [kCIInputImageKey: image])?.outputImage else {
            return 0.5
        }
        return areaAverageLuma(mono, extent: image.extent)
    }

    /// Mean edge energy (sharpness proxy) — apply CIEdges then average the
    /// result. Blurry images produce weak edges → low mean.
    private static func edgeEnergy(_ image: CIImage) -> Double {
        guard let edges = CIFilter(name: "CIEdges", parameters: [
            kCIInputImageKey: image,
            "inputIntensity": 1.0
        ])?.outputImage else {
            return 1.0 // fail open — don't block when we can't measure
        }
        return areaAverageLuma(edges, extent: image.extent)
    }

    /// Reduces an image to a single averaged pixel and returns its luminance 0-1.
    private static func areaAverageLuma(_ image: CIImage, extent: CGRect) -> Double {
        let safeExtent = extent.isInfinite ? image.extent : extent
        guard !safeExtent.isInfinite,
              let avg = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: image,
                kCIInputExtentKey: CIVector(cgRect: safeExtent)
              ])?.outputImage else {
            return 0.5
        }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(avg,
                        toBitmap: &bitmap,
                        rowBytes: 4,
                        bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8,
                        colorSpace: nil)
        let r = Double(bitmap[0]) / 255.0
        let g = Double(bitmap[1]) / 255.0
        let b = Double(bitmap[2]) / 255.0
        // Rec. 709 luma.
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
