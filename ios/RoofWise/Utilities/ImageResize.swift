import Foundation
import UIKit

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
        (1600, 0.85), (1280, 0.82), (1024, 0.78), (832, 0.74), (640, 0.70)
    ]
    private static let liveLadder: [(maxPixel: CGFloat, quality: CGFloat)] = [
        (768, 0.70), (640, 0.65), (512, 0.60)
    ]

    static func encodedJPEGBase64(from image: UIImage,
                                  profile: Profile = .full,
                                  maxBytes: Int? = nil) -> String? {
        let normalized = image.normalizedOrientation()
        let ladder = profile == .full ? fullLadder : liveLadder
        let cap = maxBytes ?? (profile == .full ? 3_000_000 : 600_000)
        for step in ladder {
            guard let resized = resize(image: normalized, maxEdge: step.maxPixel) else { continue }
            guard let data = resized.jpegData(compressionQuality: step.quality) else { continue }
            if data.count <= cap { return data.base64EncodedString() }
        }
        return nil
    }

    /// Downsamples to `longestEdge` and returns JPEG `Data` at `quality`.
    /// Used by the live AR analyzer to send small, fast frames to Gemini.
    static func encodedJPEGData(from image: UIImage,
                                longestEdge: CGFloat,
                                quality: CGFloat) -> Data? {
        let normalized = image.normalizedOrientation()
        guard let resized = resize(image: normalized, maxEdge: longestEdge) else { return nil }
        return resized.jpegData(compressionQuality: quality)
    }

    private static func resize(image: UIImage, maxEdge: CGFloat) -> UIImage? {
        let size = image.size
        let scale = min(maxEdge / max(size.width, size.height), 1.0)
        if scale >= 1.0 {
            // Still re-render so EXIF orientation is baked into pixels.
            return image
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out
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
