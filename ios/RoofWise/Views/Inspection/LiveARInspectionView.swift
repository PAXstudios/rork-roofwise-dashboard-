import SwiftUI
import ARKit
import UIKit
#if !targetEnvironment(simulator)
import RealityKit
#endif

/// Live AR Damage Detection — the pitch demo. Full-screen cover that shows a
/// live camera/AR feed with a 2 Hz Gemini damage overlay, an anchored 10×10 ft
/// test square (LiDAR devices), and glove-friendly inspection HUD.
struct LiveARInspectionView: View {
    var onClose: () -> Void = {}

    var body: some View {
        content
            .ignoresSafeArea()
            .statusBarHidden()
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        #if targetEnvironment(simulator)
        LiveARFallbackStage(arUnavailable: true, onClose: onClose)
        #else
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            LiveARDeviceStage(onClose: onClose)
        } else {
            LiveARFallbackStage(arUnavailable: true, onClose: onClose)
        }
        #endif
    }
}

// MARK: - Shared HUD chrome

/// All foreground overlays for the live AR experience. Pure SwiftUI so it is
/// shared between the real-device AR stage and the fallback stage.
struct LiveAROverlayChrome: View {
    let yawDegrees: Double
    let pitchDegrees: Double
    let rollDegrees: Double
    let confidence: Double
    let markerCount: Int
    let arUnavailable: Bool
    @Binding var slope: SlopeType
    let isCapturing: Bool
    let captureEligible: Bool
    let onClose: () -> Void
    let onShutter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topRow
            Spacer(minLength: 0)
            bottomRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .padding(.bottom, 40)
    }

    // MARK: Top

    private var topRow: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                compassChip
                Spacer()
                centerCluster
                Spacer()
                levelChip
            }
            HStack {
                Spacer()
                closeButton
            }
        }
    }

    private var centerCluster: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: arUnavailable ? "arkit.badge.xmark" : "arkit")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                Text("AR MODE")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .tracking(1.4)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().stroke(Theme.ember.opacity(0.5), lineWidth: 0.8))

            Menu {
                Picker("Slope", selection: $slope) {
                    ForEach(SlopeType.allCases) { s in
                        Label(s.shortName, systemImage: s.icon).tag(s)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: slope.icon)
                        .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    Text(slope.shortName)
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: .capsule)
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.6))
            }

            if arUnavailable {
                Text("AR mode unavailable on this device — using standard camera")
                    .font(.system(size: Theme.TypeRamp.microSm, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: 220)
            }
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: .circle)
        }
        .buttonStyle(.plain)
    }

    /// Top-left compass — arrow rotates with device yaw + degree readout.
    private var compassChip: some View {
        VStack(spacing: 4) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.ember)
                .rotationEffect(.degrees(-yawDegrees))
            Text("\(Int((yawDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)))°")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 56, height: 56)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 0.6))
    }

    /// Top-right bullseye level — bubble offsets with pitch + roll.
    private var levelChip: some View {
        let level = abs(rollDegrees) < 3 && abs(pitchDegrees - 40) < 18
        return ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 1)
                .frame(width: 40, height: 40)
            Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                .frame(width: 22, height: 22)
            Circle()
                .fill(level ? Theme.mint : Theme.amber)
                .frame(width: 12, height: 12)
                .offset(x: CGFloat(max(-18, min(18, rollDegrees))),
                        y: CGFloat(max(-18, min(18, (pitchDegrees - 40) * 0.6))))
        }
        .frame(width: 56, height: 56)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 0.6))
    }

    // MARK: Bottom

    private var bottomRow: some View {
        HStack(alignment: .bottom) {
            confidenceMeter
            Spacer()
            shutterButton
            Spacer()
            qualityIndicator
        }
    }

    private var confidenceColor: Color {
        if confidence >= 0.7 { return Theme.mint }
        if confidence >= 0.4 { return Theme.amber }
        return Theme.crimson
    }

    private var confidenceMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI CONF")
                .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.6))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(confidenceColor)
                        .frame(width: max(4, geo.size.width * CGFloat(confidence)))
                }
            }
            .frame(width: 72, height: 8)
            Text("\(Int(confidence * 100))%")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(confidenceColor.opacity(0.4), lineWidth: 0.6))
    }

    private var qualityIndicator: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "scope")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                Text("\(markerCount)")
                    .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            HStack(spacing: 5) {
                Image(systemName: captureEligible ? "checkmark.seal.fill" : "viewfinder")
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .foregroundStyle(captureEligible ? Theme.mint : .white.opacity(0.7))
                Text(captureEligible ? "READY" : "AIM")
                    .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 0.6))
    }

    private var shutterButton: some View {
        Button(action: onShutter) {
            ZStack {
                Circle()
                    .stroke(captureEligible ? Theme.mint : .white.opacity(0.85),
                            lineWidth: 4)
                    .frame(width: 100, height: 100)
                Circle()
                    .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 88, height: 88)
                    .shadow(color: Theme.ember.opacity(0.55), radius: 18, y: 6)
                if isCapturing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isCapturing)
    }
}

// MARK: - Live damage marker overlay (CAShapeLayer)

/// CAShapeLayer host that draws pulsing damage circles over the camera feed.
final class LiveMarkerLayer: CAShapeLayer {
    private var renderedIDs: Set<String> = []

    func render(_ markers: [DamageMarker], in bounds: CGRect) {
        sublayers?.forEach { $0.removeFromSuperlayer() }
        guard bounds.width > 0, bounds.height > 0 else { return }

        var newIDs: Set<String> = []
        let minEdge = min(bounds.width, bounds.height)
        for marker in markers {
            let id = marker.id.uuidString
            newIDs.insert(id)

            let radius = max(8, minEdge * marker.radius)
            let diameter = radius * 2
            let center = CGPoint(x: bounds.width * marker.x, y: bounds.height * marker.y)
            let circle = CAShapeLayer()
            circle.frame = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: diameter, height: diameter)
            circle.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).cgPath
            let color = UIColor(marker.type.color)
            circle.strokeColor = color.cgColor
            circle.fillColor = color.withAlphaComponent(0.18).cgColor
            circle.lineWidth = 2
            addSublayer(circle)

            if !renderedIDs.contains(id) {
                let anim = CABasicAnimation(keyPath: "transform.scale")
                anim.fromValue = 0.5
                anim.toValue = 1.0
                anim.duration = 0.3
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                circle.add(anim, forKey: "appear")
            }
        }
        renderedIDs = newIDs
    }
}

/// SwiftUI wrapper for `LiveMarkerLayer`.
struct LiveMarkerOverlay: UIViewRepresentable {
    var markers: [DamageMarker]

    func makeUIView(context: Context) -> MarkerHostView { MarkerHostView() }

    func updateUIView(_ uiView: MarkerHostView, context: Context) {
        uiView.markers = markers
    }

    final class MarkerHostView: UIView {
        let markerLayer = LiveMarkerLayer()
        var markers: [DamageMarker] = [] { didSet { setNeedsLayout() } }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            layer.addSublayer(markerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            markerLayer.frame = bounds
            markerLayer.render(markers, in: bounds)
        }
    }
}

// MARK: - Fallback stage (simulator / no-LiDAR device)

struct LiveARFallbackStage: View {
    let arUnavailable: Bool
    var onClose: () -> Void = {}

    @Environment(CustomerStore.self) private var customerStore
    @State private var analyzer = LiveARAnalyzer()
    @State private var motion = MotionElevationService()
    @State private var slope: SlopeType = .frontSlope
    @State private var isCapturing = false
    @State private var flash = false

    var body: some View {
        ZStack {
            CameraProxyView()
                .ignoresSafeArea()

            LiveMarkerOverlay(markers: analyzer.lastMarkers)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            LiveAROverlayChrome(
                yawDegrees: motion.yawDegrees,
                pitchDegrees: motion.pitchDegrees,
                rollDegrees: motion.rollDegrees,
                confidence: analyzer.liveConfidence,
                markerCount: analyzer.lastMarkers.count,
                arUnavailable: arUnavailable,
                slope: $slope,
                isCapturing: isCapturing,
                captureEligible: !isCapturing,
                onClose: onClose,
                onShutter: capture
            )
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    private func capture() {
        guard !isCapturing else { return }
        let g = UIImpactFeedbackGenerator(style: .heavy); g.impactOccurred()
        isCapturing = true
        withAnimation(.easeIn(duration: 0.08)) { flash = true }
        let slopeValue = slope
        let pitch = motion.pitchDegrees
        let elev = motion.elevationFeet
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
            let image = CameraCaptureService.synthesizePlaceholder(slope: slopeValue,
                                                                   pitchDegrees: pitch,
                                                                   elevationFeet: elev)
            await LiveARCapture.analyzeAndStore(image: image, slope: slopeValue,
                                                pitch: pitch, elevation: elev,
                                                customerStore: customerStore)
            isCapturing = false
        }
    }
}

// MARK: - Capture helper (shared by both stages)

enum LiveARCapture {
    /// Runs FULL-quality analysis on a captured frame and stores it as a regular
    /// photo via the existing CustomerStore persistence (same API as Quick Inspection).
    @MainActor
    static func analyzeAndStore(image: UIImage,
                                slope: SlopeType,
                                pitch: Double,
                                elevation: Double,
                                customerStore: CustomerStore) async {
        let result = await GeminiAnalysisService.analyzeFull(image: image,
                                                             slope: slope,
                                                             mode: .square,
                                                             squaresCovered: 0)
        var photo = CapturedPhoto(image: image, slope: slope,
                                  pitchDegrees: pitch, elevationFeet: elevation,
                                  captureMode: .square, squaresCovered: 0)
        photo.findings = result.findings
        photo.damageMarkers = result.markers
        photo.analyzed = !result.failed
        if let cid = customerStore.activeCustomerID {
            customerStore.appendPhotos([photo], to: cid)
        }
        let n = UINotificationFeedbackGenerator(); n.notificationOccurred(.success)
    }
}

// MARK: - Real-device AR stage

#if !targetEnvironment(simulator)

struct LiveARDeviceStage: View {
    var onClose: () -> Void = {}

    @Environment(CustomerStore.self) private var customerStore
    @State private var analyzer = LiveARAnalyzer()
    @State private var motion = MotionElevationService()
    @State private var controller: LiveARController
    @State private var slope: SlopeType = .frontSlope
    @State private var isCapturing = false
    @State private var flash = false

    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        let analyzer = LiveARAnalyzer()
        _analyzer = State(initialValue: analyzer)
        _controller = State(initialValue: LiveARController(analyzer: analyzer))
    }

    var body: some View {
        ZStack {
            LiveARViewContainer(controller: controller)
                .ignoresSafeArea()

            LiveMarkerOverlay(markers: analyzer.lastMarkers)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            LiveAROverlayChrome(
                yawDegrees: motion.yawDegrees,
                pitchDegrees: motion.pitchDegrees,
                rollDegrees: motion.rollDegrees,
                confidence: analyzer.liveConfidence,
                markerCount: analyzer.lastMarkers.count,
                arUnavailable: false,
                slope: $slope,
                isCapturing: isCapturing,
                captureEligible: !isCapturing,
                onClose: onClose,
                onShutter: capture
            )
            .overlay(alignment: .bottom) {
                Button {
                    let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                    controller.placeTestSquare()
                } label: {
                    Label("Place 10×10 Square", systemImage: "square.dashed.inset.filled")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: .capsule)
                        .overlay(Capsule().stroke(Theme.ember.opacity(0.5), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 150)
            }
        }
        .onAppear { motion.start() }
        .onDisappear {
            motion.stop()
            controller.stop()
        }
    }

    private func capture() {
        guard !isCapturing else { return }
        let g = UIImpactFeedbackGenerator(style: .heavy); g.impactOccurred()
        isCapturing = true
        withAnimation(.easeIn(duration: 0.08)) { flash = true }
        let slopeValue = slope
        let pitch = motion.pitchDegrees
        let elev = motion.elevationFeet
        Task { @MainActor in
            let snapshot = await controller.snapshot()
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.25)) { flash = false }
            let image = snapshot ?? CameraCaptureService.synthesizePlaceholder(
                slope: slopeValue, pitchDegrees: pitch, elevationFeet: elev)
            await LiveARCapture.analyzeAndStore(image: image, slope: slopeValue,
                                                pitch: pitch, elevation: elev,
                                                customerStore: customerStore)
            isCapturing = false
        }
    }
}

/// Hosts the RealityKit `ARView` and hands its session to the analyzer.
struct LiveARViewContainer: UIViewRepresentable {
    let controller: LiveARController

    func makeUIView(context: Context) -> ARView { controller.makeARView() }
    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// Owns the ARView, the test-square anchor, and snapshot capture.
@MainActor
final class LiveARController {
    let analyzer: LiveARAnalyzer
    private weak var arView: ARView?
    private var squareAnchor: AnchorEntity?

    init(analyzer: LiveARAnalyzer) {
        self.analyzer = analyzer
    }

    func makeARView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView = view
        analyzer.start(session: view.session)
        return view
    }

    /// Raycasts from screen center to a plane and anchors a 10×10 ft test square.
    func placeTestSquare() {
        guard let arView else { return }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let query = arView.makeRaycastQuery(from: center,
                                                  allowing: .estimatedPlane,
                                                  alignment: .any),
              let hit = arView.session.raycast(query).first else {
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.warning)
            return
        }
        if let existing = squareAnchor {
            arView.scene.removeAnchor(existing)
        }
        let mesh = MeshResource.generatePlane(width: 3.048, depth: 3.048)
        let material = SimpleMaterial(color: UIColor.systemOrange.withAlphaComponent(0.18),
                                      isMetallic: false)
        let model = ModelEntity(mesh: mesh, materials: [material])
        let anchor = AnchorEntity(world: hit.worldTransform)
        anchor.name = "rw.testSquare"
        anchor.addChild(model)
        arView.scene.addAnchor(anchor)
        squareAnchor = anchor
        let g = UIImpactFeedbackGenerator(style: .rigid); g.impactOccurred()
    }

    func snapshot() async -> UIImage? {
        guard let arView else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            arView.snapshot(saveToHDR: false) { image in
                cont.resume(returning: image)
            }
        }
    }

    func stop() {
        analyzer.stop()
    }
}

#endif
