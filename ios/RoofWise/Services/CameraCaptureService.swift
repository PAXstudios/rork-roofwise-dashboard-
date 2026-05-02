import SwiftUI
import AVFoundation
import UIKit

/// Captures roof photos. Uses AVCapturePhotoOutput on real devices,
/// falls back to a synthesized stylized roof tile in the cloud simulator.
@Observable
final class CameraCaptureService: NSObject {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var configured: Bool = false
    private var continuation: CheckedContinuation<UIImage, Never>?

    var hasCamera: Bool { CameraProxyView.hasRearCamera }

    func ensureConfigured() {
        guard hasCamera, !configured else { return }
        session.beginConfiguration()
        if let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
        configured = true
    }

    func capture(slope: SlopeType, pitchDegrees: Double, elevationFeet: Double) async -> UIImage {
        if hasCamera {
            ensureConfigured()
            let image: UIImage = await withCheckedContinuation { (cont: CheckedContinuation<UIImage, Never>) in
                self.continuation = cont
                let settings = AVCapturePhotoSettings()
                self.output.capturePhoto(with: settings, delegate: self)
            }
            return image
        }
        return Self.synthesizePlaceholder(slope: slope,
                                          pitchDegrees: pitchDegrees,
                                          elevationFeet: elevationFeet)
    }

    static func synthesizePlaceholder(slope: SlopeType,
                                      pitchDegrees: Double,
                                      elevationFeet: Double) -> UIImage {
        let size = CGSize(width: 640, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Sky to slope gradient
            let colors = [
                UIColor(red: 0.12, green: 0.16, blue: 0.28, alpha: 1).cgColor,
                UIColor(red: 0.32, green: 0.22, blue: 0.18, alpha: 1).cgColor,
                UIColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 1).cgColor
            ] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors,
                                  locations: [0, 0.4, 1])!
            cg.drawLinearGradient(grad,
                                  start: .zero,
                                  end: CGPoint(x: 0, y: size.height),
                                  options: [])

            // Shingle rows
            let rows = 22
            let cols = 14
            let dx = size.width / CGFloat(cols)
            let dy = (size.height * 0.7) / CGFloat(rows)
            let yStart = size.height * 0.28
            for r in 0..<rows {
                for c in 0..<cols {
                    let stagger: CGFloat = r.isMultiple(of: 2) ? dx / 2 : 0
                    let x = CGFloat(c) * dx + stagger
                    let y = yStart + CGFloat(r) * dy
                    let rect = CGRect(x: x, y: y, width: dx * 0.94, height: dy * 0.88)
                    let darkness = CGFloat.random(in: 0.18...0.34)
                    UIColor(red: darkness, green: darkness * 0.85, blue: darkness * 0.75, alpha: 1).setFill()
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: 2)
                    path.fill()
                }
            }

            // Random hail dots
            for _ in 0..<28 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: yStart...(size.height - 20))
                let r = CGFloat.random(in: 4...10)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(ovalIn: CGRect(x: x, y: y, width: r, height: r)).fill()
            }

            // Slope label
            let label = "\(slope.rawValue) · \(Int(pitchDegrees))° · \(Int(elevationFeet)) ft"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let bgRect = CGRect(x: 24, y: 24, width: size.width - 48, height: 38)
            UIColor.black.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: bgRect, cornerRadius: 10).fill()
            str.draw(at: CGPoint(x: 38, y: 32))
        }
    }
}

extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image: UIImage = {
            if let data = photo.fileDataRepresentation(),
               let img = UIImage(data: data) {
                return img
            }
            return UIImage()
        }()
        Task { @MainActor in
            self.continuation?.resume(returning: image)
            self.continuation = nil
        }
    }
}
