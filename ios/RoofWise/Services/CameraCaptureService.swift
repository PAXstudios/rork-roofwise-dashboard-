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

    /// Current frame's detected roof/shingle region in UIKit-normalized coords (0..1, top-left origin).
    /// Empty until Vision confidently sees roofing material.
    var detectionRects: [CGRect] = []

    /// Per-detection confidence (0..1), parallel to `detectionRects`.
    var detectionConfidences: [Double] = []

    /// True only when Vision classification sees roof/shingle/tile/roofing material at >= 0.6 confidence.
    var roofDetected: Bool = false

    /// Most recent camera frame, used for lightweight live Gemini damage analysis.
    var latestFrame: UIImage?

    /// Live damage markers returned by Gemini for the current camera feed.
    var liveDamageMarkers: [DamageMarker] = []

    /// Roof material classified by Gemini on the most recent live frame, if any.
    var liveShingleType: String?
    var liveShingleTypeConfidence: Int = 0

    /// Preview layer used to map normalized image-space marker coordinates to
    /// preview-layer-space (aspectFill cropping). Set by `CameraProxyView`.
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    private var lastVisionRun: Date = .distantPast
    private var lastLiveDamageRun: Date = .distantPast
    private var isLiveDamageAnalyzing: Bool = false
    private let ciContext = CIContext()

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

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
    }

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
        roofDetected = false
        liveDamageMarkers = []
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
        // No simulated roof detection. The live overlay stays hidden by default
        // until a real camera frame is classified as roofing material.
        roofDetected = false
        detectionRects = []
        detectionConfidences = []
        liveDamageMarkers = []
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

        let now = Date()
        let shouldRunVision = now.timeIntervalSince(lastVisionRun) >= 0.5
        guard shouldRunVision else { return }
        lastVisionRun = now

        let classifyRequest = VNClassifyImageRequest()

        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumAspectRatio = 0.75
        rectangleRequest.maximumAspectRatio = 1.35
        rectangleRequest.minimumSize = 0.08
        rectangleRequest.maximumObservations = 12
        rectangleRequest.minimumConfidence = 0.55
        rectangleRequest.quadratureTolerance = 25

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right,
                                            options: [:])
        try? handler.perform([classifyRequest, rectangleRequest])

        let roofClassifications = (classifyRequest.results ?? []).filter { observation in
            Self.isRoofLabel(observation.identifier) && observation.confidence >= 0.6
        }
        let isRoof = !roofClassifications.isEmpty
        let classificationConfidence = Double(roofClassifications.map(\.confidence).max() ?? 0)

        let observations = (rectangleRequest.results as [VNRectangleObservation]?) ?? []
        var rects: [CGRect] = []
        var confs: [Double] = []
        if isRoof {
            for obs in observations {
                let r = obs.boundingBox
                let flipped = CGRect(x: r.minX,
                                     y: 1 - r.maxY,
                                     width: r.width,
                                     height: r.height)
                rects.append(Self.shingleRegionGridRect(from: flipped))
                confs.append(max(Double(obs.confidence), classificationConfidence))
            }
            if rects.isEmpty {
                rects = [CGRect(x: 0.16, y: 0.26, width: 0.68, height: 0.42)]
                confs = [classificationConfidence]
            }
        }

        let frameImage = Self.image(from: pixelBuffer, context: ciContext)
        Task { @MainActor in
            self.roofDetected = isRoof
            self.latestFrame = frameImage
            if isRoof {
                self.applyDetections(rects, confidences: confs)
                self.runLiveDamageAnalysisIfNeeded(now: now)
            } else {
                self.detectionRects = []
                self.detectionConfidences = []
                self.liveDamageMarkers = []
            }
        }
    }

    nonisolated private static func isRoofLabel(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return lowered.contains("roof")
            || lowered.contains("shingle")
            || lowered.contains("tile roof")
            || lowered.contains("roofing")
            || lowered.contains("asphalt")
            || lowered.contains("slate")
            || lowered.contains("metal panel")
            || lowered.contains("standing seam")
    }

    nonisolated private static func shingleRegionGridRect(from rect: CGRect) -> CGRect {
        let minWidth: CGFloat = 0.34
        let minHeight: CGFloat = 0.30
        let width = max(rect.width, minWidth)
        let height = max(rect.height, minHeight)
        let x = max(0.04, min(0.96 - width, rect.midX - width / 2))
        let y = max(0.14, min(0.86 - height, rect.midY - height / 2))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    nonisolated private static func image(from pixelBuffer: CVPixelBuffer, context: CIContext) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private extension CameraCaptureService {
    func runLiveDamageAnalysisIfNeeded(now: Date) {
        guard now.timeIntervalSince(lastLiveDamageRun) >= 3.0,
              !isLiveDamageAnalyzing,
              roofDetected,
              let image = latestFrame else { return }
        lastLiveDamageRun = now
        isLiveDamageAnalyzing = true
        Task { @MainActor in
            // Use the real full analysis pipeline so live dots come from the same
            // Gemini call (and prompt) as captured-photo analysis.
            let result = await GeminiAnalysisService.analyzeFull(image: image,
                                                                  slope: .frontSlope,
                                                                  mode: .square,
                                                                  squaresCovered: 0)
            if roofDetected, !result.noRoofDetected, !result.failed {
                let mapped = mapMarkersToPreviewSpace(result.markers, frameSize: image.size)
                withAnimation(.easeInOut(duration: 0.25)) {
                    liveDamageMarkers = mapped
                }
                if let t = result.shingleType {
                    liveShingleType = t
                    liveShingleTypeConfidence = result.shingleTypeConfidence
                }
            } else {
                liveDamageMarkers = []
            }
            isLiveDamageAnalyzing = false
        }
    }

    /// Convert normalized image-space markers (top-left origin, in the captured
    /// frame) into normalized preview-layer space, accounting for the preview's
    /// `.resizeAspectFill` cropping. Falls back to the original markers if the
    /// preview layer isn't attached or sized.
    func mapMarkersToPreviewSpace(_ markers: [DamageMarker], frameSize: CGSize) -> [DamageMarker] {
        guard let layer = previewLayer,
              layer.bounds.width > 0, layer.bounds.height > 0,
              frameSize.width > 0, frameSize.height > 0 else {
            return markers
        }
        let bounds = layer.bounds
        return markers.map { m in
            // AVCaptureVideoPreviewLayer uses normalized device coordinates with
            // top-left origin in the active capture orientation.
            let device = CGPoint(x: m.x, y: m.y)
            let pt = layer.layerPointConverted(fromCaptureDevicePoint: device)
            let nx = max(0, min(1, pt.x / bounds.width))
            let ny = max(0, min(1, pt.y / bounds.height))
            return DamageMarker(x: nx, y: ny, radius: m.radius,
                                type: m.type, severity: m.severity,
                                note: m.note, confidence: m.confidence)
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
                // Normalize EXIF orientation up-front so the bitmap we send to
                // Gemini Vision and the bitmap we display under the marker
                // overlay are pixel-identical (markers landed off otherwise).
                return img.normalizedOrientation()
            }
            return UIImage()
        }()
        Task { @MainActor in
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}
