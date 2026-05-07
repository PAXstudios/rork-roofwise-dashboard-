import Foundation
import UIKit
import CoreImage

/// Compression ladder used when uploading photos to the Rork toolkit proxy.
/// Two paths:
///  - `.full`  — saved/full inspection photo: bigger pixels, higher quality
///    so Gemini finds every hail strike. Used by `analyzeFull`.
///  - `.live`  — live camera frame for AR overlay: small + fast for low latency.
///
/// Always normalizes EXIF orientation before encoding so that marker
/// coordinates returned by Gemini line up with the same image we display.
enum ImageResize {
    enum Profile {
        case full
        case live
    }

    private static let fullLadder: [(maxPixel: CGFloat, quality: CGFloat)] = [
        (2560, 0.92), (2304, 0.91), (2048, 0.90), (1792, 0.88),
        (1536, 0.86), (1280, 0.82), (1024, 0.80), (832, 0.76), (640, 0.72)
    ]
    private static let liveLadder: [(maxPixel: CGFloat, quality: CGFloat)] = [
        (1024, 0.74), (832, 0.72), (768, 0.70), (640, 0.65), (512, 0.60)
    ]

    static func encodedJPEGBase64(from image: UIImage,
                                  profile: Profile = .full,
                                  maxBytes: Int? = nil) -> String? {
        let normalized = image.normalizedOrientation()
        let aiReady = damageAnalysisOptimizedImage(from: normalized)
        let ladder = profile == .full ? fullLadder : liveLadder
        let cap = maxBytes ?? (profile == .full ? 3_000_000 : 600_000)
        for step in ladder {
            guard let resized = resize(image: aiReady, maxEdge: step.maxPixel) else { continue }
            guard let data = resized.jpegData(compressionQuality: step.quality) else { continue }
            if data.count <= cap { return data.base64EncodedString() }
        }
        return nil
    }

    private static func resize(image: UIImage, maxEdge: CGFloat) -> UIImage? {
        let size = image.size
        let scale = min(maxEdge / max(size.width, size.height), 1.0)
        if scale >= 1.0 {
            // Still re-render so EXIF orientation is baked into pixels.
            return render(image: image, size: size)
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return render(image: image, size: newSize)
    }

    /// Prepares roof photos for visual damage localization without changing the
    /// aspect ratio, so normalized AI coordinates still map back onto the original
    /// photo. The goal is to preserve granule texture, expose dark bruising, and
    /// sharpen shingle edges rather than over-compressing into a blurry bitmap.
    private static func damageAnalysisOptimizedImage(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)
        let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])

        let colorAdjusted: CIImage = {
            guard let filter = CIFilter(name: "CIColorControls") else { return input }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(1.22, forKey: kCIInputContrastKey)
            filter.setValue(1.05, forKey: kCIInputSaturationKey)
            filter.setValue(0.018, forKey: kCIInputBrightnessKey)
            return filter.outputImage ?? input
        }()

        let luminanceSharpened: CIImage = {
            guard let filter = CIFilter(name: "CISharpenLuminance") else { return colorAdjusted }
            filter.setValue(colorAdjusted, forKey: kCIInputImageKey)
            filter.setValue(0.62, forKey: kCIInputSharpnessKey)
            return filter.outputImage ?? colorAdjusted
        }()

        let edgeSharpened: CIImage = {
            guard let filter = CIFilter(name: "CIUnsharpMask") else { return luminanceSharpened }
            filter.setValue(luminanceSharpened, forKey: kCIInputImageKey)
            filter.setValue(0.78, forKey: kCIInputIntensityKey)
            filter.setValue(1.20, forKey: kCIInputRadiusKey)
            return filter.outputImage ?? luminanceSharpened
        }()

        guard let output = context.createCGImage(edgeSharpened, from: input.extent) else { return image }
        return UIImage(cgImage: output, scale: 1.0, orientation: .up)
    }

    private static func render(image: UIImage, size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension UIImage {
    /// Returns a copy with `.up` orientation by re-rendering pixels.
    /// `UIImage.draw(in:)` honors `imageOrientation`, so the resulting bitmap
    /// is what a downstream consumer (Gemini Vision, SwiftUI Image) actually sees.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out ?? self
    }
}
