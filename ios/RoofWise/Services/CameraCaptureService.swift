import SwiftUI
import AVFoundation
import Vision
import UIKit

/// Manages the live camera session, runs `VNDetectRectanglesRequest` on every
/// frame to find shingle-shaped quads, and captures still photos for AI grading.
///
/// Detection state (`detectionRects`, `totalUniqueShingles`, `squaresCovered`)
/// is published on the main actor and consumed by the camera viewfinder
/// overlay. In the cloud simulator (no rear camera) the service runs a mock
/// detection loop so the UI still feels alive.
@Observable
final class CameraCaptureService: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "roofwise.camera.video", qos: .userInitiated)
    private var configured: Bool = false
    private var photoContinuation: CheckedContinuation<UIImage, Never>?

    // MARK: - Live detection state

    /// Current frame's detected shingles in UIKit-normalized coords (0..1, top-left origin).
    var detectionRects: [CGRect] = []

    /// Per-detection confidence (0..1), parallel to `detectionRects`.
    var detectionConfidences: [Double] = []

    /// Cumulative count of unique shingles spotted across the session.
    var totalUniqueShingles: Int = 0

    /// Cumulative coverage expressed as 100 sq ft "roofing squares".
    var squaresCovered: Int = 0

    /// Coverage 0..1 within a roofing square (0 → empty, 1 → next square unlocked).
    var currentSquareProgress: Double = 0

    private var coverageCells = Set<Int>()
    private var uniqueShingleCells = Set<Int>()
    private static let gridDim: Int = 24

    private var mockTimer: Timer?
    private var activeDevice: AVCaptureDevice?

    var hasCamera: Bool { CameraProxyView.hasRearCamera }

    /// Current zoom factor (1, 2, 3...). Mock value used when running in the cloud simulator.
    var zoomFactor: CGFloat = 1.0

    func setZoom(_ factor: CGFloat) {
        zoomFactor = factor
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            let clamped = max(1.0, min(factor, min(device.activeFormat.videoMaxZoomFactor, 6.0)))
            device.ramp(toVideoZoomFactor: clamped, withRate: 4.0)
            device.unlockForConfiguration()
        } catch {
            // ignore — leave zoom at previous value
        }
    }

    // MARK: - Lifecycle

    func start() {
        if hasCamera {
            ensureConfigured()
        } else {
            startMockDetection()
        }
    }

    func stop() {
        mockTimer?.invalidate()
        mockTimer = nil
    }

    func ensureConfigured() {
        guard hasCamera, !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        if let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            activeDevice = device
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        configured = true
    }

    // MARK: - Photo capture

    func capture(slope: SlopeType, pitchDegrees: Double, elevationFeet: Double) async -> UIImage {
        if hasCamera {
            ensureConfigured()
            let image: UIImage = await withCheckedContinuation { (cont: CheckedContinuation<UIImage, Never>) in
                self.photoContinuation = cont
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
            return image
        }
        return Self.synthesizePlaceholder(slope: slope,
                                          pitchDegrees: pitchDegrees,
                                          elevationFeet: elevationFeet)
    }

    // MARK: - Coverage math

    /// Replaces the visible detections and accumulates spatial coverage.
    /// `rects` are normalized 0..1 in top-left UIKit space.
    func applyDetections(_ rects: [CGRect], confidences: [Double]) {
        detectionRects = rects
        detectionConfidences = confidences

        let dim = Self.gridDim
        var newUnique = 0

        for r in rects {
            let cx = max(0, min(dim - 1, Int(r.midX * CGFloat(dim))))
            let cy = max(0, min(dim - 1, Int(r.midY * CGFloat(dim))))
            let centerKey = cy * dim + cx
            if !uniqueShingleCells.contains(centerKey) {
                uniqueShingleCells.insert(centerKey)
                newUnique += 1
            }

            let x0 = max(0, Int(r.minX * CGFloat(dim)))
            let x1 = min(dim - 1, Int(r.maxX * CGFloat(dim)))
            let y0 = max(0, Int(r.minY * CGFloat(dim)))
            let y1 = min(dim - 1, Int(r.maxY * CGFloat(dim)))
            if x0 <= x1 && y0 <= y1 {
                for yy in y0...y1 {
                    for xx in x0...x1 {
                        coverageCells.insert(yy * dim + xx)
                    }
                }
            }
        }

        totalUniqueShingles += newUnique

        // A typical roof viewfinder at ~10 ft viewing distance covers ~200 sq ft.
        // Pitch is folded in by the inspector aiming — once cumulative cells hit
        // 50% of the frame grid we've documented one full 10x10 square.
        let totalCells = Double(dim * dim)
        let coverage = Double(coverageCells.count) / totalCells
        let coveredSqFt = coverage * 200.0
        let newSquares = Int(coveredSqFt / 100.0)
        squaresCovered = newSquares
        let progressInto = (coveredSqFt - Double(newSquares) * 100.0) / 100.0
        currentSquareProgress = max(0, min(1, progressInto))
    }

    func resetCoverage() {
        coverageCells.removeAll()
        uniqueShingleCells.removeAll()
        totalUniqueShingles = 0
        squaresCovered = 0
        currentSquareProgress = 0
        detectionRects = []
        detectionConfidences = []
    }

    // MARK: - Mock detection (cloud simulator)

    private func startMockDetection() {
        mockTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            guard let strong = self else { return }
            Task { @MainActor in strong.tickMock() }
        }
        mockTimer = timer
    }

    private func tickMock() {
        var rects: [CGRect] = []
        var confs: [Double] = []
        let baseY = CGFloat.random(in: 0.28...0.72)
        let rowH: CGFloat = CGFloat.random(in: 0.058...0.072)
        let cellW: CGFloat = CGFloat.random(in: 0.16...0.20)
        for row in -1...1 {
            let y = baseY + CGFloat(row) * rowH
            let stagger: CGFloat = (abs(row) % 2 == 0) ? 0 : cellW / 2
            let count = Int.random(in: 2...4)
            let startX = CGFloat.random(in: 0.06...0.18) + stagger
            for c in 0..<count {
                let x = startX + CGFloat(c) * (cellW + 0.006) + CGFloat.random(in: -0.004...0.004)
                guard x > 0.02, x + cellW < 0.98, y > 0.05, y + rowH < 0.95 else { continue }
                rects.append(CGRect(x: x, y: y, width: cellW, height: rowH))
                confs.append(Double.random(in: 0.78...0.97))
            }
        }
        applyDetections(rects, confidences: confs)
    }

    // MARK: - Synthesized placeholder photo

    static func synthesizePlaceholder(slope: SlopeType,
                                      pitchDegrees: Double,
                                      elevationFeet: Double) -> UIImage {
        let size = CGSize(width: 640, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
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

            let rows = 22, cols = 14
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
                    UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
                }
            }

            for _ in 0..<28 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: yStart...(size.height - 20))
                let r = CGFloat.random(in: 4...10)
                UIColor.black.withAlphaComponent(0.55).setFill()
                UIBezierPath(ovalIn: CGRect(x: x, y: y, width: r, height: r)).fill()
            }

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

// MARK: - Vision shingle detection

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectRectanglesRequest()
        // Roof shingles are wide, low-aspect rectangles.
        request.minimumAspectRatio = 0.18
        request.maximumAspectRatio = 0.48
        request.minimumSize = 0.04
        request.maximumObservations = 24
        request.minimumConfidence = 0.55
        request.quadratureTolerance = 25

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right,
                                            options: [:])
        try? handler.perform([request])

        let observations = (request.results as [VNRectangleObservation]?) ?? []
        // Convert from Vision's bottom-left normalized space into UIKit top-left.
        var rects: [CGRect] = []
        var confs: [Double] = []
        rects.reserveCapacity(observations.count)
        confs.reserveCapacity(observations.count)
        for obs in observations {
            let r = obs.boundingBox
            let flipped = CGRect(x: r.minX,
                                 y: 1 - r.maxY,
                                 width: r.width,
                                 height: r.height)
            rects.append(flipped)
            confs.append(Double(obs.confidence))
        }

        let finalRects = rects
        let finalConfs = confs
        Task { @MainActor in
            self.applyDetections(finalRects, confidences: finalConfs)
        }
    }
}

// MARK: - Photo capture delegate

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
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}
