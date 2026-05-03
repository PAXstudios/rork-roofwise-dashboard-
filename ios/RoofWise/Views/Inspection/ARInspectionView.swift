import SwiftUI
import RealityKit
import ARKit
import UIKit
import Combine

// MARK: - SwiftUI entry point

/// AR roof inspection mode. Wraps a real ARView on LiDAR-equipped devices and
/// shows a friendly placeholder everywhere else (cloud simulator, non-Pro
/// iPhones). The output is a single `ARInspectionSnapshot` handed back to the
/// caller so the rest of the app keeps working with the existing
/// `CapturedPhoto` / claim-packet pipeline.
struct ARInspectionView: View {
    let slope: SlopeType
    var onSave: (ARInspectionSnapshot) -> Void
    var onClose: () -> Void

    var body: some View {
        Group {
            #if targetEnvironment(simulator)
            ARDeviceRequiredPlaceholder(reason: .simulator, onClose: onClose)
            #else
            if LiDARRoofService.hasLiDAR {
                ARInspectionStage(slope: slope, onSave: onSave, onClose: onClose)
            } else {
                ARDeviceRequiredPlaceholder(reason: .noLidar, onClose: onClose)
            }
            #endif
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }
}

// MARK: - Placeholder

private struct ARDeviceRequiredPlaceholder: View {
    enum Reason { case simulator, noLidar }
    let reason: Reason
    let onClose: () -> Void

    private var title: String {
        reason == .simulator ? "AR Mode preview is unavailable" : "LiDAR-equipped iPhone required"
    }
    private var message: String {
        switch reason {
        case .simulator:
            return "Install RoofWise on your iPhone via the Rork App to use the 3D AR roof scanner."
        case .noLidar:
            return "AR Mode uses your device's LiDAR scanner to measure pitting and anchor 3D damage markers. iPhone 12 Pro / Pro Max or newer is required."
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Theme.ink.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Theme.ember.opacity(0.18))
                        .frame(width: 120, height: 120)
                    Image(systemName: "arkit")
                        .font(.system(size: 56, weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [Theme.amber, Theme.ember],
                                                        startPoint: .top, endPoint: .bottom))
                }
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: onClose) {
                    Text("Close")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                           startPoint: .leading, endPoint: .trailing),
                            in: .capsule
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - AR stage (real device)

#if !targetEnvironment(simulator)

private struct ARInspectionStage: View {
    let slope: SlopeType
    var onSave: (ARInspectionSnapshot) -> Void
    var onClose: () -> Void

    @State private var coordinator = ARInspectionCoordinator()
    @State private var selectedTool: ARTool = .marker
    @State private var selectedDamageType: DamageMarkerType = .hailStrike
    @State private var heatmapOn: Bool = false
    @State private var isScanning: Bool = false
    @State private var scanError: String?
    @State private var showResultsDrawer: Bool = false
    @State private var lastGeminiAdded: Int = 0

    var body: some View {
        ZStack {
            ARInspectionContainer(coordinator: coordinator,
                                  selectedTool: $selectedTool,
                                  selectedDamageType: $selectedDamageType,
                                  heatmapOn: $heatmapOn)
                .ignoresSafeArea()

            // Vignette
            RadialGradient(colors: [.clear, .black.opacity(0.5)],
                           center: .center, startRadius: 220, endRadius: 560)
                .allowsHitTesting(false)

            // Center reticle / empty state
            ARReticleView(planeFound: coordinator.planeDetected,
                          tool: selectedTool)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topHUD
                Spacer()
                if let scanError {
                    Text(scanError)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.crimson.opacity(0.95), in: .capsule)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomHUD
            }
        }
        .sheet(isPresented: $showResultsDrawer) {
            ARScanResultsSheet(addedCount: lastGeminiAdded,
                               markers: coordinator.markers.filter { $0.source == .gemini },
                               onDismiss: { showResultsDrawer = false })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .overlay {
            if isScanning {
                ARScanningOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(true)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isScanning)
        .animation(.easeInOut(duration: 0.25), value: scanError)
    }

    // MARK: Top HUD

    private var topHUD: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(.plain)

                Spacer()

                pitchPill

                Spacer()

                Button {
                    let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        heatmapOn.toggle()
                    }
                    coordinator.setHeatmap(enabled: heatmapOn)
                } label: {
                    Image(systemName: heatmapOn ? "thermometer.sun.fill" : "thermometer.medium")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(heatmapOn ? .black : .white)
                        .frame(width: 38, height: 38)
                        .background {
                            if heatmapOn {
                                Circle().fill(LinearGradient(colors: [Theme.amber, Theme.ember],
                                                              startPoint: .top, endPoint: .bottom))
                            } else {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                statChip(icon: "mappin", value: "\(coordinator.markers.count)", label: "PINS", tint: Theme.ember)
                statChip(icon: "scribble.variable", value: "\(coordinator.chalkStrokes)", label: "CHALK", tint: Theme.amber)
                statChip(icon: "square.dashed.inset.filled",
                         value: coordinator.squarePlaced ? "\(coordinator.markersInSquare)" : "—",
                         label: "IN SQ", tint: Theme.mint)
                Spacer()
                if coordinator.squarePlaced {
                    Button {
                        let g = UIImpactFeedbackGenerator(style: .soft); g.impactOccurred()
                        coordinator.removeSquare()
                    } label: {
                        Label("Reset Square", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Damage type picker — only relevant when in marker mode
            if selectedTool == .marker {
                damageTypeRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedTool)
    }

    private var pitchPill: some View {
        VStack(spacing: 1) {
            Text(coordinator.pitchRatioString)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("PITCH · \(String(format: "%.0f°", coordinator.pitchDegrees))")
                .font(.system(size: 8, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(Theme.ember.opacity(0.45), lineWidth: 0.8))
    }

    private func statChip(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.3), lineWidth: 0.6))
    }

    private var damageTypeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(arDamageTypes, id: \.self) { type in
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            selectedDamageType = type
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: type.icon)
                                .font(.system(size: 10, weight: .heavy))
                            Text(type.display.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(0.6)
                        }
                        .foregroundStyle(selectedDamageType == type ? .black : .white.opacity(0.85))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background {
                            if selectedDamageType == type {
                                Capsule().fill(type.color.opacity(0.95))
                                    .shadow(color: type.color.opacity(0.45), radius: 5, y: 2)
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                        .overlay(Capsule().stroke(type.color.opacity(selectedDamageType == type ? 0 : 0.4), lineWidth: 0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private var arDamageTypes: [DamageMarkerType] {
        [.hailStrike, .windCrease, .crack, .granuleLoss, .missingShingle, .flashing, .other]
    }

    // MARK: Bottom HUD

    private var bottomHUD: some View {
        VStack(spacing: 14) {
            toolPalette

            HStack(spacing: 14) {
                Button {
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                    coordinator.undoLastAction()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 16, weight: .bold))
                        Text("Undo").font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: scanWithGemini) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.85), lineWidth: 3.5)
                            .frame(width: 86, height: 86)
                        Circle()
                            .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 70, height: 70)
                            .overlay(
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundStyle(.white)
                            )
                            .shadow(color: Theme.ember.opacity(0.55), radius: 18, x: 0, y: 6)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isScanning)

                Spacer()

                Button(action: saveAndClose) {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Save").font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(coordinator.markers.isEmpty && coordinator.chalkStrokes == 0 ? .white.opacity(0.4) : Theme.mint)
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(coordinator.markers.isEmpty && coordinator.chalkStrokes == 0)
            }

            Text(hintText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 38)
    }

    private var toolPalette: some View {
        HStack(spacing: 6) {
            ForEach(ARTool.allCases) { tool in
                Button {
                    let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedTool = tool
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 11, weight: .heavy))
                        Text(tool.label.uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.7)
                    }
                    .foregroundStyle(selectedTool == tool ? .black : .white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selectedTool == tool {
                            Capsule().fill(LinearGradient(colors: [Theme.amber, Theme.ember],
                                                          startPoint: .leading, endPoint: .trailing))
                                .shadow(color: Theme.amber.opacity(0.45), radius: 7, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.6))
    }

    private var hintText: String {
        switch selectedTool {
        case .marker:
            return coordinator.planeDetected
                ? "Tap a damaged shingle to drop a 3D pin · markers stay locked in space."
                : "Aim at a roof slope. Move slowly so LiDAR can map the surface."
        case .chalk:
            return "Drag your finger over the roof to virtually chalk-circle suspected hits."
        case .placeSquare:
            return coordinator.squarePlaced
                ? "10×10 square placed. Tap pins inside to count toward HAAG hit count."
                : "Aim at a flat roof slope and tap to anchor a 10' × 10' test square."
        }
    }

    // MARK: Actions

    private func scanWithGemini() {
        let g = UIImpactFeedbackGenerator(style: .heavy); g.impactOccurred()
        scanError = nil
        isScanning = true
        Task {
            let result = await coordinator.scanCurrentFrameWithGemini(slope: slope)
            await MainActor.run {
                isScanning = false
                switch result {
                case .success(let added):
                    lastGeminiAdded = added
                    if added > 0 {
                        showResultsDrawer = true
                        let s = UINotificationFeedbackGenerator(); s.notificationOccurred(.success)
                    } else {
                        scanError = "No damage detected in this frame. Move closer or try a different angle."
                        autoDismissError()
                    }
                case .failure(let msg):
                    scanError = msg
                    autoDismissError()
                    let n = UINotificationFeedbackGenerator(); n.notificationOccurred(.error)
                }
            }
        }
    }

    private func autoDismissError() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.4))
            withAnimation { scanError = nil }
        }
    }

    private func saveAndClose() {
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
        Task {
            let snapshot = await coordinator.makeSnapshot(slope: slope)
            await MainActor.run {
                onSave(snapshot)
                onClose()
            }
        }
    }
}

// MARK: - ARView container

private struct ARInspectionContainer: UIViewRepresentable {
    let coordinator: ARInspectionCoordinator
    @Binding var selectedTool: ARTool
    @Binding var selectedDamageType: DamageMarkerType
    @Binding var heatmapOn: Bool

    func makeUIView(context: Context) -> ARView {
        coordinator.makeARView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        coordinator.activeTool = selectedTool
        coordinator.activeDamageType = selectedDamageType
    }

    func makeCoordinator() -> ARInspectionCoordinator { coordinator }
}

// MARK: - Reticle / scanning overlays

private struct ARReticleView: View {
    let planeFound: Bool
    let tool: ARTool
    @State private var pulse: Bool = false

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Circle()
                    .stroke(planeFound ? Theme.ember : .white.opacity(0.55), lineWidth: 1.4)
                    .frame(width: 64, height: 64)
                    .scaleEffect(pulse ? 1.18 : 1.0)
                    .opacity(pulse ? 0.0 : 0.9)
                Circle()
                    .stroke(planeFound ? Theme.ember : .white.opacity(0.85), lineWidth: 1.6)
                    .frame(width: 28, height: 28)
                Image(systemName: tool.icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(planeFound ? Theme.ember : .white.opacity(0.9))
            }
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

private struct ARScanningOverlay: View {
    @State private var sweep: CGFloat = -1
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Theme.ember.opacity(0.35), lineWidth: 2).frame(width: 110, height: 110)
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(LinearGradient(colors: [Theme.ember, Theme.amber],
                                               startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(Double(sweep) * 360))
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                VStack(spacing: 4) {
                    Text("Analyzing this frame…")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Gemini Vision · placing 3D markers")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }
}

// MARK: - Results drawer

private struct ARScanResultsSheet: View {
    let addedCount: Int
    let markers: [ARDamageMarker]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AR Scan Results")
                    .font(.system(size: 22, weight: .heavy))
                Text("\(addedCount) new 3D marker\(addedCount == 1 ? "" : "s") anchored to the roof.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(markers) { m in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(m.type.color.opacity(0.18)).frame(width: 38, height: 38)
                                Image(systemName: m.type.icon)
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(m.type.color)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.type.display)
                                    .font(.system(size: 14, weight: .heavy))
                                Text(m.note)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                    }
                }
            }
            Button(action: onDismiss) {
                Text("Continue Inspecting")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                               startPoint: .leading, endPoint: .trailing),
                                in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
}

// MARK: - Coordinator

@MainActor
@Observable
final class ARInspectionCoordinator: NSObject {
    // Observable state
    var markers: [ARDamageMarker] = []
    var chalkStrokes: Int = 0
    var planeDetected: Bool = false
    var squarePlaced: Bool = false
    var pitchDegrees: Double = 0
    var pitchRatioString: String = "—"
    var markersInSquare: Int = 0

    // AR
    private weak var arView: ARView?
    private var markerEntities: [UUID: AnchorEntity] = [:]
    private var chalkAnchors: [AnchorEntity] = []
    private var squareAnchor: AnchorEntity?
    private var squareTransform: simd_float4x4?
    private var lastChalkPoint: SIMD3<Float>?
    private var currentChalkAnchor: AnchorEntity?
    private var pitchSampleTimer: Timer?
    private var sessionDelegateProxy: SessionDelegateProxy?

    // Tool state (set by container.updateUIView)
    var activeTool: ARTool = .marker
    var activeDamageType: DamageMarkerType = .hailStrike

    // LiDAR-derived metrics, recomputed as the mesh updates.
    var lidarRoofAreaSquareFeet: Double = 0
    var lidarPitchDegrees: Double? = nil
    private(set) var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private(set) var roofPlaneAnchors: [UUID: ARPlaneAnchor] = [:]

    // RealityKit shingle grid entities anchored to detected roof planes.
    private var planeGridAnchors: [UUID: AnchorEntity] = [:]

    // Measure-tool state
    var measureFirstMarkerID: UUID?
    private var measureAnchor: AnchorEntity?
    private var measureHighlightAnchor: AnchorEntity?
    var lastMeasurementText: String?

    // MARK: ARView setup

    func makeARView() -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        self.arView = arView

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // People occlusion if available — keeps markers behind the inspector's hand
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }

        let proxy = SessionDelegateProxy(target: self)
        sessionDelegateProxy = proxy
        arView.session.delegate = proxy

        // Coaching overlay
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
        ])

        // Gestures
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)

        // Pitch sampling — read center-screen surface tilt twice per second
        pitchSampleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePitch() }
        }

        return arView
    }

    deinit {
        pitchSampleTimer?.invalidate()
    }

    // MARK: Heatmap

    func setHeatmap(enabled: Bool) {
        guard let arView else { return }
        if enabled {
            arView.debugOptions.insert(.showSceneUnderstanding)
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    // MARK: Square

    func removeSquare() {
        squareAnchor?.removeFromParent()
        squareAnchor = nil
        squareTransform = nil
        squarePlaced = false
        recomputeMarkersInSquare()
    }

    // MARK: Undo

    func undoLastAction() {
        // Prefer undoing the most recent thing the user did.
        if let last = chalkAnchors.last {
            last.removeFromParent()
            chalkAnchors.removeLast()
            chalkStrokes = max(0, chalkStrokes - 1)
            return
        }
        if let last = markers.last {
            removeMarker(id: last.id)
            return
        }
    }

    private func removeMarker(id: UUID) {
        markerEntities[id]?.removeFromParent()
        markerEntities.removeValue(forKey: id)
        markers.removeAll { $0.id == id }
        recomputeMarkersInSquare()
    }

    // MARK: Gestures

    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        guard let arView else { return }
        let point = sender.location(in: arView)

        switch activeTool {
        case .marker:
            placeMarker(at: point, type: activeDamageType, source: .userTap, note: "User-tagged \(activeDamageType.display)")
        case .placeSquare:
            placeTestSquare(at: point)
        case .chalk:
            // single tap in chalk mode = small dot
            startChalkStrokeIfNeeded()
            addChalkPoint(at: point)
            finalizeChalkStroke()
        case .measure:
            handleMeasureTap(at: point)
        }
    }

    @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
        guard activeTool == .chalk, let arView else { return }
        let point = sender.location(in: arView)
        switch sender.state {
        case .began:
            startChalkStrokeIfNeeded()
            addChalkPoint(at: point)
        case .changed:
            addChalkPoint(at: point)
        case .ended, .cancelled, .failed:
            finalizeChalkStroke()
        default: break
        }
    }

    // MARK: Marker placement

    private func placeMarker(at viewPoint: CGPoint, type: DamageMarkerType, source: ARDamageMarker.Source, note: String) {
        guard let arView else { return }
        guard let result = arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .any).first else {
            // No surface yet — light error haptic
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.warning)
            return
        }
        placeMarker(atWorld: result.worldTransform, type: type, source: source, note: note)
    }

    private func placeMarker(atWorld transform: simd_float4x4, type: DamageMarkerType, source: ARDamageMarker.Source, note: String) {
        guard let arView else { return }
        let pos = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let marker = ARDamageMarker(type: type, position: pos, note: note, source: source)

        let anchor = AnchorEntity(world: transform)
        let pin = makePinEntity(type: type)
        anchor.addChild(pin)
        arView.scene.addAnchor(anchor)
        markerEntities[marker.id] = anchor

        markers.append(marker)
        recomputeMarkersInSquare()

        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
    }

    private func makePinEntity(type: DamageMarkerType) -> Entity {
        let root = Entity()
        let uiColor = UIColor(type.color)

        // Vertical stem (cone)
        let stem = ModelEntity(
            mesh: .generateCone(height: 0.06, radius: 0.012),
            materials: [SimpleMaterial(color: uiColor, roughness: 0.4, isMetallic: false)]
        )
        stem.position.y = 0.03

        // Head sphere
        let head = ModelEntity(
            mesh: .generateSphere(radius: 0.018),
            materials: [SimpleMaterial(color: uiColor, roughness: 0.2, isMetallic: true)]
        )
        head.position.y = 0.07

        // Glow ring at base
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.001, radius: 0.04),
            materials: [UnlitMaterial(color: uiColor.withAlphaComponent(0.45))]
        )
        ring.position.y = 0.0006

        root.addChild(ring)
        root.addChild(stem)
        root.addChild(head)

        // Pulse animation on ring
        let pulse = FromToByAnimation<Transform>(
            name: "pulse",
            from: Transform(scale: SIMD3<Float>(repeating: 1.0)),
            to: Transform(scale: SIMD3<Float>(repeating: 1.6)),
            duration: 1.2,
            timing: .easeInOut,
            bindTarget: .transform
        )
        if let res = try? AnimationResource.generate(with: pulse) {
            ring.playAnimation(res.repeat(duration: .infinity), transitionDuration: 0, startsPaused: false)
        }
        return root
    }

    // MARK: Test square

    private func placeTestSquare(at viewPoint: CGPoint) {
        guard let arView else { return }
        guard let result = arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .any).first else {
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.warning)
            return
        }
        squareAnchor?.removeFromParent()

        let anchor = AnchorEntity(world: result.worldTransform)
        let side: Float = 3.048   // 10 ft

        // Translucent fill
        let fill = ModelEntity(
            mesh: .generatePlane(width: side, depth: side),
            materials: [UnlitMaterial(color: UIColor(white: 1.0, alpha: 0.07))]
        )
        anchor.addChild(fill)

        // Border lines (4 thin boxes)
        let edgeColor = UIColor(Theme.ember).withAlphaComponent(0.95)
        let lineMaterial = UnlitMaterial(color: edgeColor)
        let lineThickness: Float = 0.012
        let halfSide = side / 2
        let edges: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(0, 0.001,  halfSide), SIMD3(side, lineThickness, lineThickness)),
            (SIMD3(0, 0.001, -halfSide), SIMD3(side, lineThickness, lineThickness)),
            (SIMD3( halfSide, 0.001, 0), SIMD3(lineThickness, lineThickness, side)),
            (SIMD3(-halfSide, 0.001, 0), SIMD3(lineThickness, lineThickness, side))
        ]
        for (pos, size) in edges {
            let edge = ModelEntity(
                mesh: .generateBox(size: size),
                materials: [lineMaterial]
            )
            edge.position = pos
            anchor.addChild(edge)
        }

        // Inner grid (10 ft / 5 = 2 ft cells, 4 inner lines per axis)
        let innerColor = UIColor(white: 1.0, alpha: 0.45)
        let innerMaterial = UnlitMaterial(color: innerColor)
        let cells = 5
        for i in 1..<cells {
            let offset = -halfSide + Float(i) * (side / Float(cells))
            let xLine = ModelEntity(
                mesh: .generateBox(size: SIMD3(side, lineThickness * 0.6, lineThickness * 0.6)),
                materials: [innerMaterial]
            )
            xLine.position = SIMD3(0, 0.0008, offset)
            anchor.addChild(xLine)

            let zLine = ModelEntity(
                mesh: .generateBox(size: SIMD3(lineThickness * 0.6, lineThickness * 0.6, side)),
                materials: [innerMaterial]
            )
            zLine.position = SIMD3(offset, 0.0008, 0)
            anchor.addChild(zLine)
        }

        // Floating "10' × 10'" label above one corner
        let label = ModelEntity(
            mesh: .generateText("10' × 10'",
                                extrusionDepth: 0.001,
                                font: .systemFont(ofSize: 0.08, weight: .heavy),
                                alignment: .center),
            materials: [UnlitMaterial(color: UIColor(Theme.amber))]
        )
        label.position = SIMD3(-halfSide + 0.1, 0.18, -halfSide + 0.1)
        anchor.addChild(label)

        arView.scene.addAnchor(anchor)
        squareAnchor = anchor
        squareTransform = result.worldTransform
        squarePlaced = true
        recomputeMarkersInSquare()

        let g = UIImpactFeedbackGenerator(style: .heavy); g.impactOccurred()
    }

    private func recomputeMarkersInSquare() {
        guard let t = squareTransform else { markersInSquare = 0; return }
        let center = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let halfSide: Float = 3.048 / 2
        // Plane local axes
        let localX = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let localZ = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        var count = 0
        for m in markers {
            let v = m.position - center
            let dx = abs(simd_dot(v, simd_normalize(localX)))
            let dz = abs(simd_dot(v, simd_normalize(localZ)))
            if dx <= halfSide && dz <= halfSide { count += 1 }
        }
        markersInSquare = count
    }

    // MARK: Chalk

    private func startChalkStrokeIfNeeded() {
        if currentChalkAnchor == nil {
            let anchor = AnchorEntity(world: .init(repeating: 0))
            currentChalkAnchor = anchor
            arView?.scene.addAnchor(anchor)
            lastChalkPoint = nil
        }
    }

    private func addChalkPoint(at viewPoint: CGPoint) {
        guard let arView, let anchor = currentChalkAnchor else { return }
        guard let result = arView.raycast(from: viewPoint, allowing: .estimatedPlane, alignment: .any).first else { return }
        let p = SIMD3<Float>(result.worldTransform.columns.3.x,
                             result.worldTransform.columns.3.y,
                             result.worldTransform.columns.3.z)

        // Tiny sphere dot
        let dot = ModelEntity(
            mesh: .generateSphere(radius: 0.006),
            materials: [UnlitMaterial(color: UIColor(Theme.amber))]
        )
        dot.position = p
        anchor.addChild(dot)

        // Cylinder segment to previous point
        if let prev = lastChalkPoint {
            let segment = makeChalkSegment(from: prev, to: p)
            anchor.addChild(segment)
        }
        lastChalkPoint = p
    }

    private func makeChalkSegment(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Entity {
        let mid = (a + b) / 2
        let length = simd_distance(a, b)
        let cyl = ModelEntity(
            mesh: .generateCylinder(height: max(length, 0.001), radius: 0.004),
            materials: [UnlitMaterial(color: UIColor(Theme.amber))]
        )
        cyl.position = mid
        // Rotate cylinder so its Y axis aligns with (b - a)
        let dir = b - a
        let normalized = simd_normalize(dir)
        let up = SIMD3<Float>(0, 1, 0)
        let dot = simd_dot(up, normalized)
        if dot < 0.9999 && dot > -0.9999 {
            let axis = simd_normalize(simd_cross(up, normalized))
            let angle = acos(dot)
            cyl.orientation = simd_quatf(angle: angle, axis: axis)
        } else if dot < 0 {
            cyl.orientation = simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))
        }
        return cyl
    }

    private func finalizeChalkStroke() {
        if let anchor = currentChalkAnchor {
            chalkAnchors.append(anchor)
            chalkStrokes = chalkAnchors.count
        }
        currentChalkAnchor = nil
        lastChalkPoint = nil
    }

    // MARK: Pitch

    private func samplePitch() {
        guard let arView else { return }
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first else {
            return
        }
        // Plane Y axis = surface normal
        let n = SIMD3<Float>(result.worldTransform.columns.1.x,
                             result.worldTransform.columns.1.y,
                             result.worldTransform.columns.1.z)
        let normal = simd_normalize(n)
        let cosAngle = abs(simd_dot(normal, SIMD3<Float>(0, 1, 0)))
        let angleRad = Double(acos(min(1, max(-1, cosAngle))))
        let degrees = RoofPitch.degrees(forAngle: angleRad)

        // Smooth a little — exponential moving avg
        let smoothed = pitchDegrees == 0 ? degrees : pitchDegrees * 0.6 + degrees * 0.4
        pitchDegrees = smoothed
        pitchRatioString = RoofPitch.ratio(forAngle: smoothed * .pi / 180)
        planeDetected = true
    }

    // MARK: Snapshot

    func makeSnapshot(slope: SlopeType) async -> ARInspectionSnapshot {
        let image = await captureSnapshotImage() ?? UIImage()
        let smoothedAngleRad = pitchDegrees * .pi / 180
        // Try to bake a USDZ alongside the snapshot so the results screen can
        // hand it directly to QuickLook without re-running the AR session.
        let usdz: URL? = {
            guard !meshAnchors.isEmpty else { return nil }
            return try? LiDARRoofService.exportUSDZ(
                meshAnchors: Array(meshAnchors.values),
                markers: markers)
        }()
        return ARInspectionSnapshot(
            snapshotImage: image,
            markers: markers,
            chalkStrokeCount: chalkStrokes,
            pitchDegrees: pitchDegrees,
            pitchRatio: RoofPitch.ratio(forAngle: smoothedAngleRad),
            hitsInSquare: markersInSquare,
            squarePlaced: squarePlaced,
            slope: slope,
            lidarRoofAreaSquareFeet: lidarRoofAreaSquareFeet > 0 ? lidarRoofAreaSquareFeet : nil,
            lidarPitchDegrees: lidarPitchDegrees,
            usdzReportURL: usdz
        )
    }

    private func captureSnapshotImage() async -> UIImage? {
        guard let arView else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: Gemini scan + unprojection

    enum ScanOutcome {
        case success(addedMarkers: Int)
        case failure(message: String)
    }

    func scanCurrentFrameWithGemini(slope: SlopeType) async -> ScanOutcome {
        guard let arView else { return .failure(message: "AR session not available.") }
        guard let snapshot = await captureSnapshotImage() else {
            return .failure(message: "Could not capture AR frame.")
        }
        // Snapshot through Gemini using the existing analysis service
        let result = await GeminiAnalysisService.analyzeFull(image: snapshot,
                                                             slope: slope,
                                                             mode: .square,
                                                             squaresCovered: squarePlaced ? 1 : 0)
        if result.failed {
            return .failure(message: "Gemini analysis failed. Try again.")
        }
        if result.usedMock {
            return .failure(message: "Set EXPO_PUBLIC_GEMINI_API_KEY to use real AR scanning.")
        }
        // For each marker, unproject normalized image (x,y) → ARView pixel → raycast into world.
        let bounds = arView.bounds
        var added = 0
        for marker in result.markers {
            let pt = CGPoint(x: CGFloat(marker.x) * bounds.width,
                             y: CGFloat(marker.y) * bounds.height)
            guard let hit = arView.raycast(from: pt, allowing: .estimatedPlane, alignment: .any).first else {
                continue
            }
            placeMarker(atWorld: hit.worldTransform,
                        type: marker.type,
                        source: .gemini,
                        note: marker.note)
            added += 1
        }
        return .success(addedMarkers: added)
    }

    // MARK: Session delegate forwarding

    fileprivate func planeAnchorObserved() {
        if !planeDetected { planeDetected = true }
    }

    // Called from the session delegate (main actor). Keeps our LiDAR anchor
    // dictionaries in sync so we can compute area/pitch and export USDZ.
    fileprivate func updateAnchors(added: [ARAnchor],
                                   updated: [ARAnchor],
                                   removed: [ARAnchor]) {
        for anchor in added + updated {
            if let m = anchor as? ARMeshAnchor {
                meshAnchors[m.identifier] = m
            } else if let p = anchor as? ARPlaneAnchor,
                      p.classification.isValidRoofSurface {
                roofPlaneAnchors[p.identifier] = p
                if !planeDetected { planeDetected = true }
                rebuildShingleGrid(for: p)
            }
        }
        for anchor in removed {
            meshAnchors.removeValue(forKey: anchor.identifier)
            roofPlaneAnchors.removeValue(forKey: anchor.identifier)
            if let grid = planeGridAnchors.removeValue(forKey: anchor.identifier) {
                grid.removeFromParent()
            }
        }
        recomputeLiDARMetrics()
    }

    private func recomputeLiDARMetrics() {
        let anchors = Array(meshAnchors.values)
        guard !anchors.isEmpty else { return }
        let area = LiDARRoofService.roofSurfaceAreaSquareFeet(meshAnchors: anchors)
        if area > 0 { lidarRoofAreaSquareFeet = area }
        if let pitch = LiDARRoofService.roofPitchDegrees(meshAnchors: anchors) {
            lidarPitchDegrees = pitch
            // Replace the gyroscope-style smoothed pitch with the LiDAR value.
            pitchDegrees = pitch
            pitchRatioString = RoofPitch.ratio(forAngle: pitch * .pi / 180)
        }
    }

    /// Exports the current LiDAR roof mesh + damage anchors as a USDZ file
    /// at a temp URL the caller can hand to QuickLook.
    func exportUSDZReport() throws -> URL {
        try LiDARRoofService.exportUSDZ(
            meshAnchors: Array(meshAnchors.values),
            markers: markers
        )
    }

    // MARK: RealityKit shingle grid (3D, conforms to detected plane)

    /// One real 3-tab asphalt shingle tab is ~13.25" wide x 12" tall.
    /// In meters: 0.337 x 0.305 (width:height = 1.1:1).
    private static let shingleCellWidth: Float = 0.337
    private static let shingleCellHeight: Float = 0.305

    private func rebuildShingleGrid(for plane: ARPlaneAnchor) {
        guard let arView else { return }
        // Tear down previous grid for this plane (extent may have grown).
        if let old = planeGridAnchors.removeValue(forKey: plane.identifier) {
            old.removeFromParent()
        }

        let width = plane.planeExtent.width
        let height = plane.planeExtent.height
        guard width > 0.05, height > 0.05 else { return }

        let anchorEntity = AnchorEntity(anchor: plane)
        let grid = makeShingleGridEntity(width: width, height: height)
        // Position the grid at the plane's centroid (in plane-local coords).
        grid.position = plane.center
        // ARPlaneExtent supplies a Y-axis rotation for newer ARKit. Apply it
        // so the grid aligns with the detected dominant edge of the plane.
        let yaw = plane.planeExtent.rotationOnYAxis
        if abs(yaw) > 1e-4 {
            grid.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        }
        anchorEntity.addChild(grid)
        arView.scene.addAnchor(anchorEntity)
        planeGridAnchors[plane.identifier] = anchorEntity
    }

    private func makeShingleGridEntity(width: Float, height: Float) -> Entity {
        let root = Entity()
        // Teal/cyan to match the existing 2D shingle UI.
        let teal = UIColor(Theme.mint)

        // Semi-transparent fill (opacity 0.15)
        var fillMaterial = UnlitMaterial(color: teal.withAlphaComponent(0.15))
        fillMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.15))
        let fill = ModelEntity(
            mesh: .generatePlane(width: width, depth: height),
            materials: [fillMaterial]
        )
        fill.position.y = 0.001 // tiny lift to avoid z-fighting with the plane
        root.addChild(fill)

        // Stroke material — slightly stronger teal for the grid lines.
        let strokeMaterial = UnlitMaterial(color: teal.withAlphaComponent(0.85))
        let lineThickness: Float = 0.004
        let halfW = width / 2
        let halfH = height / 2

        // Compute grid divisions so cells stay close to a real shingle tab.
        let columns = max(1, Int((width / Self.shingleCellWidth).rounded()))
        let rows = max(1, Int((height / Self.shingleCellHeight).rounded()))
        let cellW = width / Float(columns)
        let cellH = height / Float(rows)

        // Vertical lines (along Z axis)
        for i in 0...columns {
            let x = -halfW + Float(i) * cellW
            let line = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(lineThickness, lineThickness, height)),
                materials: [strokeMaterial]
            )
            line.position = SIMD3<Float>(x, 0.0015, 0)
            root.addChild(line)
        }
        // Horizontal lines (along X axis)
        for j in 0...rows {
            let z = -halfH + Float(j) * cellH
            let line = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(width, lineThickness, lineThickness)),
                materials: [strokeMaterial]
            )
            line.position = SIMD3<Float>(0, 0.0015, z)
            root.addChild(line)
        }
        return root
    }

    // MARK: Measure mode (tap two damage anchors)

    private func handleMeasureTap(at viewPoint: CGPoint) {
        guard let arView else { return }
        // Raycast to a world point near the tap, then find the nearest
        // existing damage marker within 0.5m (so taps anywhere on a pin
        // count, not just dead-center).
        guard let result = arView.raycast(from: viewPoint,
                                          allowing: .estimatedPlane,
                                          alignment: .any).first else {
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.warning)
            return
        }
        let p = SIMD3<Float>(result.worldTransform.columns.3.x,
                             result.worldTransform.columns.3.y,
                             result.worldTransform.columns.3.z)
        var best: (UUID, Float)? = nil
        for m in markers {
            let d = simd_distance(m.position, p)
            if d < 0.5, best == nil || d < best!.1 {
                best = (m.id, d)
            }
        }
        guard let pickedID = best?.0,
              let picked = markers.first(where: { $0.id == pickedID }) else {
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.warning)
            return
        }

        if let firstID = measureFirstMarkerID, firstID != pickedID,
           let first = markers.first(where: { $0.id == firstID }) {
            drawMeasurement(from: first.position, to: picked.position)
            measureFirstMarkerID = nil
            measureHighlightAnchor?.removeFromParent()
            measureHighlightAnchor = nil
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
        } else {
            // First tap — clear any old measurement and highlight pick #1.
            measureAnchor?.removeFromParent()
            measureAnchor = nil
            lastMeasurementText = nil
            measureFirstMarkerID = pickedID
            highlightFirstMeasurePick(at: picked.position)
            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
        }
    }

    private func highlightFirstMeasurePick(at position: SIMD3<Float>) {
        guard let arView else { return }
        measureHighlightAnchor?.removeFromParent()
        let anchor = AnchorEntity(world: position)
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.001, radius: 0.06),
            materials: [UnlitMaterial(color: UIColor(Theme.mint).withAlphaComponent(0.7))]
        )
        anchor.addChild(ring)
        arView.scene.addAnchor(anchor)
        measureHighlightAnchor = anchor
    }

    private func drawMeasurement(from a: SIMD3<Float>, to b: SIMD3<Float>) {
        guard let arView else { return }
        measureAnchor?.removeFromParent()

        let anchor = AnchorEntity(world: .init(repeating: 0))
        let mid = (a + b) / 2
        let length = simd_distance(a, b)
        let mintColor = UIColor(Theme.mint)

        // Connecting cylinder between the two anchors
        let segment = ModelEntity(
            mesh: .generateCylinder(height: max(length, 0.001), radius: 0.005),
            materials: [UnlitMaterial(color: mintColor)]
        )
        segment.position = mid
        let dir = b - a
        if simd_length(dir) > 1e-5 {
            let n = simd_normalize(dir)
            let up = SIMD3<Float>(0, 1, 0)
            let dotV = simd_dot(up, n)
            if dotV < 0.9999 && dotV > -0.9999 {
                let axis = simd_normalize(simd_cross(up, n))
                segment.orientation = simd_quatf(angle: acos(dotV), axis: axis)
            } else if dotV < 0 {
                segment.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
            }
        }
        anchor.addChild(segment)

        // End caps so the line reads as a measurement, not a stick.
        for endpoint in [a, b] {
            let cap = ModelEntity(
                mesh: .generateSphere(radius: 0.012),
                materials: [UnlitMaterial(color: mintColor)]
            )
            cap.position = endpoint
            anchor.addChild(cap)
        }

        // Floating distance label in feet & inches
        let label = formatFeetInches(meters: Double(length))
        lastMeasurementText = label
        let text = ModelEntity(
            mesh: .generateText(label,
                                extrusionDepth: 0.002,
                                font: .systemFont(ofSize: 0.07, weight: .heavy),
                                containerFrame: .zero,
                                alignment: .center,
                                lineBreakMode: .byTruncatingTail),
            materials: [UnlitMaterial(color: UIColor(Theme.amber))]
        )
        // Center the generated text mesh on its anchor point.
        let textBounds = text.visualBounds(relativeTo: nil)
        text.position = mid + SIMD3<Float>(0, 0.08, 0) - textBounds.center
        // Small backing plate so the label is readable on busy roofs.
        let plate = ModelEntity(
            mesh: .generatePlane(width: textBounds.extents.x + 0.04,
                                 height: textBounds.extents.y + 0.02,
                                 cornerRadius: 0.01),
            materials: [UnlitMaterial(color: UIColor.black.withAlphaComponent(0.55))]
        )
        plate.position = mid + SIMD3<Float>(0, 0.08, -0.001)
        anchor.addChild(plate)
        anchor.addChild(text)

        arView.scene.addAnchor(anchor)
        measureAnchor = anchor
    }

    private func formatFeetInches(meters: Double) -> String {
        let totalInches = meters * 39.3700787
        var feet = Int(totalInches) / 12
        var inches = Int(totalInches.rounded()) - feet * 12
        if inches == 12 { feet += 1; inches = 0 }
        return "\(feet)' \(inches)\""
    }
}

// MARK: - ARSession delegate proxy
//
// ARSessionDelegate methods come in on background queues, so we keep them on a
// nonisolated proxy and bounce results to the @MainActor coordinator.

private final class SessionDelegateProxy: NSObject, ARSessionDelegate {
    weak var target: ARInspectionCoordinator?
    init(target: ARInspectionCoordinator) { self.target = target }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor [weak self] in
            self?.target?.updateAnchors(added: anchors, updated: [], removed: [])
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor [weak self] in
            self?.target?.updateAnchors(added: [], updated: anchors, removed: [])
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor [weak self] in
            self?.target?.updateAnchors(added: [], updated: [], removed: anchors)
        }
    }
}

#endif
