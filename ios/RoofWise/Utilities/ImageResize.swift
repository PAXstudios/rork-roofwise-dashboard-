import Foundation
import UIKit

/// Compression ladder used when uploading photos to the Rork toolkit proxy.
/// Tries progressively smaller images until one fits under `maxBytes`.
enum ImageResize {
    private static let ladder: [(maxPixel: CGFloat, quality: CGFloat)] = [
        (1280, 0.82), (1024, 0.78), (832, 0.74), (640, 0.70), (512, 0.65)
    ]

    static func encodedJPEGBase64(from image: UIImage, maxBytes: Int = 3_000_000) -> String? {
        for step in ladder {
            guard let resized = resize(image: image, maxEdge: step.maxPixel) else { continue }
            guard let data = resized.jpegData(compressionQuality: step.quality) else { continue }
            if data.count <= maxBytes { return data.base64EncodedString() }
        }
        return nil
    }

    private static func resize(image: UIImage, maxEdge: CGFloat) -> UIImage? {
        let size = image.size
        let scale = min(maxEdge / max(size.width, size.height), 1.0)
        if scale >= 1.0 { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out
    }
}
