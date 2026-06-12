import Foundation
import ARKit
import UIKit
import CoreImage

/// Thread-safe throttle gate so the (background) ARSession delegate can decide
/// whether to kick off a new Gemini analysis without touching MainActor state.
private final class AnalyzerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastAt: Date = .distantPast
    private var analyzing = false

    /// Returns true (and arms the gate) when a new analysis is allowed.
    func tryBegin(now: Date, interval: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if analyzing { return false }
        if now.timeIntervalSince(lastAt) < interval { return false }
        lastAt = now
        analyzing = true
        return true
    }

    func end() {
        lock.lock(); analyzing = false; lock.unlock()
    }
}

/// Drives the live AR damage overlay: owns the ARSession, throttles frame
/// analysis to ~2 Hz, and publishes the latest markers + confidence for the UI.
@Observable
final class LiveARAnalyzer: NSObject, ARSessionDelegate {
    /// Latest damage markers (normalized 0-1, top-left origin) for the current frame.
    var lastMarkers: [DamageMarker] = []
    /// Average marker confidence (0-1) from the most recent successful analysis.
    var liveConfidence: Double = 0
    /// True while a frame is being analyzed. Drives the "Analyzing…" HUD pill.
    var isAnalyzing: Bool = false

    private weak var session: ARSession?
    private nonisolated let gate = AnalyzerGate()
    private nonisolated(unsafe) let ciContext = CIContext(options: nil)

    func start(session: ARSession) {
        self.session = session
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        session.run(config)
    }

    func stop() {
        session?.pause()
    }

    // MARK: - ARSessionDelegate (background queue)

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        guard gate.tryBegin(now: now, interval: 0.5) else { return }

        // Downsample the frame to a small JPEG (longest edge 640, q 0.7) so the
        // upload stays fast. Data is Sendable so it crosses into the detached task.
        guard let data = jpegData(from: frame.capturedImage) else {
            gate.end()
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isAnalyzing = true }
            defer {
                self.gate.end()
                Task { @MainActor in self.isAnalyzing = false }
            }
            do {
                let result = try await GeminiAnalysisService.analyzeLive(imageData: data)
                let avg = Self.averageConfidence(of: result.markers)
                await MainActor.run {
                    self.lastMarkers = result.markers
                    self.liveConfidence = avg
                }
            } catch {
                print("[LiveARAnalyzer] analyze error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private nonisolated func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        return ImageResize.encodedJPEGData(from: uiImage, longestEdge: 640, quality: 0.7)
    }

    private nonisolated static func averageConfidence(of markers: [DamageMarker]) -> Double {
        guard !markers.isEmpty else { return 0 }
        let total = markers.reduce(0.0) { $0 + Double($1.confidence) / 100.0 }
        return total / Double(markers.count)
    }
}
