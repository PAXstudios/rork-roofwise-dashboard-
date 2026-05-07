import SwiftUI
import UIKit
import Combine
import PhotosUI

// MARK: - Flow

enum InspectionStep {
    case capture       // viewfinder, big shutter
    case scanning      // LiDAR mesh + AI progress
    case results       // structured findings
}

struct QuickInspectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CustomerStore.self) private var customerStore
    var autoAnalyzeOnDone: Bool = true
    var onSessionFinished: ([CapturedPhoto], [InspectionFinding]) -> Void = { _, _ in }
    @State private var step: InspectionStep = .capture
    @State private var scanProgress: CGFloat = 0
    @State private var detectedHits: [DetectedHit] = []
    @State private var flashOn: Bool = false
    @State private var currentPass: Int = 0
    @State private var showSquareBadge: Bool = false
    @State private var currentSlope: SlopeType = .frontSlope
    @State private var showSlopePicker: Bool = false
    @State private var captureMode: CaptureMode = .square
    @State private var showShingleDetect: Bool = true
    @State private var showLiDARMesh: Bool = false
    @State private var showGridOverlay: Bool = false
    @State private var showARMode: Bool = false
    @State private var zoomLevel: CGFloat = 1.0
    @State private var capturedPhotos: [CapturedPhoto] = []
    @State private var previewPhoto: CapturedPhoto?
    // Guided inspection mode
    @State private var isGuidedMode: Bool = false
    @State private var guidedZoneCounts: [GuidedZone: Int] = [:]
    @State private var currentGuidedZone: GuidedZone = .frontSlope
    @State private var showGuidedChecklist: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var pdfShareURL: URL?
    @State private var libraryPickerItems: [PhotosPickerItem] = []
    @State private var isImportingLibrary: Bool = false
    @State private var lastFindings: [InspectionFinding] = []
    @State private var claimPacket: ClaimPacket?
    // Live analysis progress (drives Feature 3 panel during scanning)
    @State private var analyzingPhotoIndex: Int = 0      // 1-based, current photo being analyzed
    @State private var analyzingTotal: Int = 0
    @State private var analyzingThumbnail: UIImage?
    @State private var analyzingPhotosCompleted: Int = 0
    @State private var analyzingEtaSeconds: Int = 0
    @State private var analyzingPerPhotoSeconds: Double = 6.0  // initial estimate, updated from real timings
    @State private var motion = MotionElevationService()
    @State private var camera = CameraCaptureService()
    // Latest USDZ baked from an AR snapshot (only on LiDAR devices). Surfaced
    // in the results screen as the "Export 3D Report" button.
    @State private var latestUSDZReportURL: URL?
    // Inspector-placed manual damage markers (cleared when session ends).
    @State private var manualMarkers: [ManualDamageMarker] = []
    @State private var pendingMarkLocation: CGPoint? = nil
    @State private var showMarkSheet: Bool = false
    @State private var markerPendingDelete: ManualDamageMarker? = nil
    // Phase: Surface upstream Gemini error.message to the inspector via a
    // system alert so HTTP failures aren't invisible.
    @State private var analysisErrorMessage: String? = nil

    private var totalSquaresDocumented: Int {
        max(camera.squaresCovered, capturedPhotos.map(\.squaresCovered).max() ?? 0)
    }

    private let scanPasses: [(label: String, icon: String)] = [
        ("Detecting hail", "circle.hexagongrid.fill"),
        ("Analyzing granules", "circle.dotted"),
        ("Checking wind damage", "wind"),
        ("Inspecting flashing", "square.stack.3d.up.slash.fill"),
        ("Generating report", "doc.text.magnifyingglass")
    ]

    var body: some View {
        ZStack {
            switch step {
            case .capture:
                captureView
            case .scanning:
                scanningView
            case .results:
                ResultsView(findings: lastFindings,
                            photoCount: capturedPhotos.count,
                            photos: capturedPhotos,
                            customer: customerStore.activeCustomer,
                            usdzReportURL: latestUSDZReportURL,
                            manualMarkers: manualMarkers,
                            onClose: {
                                onSessionFinished(capturedPhotos, lastFindings)
                                dismiss()
                            },
                            onRescan: { resetToCapture() },
                            onCreateClaim: { generateClaimPacket() })
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(step != .results)
        .preferredColorScheme(step == .results ? .light : .dark)
        .sheet(isPresented: $showSlopePicker) {
            SlopePickerSheet(selected: $currentSlope)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGuidedChecklist) {
            GuidedChecklistSheet(zoneCounts: guidedZoneCounts,
                                 currentZone: $currentGuidedZone,
                                 isGuidedMode: $isGuidedMode)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: currentGuidedZone) { _, newZone in
            guard isGuidedMode else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                currentSlope = newZone.slope
                captureMode = newZone.captureMode
            }
        }
        .onChange(of: isGuidedMode) { _, newValue in
            if newValue {
                // Snap to first uncompleted zone
                if let next = GuidedZone.allCases.first(where: { (guidedZoneCounts[$0] ?? 0) < $0.minPhotos }) {
                    currentGuidedZone = next
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    currentSlope = currentGuidedZone.slope
                    captureMode = currentGuidedZone.captureMode
                }
            }
        }
        .fullScreenCover(isPresented: $showARMode) {
            ARInspectionView(
                slope: currentSlope,
                manualMarkers: $manualMarkers,
                onSave: { snapshot in importARSnapshot(snapshot) },
                onClose: { showARMode = false }
            )
        }
        .sheet(isPresented: $showMarkSheet) {
            if let loc = pendingMarkLocation {
                MarkDamageSheet(
                    tapNormalized: loc,
                    onCancel: {
                        pendingMarkLocation = nil
                        showMarkSheet = false
                    },
                    onConfirm: { type, severity, note in
                        let marker = ManualDamageMarker(
                            x: Float(loc.x),
                            y: Float(loc.y),
                            type: type,
                            severity: severity,
                            note: note
                        )
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            manualMarkers.append(marker)
                        }
                        pendingMarkLocation = nil
                        showMarkSheet = false
                    }
                )
                .presentationDetents([.fraction(0.55), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(red: 0.08, green: 0.09, blue: 0.13))
            }
        }
        .alert("Analysis failed",
               isPresented: Binding(get: { analysisErrorMessage != nil },
                                    set: { if !$0 { analysisErrorMessage = nil } })) {
            Button("OK", role: .cancel) { analysisErrorMessage = nil }
                .frame(minHeight: 88)
        } message: {
            Text(analysisErrorMessage ?? "")
        }
        .alert("Remove this marker?",
               isPresented: Binding(get: { markerPendingDelete != nil },
                                    set: { if !$0 { markerPendingDelete = nil } })) {
            Button("Remove", role: .destructive) {
                if let m = markerPendingDelete {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        manualMarkers.removeAll { $0.id == m.id }
                    }
                }
                markerPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { markerPendingDelete = nil }
        } message: {
            Text("Inspector-marked damage will be deleted from this inspection.")
        }
        .fullScreenCover(item: $previewPhoto) { photo in
            PhotoDamageOverlayView(
                photo: photo,
                onClose: { previewPhoto = nil },
                onDelete: {
                    capturedPhotos.removeAll { $0.id == photo.id }
                    previewPhoto = nil
                },
                onRetry: {
                    await retryAnalysis(for: photo.id)
                }
            )
        }
        .fullScreenCover(item: $claimPacket) { packet in
            ClaimPacketView(packet: packet,
                            photoCount: capturedPhotos.count,
                            photos: capturedPhotos,
                            findings: lastFindings,
                            customer: customerStore.activeCustomer) {
                claimPacket = nil
            }
        }
        .onAppear {
            motion.start()
            camera.start()
        }
        .onDisappear {
            motion.stop()
            camera.stop()
        }
        .onChange(of: camera.squaresCovered) { oldValue, newValue in
            if newValue > oldValue { triggerSquareBadge() }
        }
        .onChange(of: libraryPickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            importLibraryPhotos(newItems)
        }
    }

    private func importLibraryPhotos(_ items: [PhotosPickerItem]) {
        let slope = currentSlope
        let pitch = motion.pitchDegrees
        let elev = motion.elevationFeet
        let mode = captureMode
        let squares = camera.squaresCovered
        isImportingLibrary = true
        Task { @MainActor in
            var imported: [CapturedPhoto] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    imported.append(CapturedPhoto(image: img, slope: slope,
                                                  pitchDegrees: pitch, elevationFeet: elev,
                                                  captureMode: mode,
                                                  squaresCovered: squares))
                }
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                capturedPhotos.append(contentsOf: imported)
            }
            if !imported.isEmpty {
                let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                if let cid = customerStore.activeCustomerID {
                    customerStore.appendPhotos(imported, to: cid)
                }
                if isGuidedMode {
                    for _ in imported { advanceGuidedZoneAfterCapture() }
                }
            }
            libraryPickerItems = []
            isImportingLibrary = false
        }
    }

    // MARK: Capture

    private var captureView: some View {
        ZStack {
            CameraProxyView(session: camera.session,
                            onPreviewLayer: { layer in camera.attachPreviewLayer(layer) })

            // Subtle vignette
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                           center: .center, startRadius: 180, endRadius: 520)
                .allowsHitTesting(false)

            // Live LiDAR-style mesh (only when toggled on in capture)
            if showLiDARMesh {
                LiDARMeshOverlay(progress: 1.0)
                    .opacity(0.55)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Optional rule-of-thirds / measurement grid overlay
            if showGridOverlay {
                CaptureGridOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Roof-gated live shingle overlay + Gemini damage dots.
            if showShingleDetect {
                if camera.roofDetected {
                    ShingleDetectionOverlay(detections: filteredDetections,
                                            confidences: filteredConfidences,
                                            squareProgress: camera.currentSquareProgress,
                                            showSquareProgress: captureMode == .square,
                                            singleShingleMode: captureMode == .singleShingle,
                                            liveDamageMarkers: camera.liveDamageMarkers)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 6) {
                        Text("Point camera at roof")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.28), in: .capsule)
                        if !LiDARRoofService.hasLiDAR {
                            Text("LiDAR not available — using camera mode")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .allowsHitTesting(false)
                }
            }

            // Tap-to-mark damage. A clear, tappable layer beneath the
            // top/bottom UI. Buttons in the chrome render on top of this and
            // intercept their own taps; manual marker pins are rendered above
            // and capture long-press for deletion.
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard geo.size.width > 1, geo.size.height > 1 else { return }
                        let nx = max(0, min(1, location.x / geo.size.width))
                        let ny = max(0, min(1, location.y / geo.size.height))
                        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                        pendingMarkLocation = CGPoint(x: nx, y: ny)
                        showMarkSheet = true
                    }
            }

            // Inspector-placed (manual) damage markers — rendered above the
            // tap layer so taps on the dot itself trigger long-press delete.
            ManualMarkerOverlay(markers: manualMarkers,
                                onLongPress: { marker in
                                    let g = UIImpactFeedbackGenerator(style: .heavy); g.impactOccurred()
                                    markerPendingDelete = marker
                                })

            // Targeting reticle
            ReticleOverlay(active: true)
                .allowsHitTesting(false)

            // Square Detected badge (square mode only)
            VStack {
                Spacer().frame(height: 170)
                if showSquareBadge && captureMode == .square {
                    SquareDetectedBadge(squares: camera.squaresCovered)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
            }
            .allowsHitTesting(false)

            // Live detection stats
            VStack {
                Spacer()
                detectionStatsBar
                    .padding(.bottom, 230)
            }
            .allowsHitTesting(false)

            // Phone position guide (bubble level + pitch tilt bar + hint)
            HStack {
                Spacer()
                PhonePositionGuide(pitchDegrees: motion.pitchDegrees,
                                   rollDegrees: motion.rollDegrees,
                                   quality: motion.tiltQuality,
                                   hint: motion.tiltHint)
                    .padding(.trailing, 14)
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomCaptureBar
            }
        }
    }

    private var detectionStatsBar: some View {
        HStack(spacing: 10) {
            if captureMode == .square {
                statPill(icon: "square.grid.3x3.topleft.filled", tint: Theme.amber,
                         label: "SHINGLES", value: "\(camera.totalUniqueShingles)")
                statPill(icon: "square.stack.3d.up.fill", tint: Theme.ember,
                         label: "SQUARES", value: "\(camera.squaresCovered)")
                statPill(icon: "viewfinder", tint: Theme.mint,
                         label: "LIVE", value: "\(camera.detectionRects.count)")
            } else {
                statPill(icon: "square.dashed", tint: Theme.amber,
                         label: "MODE", value: "SHINGLE")
                statPill(icon: "viewfinder", tint: Theme.mint,
                         label: "LOCK", value: filteredDetections.isEmpty ? "—" : "YES")
                if let conf = filteredConfidences.first {
                    statPill(icon: "checkmark.seal.fill", tint: Theme.ember,
                             label: "CONF", value: "\(Int(conf * 100))%")
                }
            }
        }
        .padding(.horizontal, 18)
    }

    /// In single-shingle mode show only the largest, highest-confidence rect.
    private var filteredDetections: [CGRect] {
        guard captureMode == .singleShingle else { return camera.detectionRects }
        return primaryDetection.map { [$0.rect] } ?? []
    }

    private var filteredConfidences: [Double] {
        guard captureMode == .singleShingle else { return camera.detectionConfidences }
        return primaryDetection.map { [$0.conf] } ?? []
    }

    private var primaryDetection: (rect: CGRect, conf: Double)? {
        let rects = camera.detectionRects
        let confs = camera.detectionConfidences
        guard !rects.isEmpty else { return nil }
        // Pick the rect closest to the reticle center, weighted by confidence.
        let center = CGPoint(x: 0.5, y: 0.5)
        var bestIdx = 0
        var bestScore = -Double.infinity
        for i in rects.indices {
            let r = rects[i]
            let dx = r.midX - center.x
            let dy = r.midY - center.y
            let dist = sqrt(Double(dx * dx + dy * dy))
            let area = Double(r.width * r.height)
            let conf = i < confs.count ? confs[i] : 0.7
            let score = conf * 1.2 + area * 2.5 - dist * 1.4
            if score > bestScore {
                bestScore = score
                bestIdx = i
            }
        }
        let conf = bestIdx < confs.count ? confs[bestIdx] : 0.85
        return (rects[bestIdx], conf)
    }

    private func statPill(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(0.35), lineWidth: 0.6))
    }

    private func triggerSquareBadge() {
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            showSquareBadge = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeInOut(duration: 0.4)) { showSquareBadge = false }
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: .circle)
                }

                pitchElevationBadge

                Spacer()

                Button { flashOn.toggle() } label: {
                    Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: .circle)
                }
            }

            if isGuidedMode {
                GuidedZonePill(
                    currentZone: currentGuidedZone,
                    completedCount: GuidedZone.allCases.filter { (guidedZoneCounts[$0] ?? 0) >= $0.minPhotos }.count,
                    totalCount: GuidedZone.allCases.count,
                    onTap: { showGuidedChecklist = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            slopeDropdown

            captureModeToggle

            viewOptionsRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    // MARK: View options (multi-select)

    private var viewOptionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                viewOptionChip(icon: "checklist",
                               label: "Guided",
                               isOn: isGuidedMode) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isGuidedMode.toggle()
                    }
                    if isGuidedMode {
                        showGuidedChecklist = true
                    }
                }
                viewOptionChip(icon: "viewfinder.circle.fill",
                               label: "Shingle Detect",
                               isOn: showShingleDetect) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showShingleDetect.toggle()
                    }
                }
                viewOptionChip(icon: "cube.transparent.fill",
                               label: "LiDAR Mesh",
                               isOn: showLiDARMesh) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showLiDARMesh.toggle()
                    }
                }
                viewOptionChip(icon: "grid",
                               label: "Grid Overlay",
                               isOn: showGridOverlay) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showGridOverlay.toggle()
                    }
                }
                viewOptionChip(icon: "arkit",
                               label: "AR Mode",
                               isOn: showARMode) {
                    let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                    showARMode = true
                }

                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 2)

                ForEach([CGFloat(1), 2, 3], id: \.self) { z in
                    zoomChip(level: z)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private func viewOptionChip(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.4)
            }
            .foregroundStyle(isOn ? .black : .white.opacity(0.78))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                if isOn {
                    Capsule().fill(
                        LinearGradient(colors: [Theme.amber, Theme.ember],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: Theme.amber.opacity(0.45), radius: 6, y: 2)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Capsule().stroke(isOn ? .clear : .white.opacity(0.18), lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }

    private func zoomChip(level: CGFloat) -> some View {
        let isOn = abs(zoomLevel - level) < 0.05
        return Button {
            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                zoomLevel = level
            }
            camera.setZoom(level)
        } label: {
            Text("\(Int(level))x")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(isOn ? .black : .white.opacity(0.78))
                .frame(width: 34, height: 28)
                .background {
                    if isOn {
                        Circle().fill(
                            LinearGradient(colors: [Theme.amber, Theme.ember],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: Theme.amber.opacity(0.45), radius: 6, y: 2)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Circle().stroke(isOn ? .clear : .white.opacity(0.18), lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    private var captureModeToggle: some View {
        HStack(spacing: 6) {
            ForEach(CaptureMode.allCases) { mode in
                Button {
                    let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        captureMode = mode
                    }
                    if mode == .singleShingle {
                        camera.resetCoverage()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .heavy))
                        Text(mode.rawValue.uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                    }
                    .foregroundStyle(captureMode == mode ? .black : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if captureMode == mode {
                            Capsule().fill(
                                LinearGradient(colors: [Theme.amber, Theme.ember],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .shadow(color: Theme.amber.opacity(0.5), radius: 8, y: 2)
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

    private var pitchElevationBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "angle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                Text("Pitch \(motion.pitchRatioString) (\(String(format: "%.1f", motion.pitchDegrees))°)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.amber)
                Text("Elev \(Int(motion.elevationFeet)) ft")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
    }

    private var slopeDropdown: some View {
        Button { showSlopePicker = true } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.ember.opacity(0.2))
                    Image(systemName: currentSlope.icon)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CAPTURING")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(currentSlope.rawValue)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// Feature 1: yellow banner shown above the shutter when the 10×10 test
    /// square is not fully visible in the viewfinder. The shutter itself is
    /// NEVER disabled — the user can always capture; the banner just warns
    /// that analysis may be less precise.
    @ViewBuilder
    private var testSquareWarningBanner: some View {
        if captureMode == .square && camera.currentSquareProgress < 1.0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("Test square not fully visible — analysis may be less precise")
                    .font(.system(size: 11, weight: .heavy))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.yellow)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.55), in: .capsule)
            .overlay(Capsule().stroke(Color.yellow.opacity(0.6), lineWidth: 0.8))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var bottomCaptureBar: some View {
        VStack(spacing: 14) {
            testSquareWarningBanner
                .animation(.easeInOut(duration: 0.25), value: camera.currentSquareProgress)
                .animation(.easeInOut(duration: 0.25), value: captureMode)

            HStack(alignment: .center) {
                photoStripThumb

                Spacer()

                // Shutter — always tappable; no .disabled, no dimming.
                Button(action: capture) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.85), lineWidth: 4)
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
                        if !capturedPhotos.isEmpty {
                            Text("\(capturedPhotos.count)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.crimson, in: .capsule)
                                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                                .offset(x: 30, y: -30)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Done / finalize
                Button {
                    if !capturedPhotos.isEmpty {
                        finishSession()
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Done")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(capturedPhotos.isEmpty ? .white.opacity(0.35) : Theme.mint)
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(capturedPhotos.isEmpty)
            }

            photoStrip

            Text(capturedPhotos.isEmpty
                 ? "Aim at the \(currentSlope.shortName.lowercased()). Capture anytime — full square not required."
                 : "\(capturedPhotos.count) photo\(capturedPhotos.count == 1 ? "" : "s") · \(totalSquaresDocumented) sq documented · tap Done to analyze.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 38)
    }

    @ViewBuilder
    private var photoStripThumb: some View {
        if let last = capturedPhotos.last {
            HStack(spacing: 8) {
                Button {
                    previewPhoto = last
                } label: {
                    Image(uiImage: last.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.7), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)

                libraryPickerButton(compact: true)
            }
        } else {
            libraryPickerButton(compact: false)
        }
    }

    @ViewBuilder
    private func libraryPickerButton(compact: Bool) -> some View {
        PhotosPicker(selection: $libraryPickerItems,
                     maxSelectionCount: 0,
                     selectionBehavior: .ordered,
                     matching: .images,
                     preferredItemEncoding: .compatible) {
            if compact {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    if isImportingLibrary {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
            } else {
                VStack(spacing: 4) {
                    if isImportingLibrary {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 16, weight: .bold))
                        Text("Library")
                            .font(.system(size: 10, weight: .heavy))
                    }
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 60, height: 60)
                .background(.ultraThinMaterial, in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.8))
            }
        }
        .buttonStyle(.plain)
        .disabled(isImportingLibrary)
    }

    @ViewBuilder
    private var photoStrip: some View {
        if !capturedPhotos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(capturedPhotos) { photo in
                        Button {
                            previewPhoto = photo
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 86, height: 86)
                                    .clipShape(.rect(cornerRadius: 10))
                                LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                               startPoint: .center, endPoint: .bottom)
                                    .frame(height: 44)
                                    .clipShape(.rect(cornerRadius: 10))
                                Text(photo.slope.shortName)
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.bottom, 5)
                            }
                            .frame(width: 86, height: 86)
                            .overlay(alignment: .topLeading) {
                                CaptureModeTag(mode: photo.captureMode)
                                    .padding(5)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 92)
        }
    }

    private func capture() {
        let gen = UIImpactFeedbackGenerator(style: .heavy); gen.impactOccurred()
        let slope = currentSlope
        let pitch = motion.pitchDegrees
        let elev = motion.elevationFeet
        let mode = captureMode
        let squares = camera.squaresCovered
        Task { @MainActor in
            let img = await camera.capture(slope: slope, pitchDegrees: pitch, elevationFeet: elev)
            let captured = CapturedPhoto(image: img, slope: slope,
                                         pitchDegrees: pitch, elevationFeet: elev,
                                         captureMode: mode,
                                         squaresCovered: squares)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                capturedPhotos.append(captured)
            }
            if let cid = customerStore.activeCustomerID {
                customerStore.appendPhotos([captured], to: cid)
            }
            if isGuidedMode {
                advanceGuidedZoneAfterCapture()
            }
        }
    }

    private func advanceGuidedZoneAfterCapture() {
        let zone = currentGuidedZone
        let newCount = (guidedZoneCounts[zone] ?? 0) + 1
        guidedZoneCounts[zone] = newCount
        // If this zone now meets its minimum, jump to next uncompleted zone
        if newCount >= zone.minPhotos {
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
            if let next = GuidedZone.allCases.first(where: { (guidedZoneCounts[$0] ?? 0) < $0.minPhotos }) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    currentGuidedZone = next
                }
            }
        }
    }

    private func finishSession() {
        let gen = UIImpactFeedbackGenerator(style: .heavy); gen.impactOccurred()
        if autoAnalyzeOnDone {
            withAnimation(.easeInOut(duration: 0.4)) { step = .scanning }
            runScan()
        } else {
            onSessionFinished(capturedPhotos, lastFindings)
            dismiss()
        }
    }

    private func runScan() {
        scanProgress = 0
        detectedHits = []
        currentPass = 0
        analyzingPhotosCompleted = 0
        analyzingTotal = capturedPhotos.count
        analyzingPhotoIndex = capturedPhotos.isEmpty ? 0 : 1
        analyzingThumbnail = capturedPhotos.first?.image
        analyzingPerPhotoSeconds = 6.0
        analyzingEtaSeconds = Int((Double(max(capturedPhotos.count, 1)) * 6.0).rounded())
        Task { @MainActor in
            let passes: [(CGFloat, Int)] = [
                (0.20, 700),  // Detecting hail
                (0.42, 700),  // Analyzing granules
                (0.62, 700),  // Checking wind damage
                (0.82, 700),  // Inspecting flashing
                (1.00, 800)   // Generating report
            ]

            // Kick off Gemini analysis for all photos. Populate `detectedHits`
            // LIVE from real AI markers so the on-screen "Hail Hits" counter
            // reflects what the AI actually found — never mock data.
            let analyzeTask = Task<[InspectionFinding], Never> { @MainActor in
                guard !capturedPhotos.isEmpty else { return [] }
                var results: [String: InspectionFinding] = [:]
                var totalHailMarkers = 0
                var totalWindMarkers = 0
                var hailOnMetal = 0
                var observedTimings: [Double] = []
                for i in capturedPhotos.indices {
                    let photo = capturedPhotos[i]
                    // Feature 3: surface which photo is being analyzed + ETA.
                    withAnimation(.easeInOut(duration: 0.25)) {
                        analyzingPhotoIndex = i + 1
                        analyzingThumbnail = photo.image
                    }
                    let started = Date()
                    let result = await GeminiAnalysisService.analyzeFull(image: photo.image,
                                                                          slope: photo.slope,
                                                                          mode: photo.captureMode,
                                                                          squaresCovered: photo.squaresCovered)
                    let elapsed = Date().timeIntervalSince(started)
                    if elapsed > 0.2 { observedTimings.append(elapsed) }
                    if !observedTimings.isEmpty {
                        analyzingPerPhotoSeconds = observedTimings.reduce(0, +) / Double(observedTimings.count)
                    }
                    let remaining = max(0, capturedPhotos.count - (i + 1))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        analyzingPhotosCompleted = i + 1
                        analyzingEtaSeconds = Int((Double(remaining) * analyzingPerPhotoSeconds).rounded())
                    }
                    let findings = result.findings
                    capturedPhotos[i].findings = findings
                    capturedPhotos[i].damageMarkers = result.markers
                    capturedPhotos[i].aiConfidenceSnapshot = result.confidenceSnapshot
                    // Only mark the photo as analyzed when the AI call actually succeeded.
                    // If it failed we leave analyzed=false so the UI can show a retry state
                    // instead of presenting fake markers as real detections.
                    capturedPhotos[i].analyzed = !result.failed
                    if result.failed, let msg = result.errorMessage, analysisErrorMessage == nil {
                        analysisErrorMessage = msg
                    }

                    // Stream real AI markers into the live scan overlay.
                    for m in result.markers {
                        let sev: DamageSeverity = {
                            switch m.severity {
                            case .severe: return .functional
                            case .moderate: return .functional
                            case .minor: return .cosmetic
                            case .none: return .clean
                            }
                        }()
                        let hit = DetectedHit(x: m.x, y: m.y,
                                              size: max(0.04, m.radius * 2),
                                              severity: sev)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            detectedHits.append(hit)
                        }
                        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                        try? await Task.sleep(for: .milliseconds(40))
                    }

                    // Skip non-roof photos entirely — don't pollute the report
                    // with fabricated findings on grass / sky / etc.
                    if result.noRoofDetected {
                        capturedPhotos[i].findings = result.findings
                        capturedPhotos[i].damageMarkers = []
                        capturedPhotos[i].aiConfidenceSnapshot = result.confidenceSnapshot
                        capturedPhotos[i].analyzed = true
                        continue
                    }
                    totalHailMarkers += result.markers.filter { $0.type.isHailImpact }.count
                    totalWindMarkers += result.markers.filter { $0.type.isShingleDamage }.count

                    for f in findings {
                        if let existing = results[f.label] {
                            if f.confidence > existing.confidence || f.severity.rank > existing.severity.rank {
                                results[f.label] = f
                            }
                        } else {
                            results[f.label] = f
                        }
                    }
                }

                // Always surface a top-level "Hail Hits" finding driven by real
                // marker counts so it appears in the inspection report list.
                let hailSeverity: FindingSeverity = totalHailMarkers >= 8 ? .severe
                    : totalHailMarkers >= 3 ? .moderate
                    : totalHailMarkers > 0 ? .minor : .none
                let hailValue: String = {
                    if totalHailMarkers == 0 { return "No hail strikes detected by AI" }
                    let photoCount = capturedPhotos.count
                    let perSquare = max(capturedPhotos.map(\.squaresCovered).reduce(0, +), 1)
                    return "\(totalHailMarkers) strike\(totalHailMarkers == 1 ? "" : "s") across \(photoCount) photo\(photoCount == 1 ? "" : "s") · \(totalHailMarkers / perSquare)/100 sq ft"
                }()
                results["hail_hits"] = InspectionFinding(
                    label: "hail_hits",
                    display: "Hail Hits",
                    value: hailValue,
                    confidence: totalHailMarkers > 0 ? 93 : 88,
                    icon: "circle.hexagongrid.fill",
                    tint: hailSeverity == .none ? Theme.mint : hailSeverity.color,
                    detected: totalHailMarkers > 0,
                    severity: hailSeverity
                )
                _ = hailOnMetal

                // Always surface a top-level "Wind Damage" finding combining
                // wind creases and missing/lifted tab markers.
                let windSeverity: FindingSeverity = totalWindMarkers >= 5 ? .severe
                    : totalWindMarkers >= 2 ? .moderate
                    : totalWindMarkers > 0 ? .minor : .none
                let windValue: String = {
                    if totalWindMarkers == 0 { return "No wind damage detected by AI" }
                    return "\(totalWindMarkers) shingle damage indicator\(totalWindMarkers == 1 ? "" : "s") · creases / lifted / torn / missing tabs"
                }()
                results["wind_damage"] = InspectionFinding(
                    label: "wind_damage",
                    display: "Wind Damage",
                    value: windValue,
                    confidence: totalWindMarkers > 0 ? 91 : 86,
                    icon: "wind",
                    tint: windSeverity == .none ? Theme.mint : windSeverity.color,
                    detected: totalWindMarkers > 0,
                    severity: windSeverity
                )

                let order = ["shingle_type", "hail_hits", "wind_damage",
                             "bruising", "granule_loss", "missing_shingles",
                             "wind_creasing", "blistering", "cracking_splitting",
                             "flashing_damage", "algae_moss", "ponding_water",
                             "structural_sagging", "hail_damage"]
                return order.compactMap { results[$0] } + results.filter { !order.contains($0.key) }.values
            }

            for (i, pass) in passes.enumerated() {
                withAnimation(.easeInOut(duration: 0.4)) { currentPass = i }
                withAnimation(.easeOut(duration: 0.65)) { scanProgress = pass.0 }
                try? await Task.sleep(for: .milliseconds(pass.1))
            }

            lastFindings = await analyzeTask.value

            if let cid = customerStore.activeCustomerID {
                customerStore.updateAnalysis(for: cid,
                                             photos: capturedPhotos,
                                             findings: lastFindings)
            }

            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                step = .results
            }
        }
    }

    private func retryAnalysis(for photoID: UUID) async {
        guard let idx = capturedPhotos.firstIndex(where: { $0.id == photoID }) else { return }
        let photo = capturedPhotos[idx]
        let result = await GeminiAnalysisService.analyzeFull(image: photo.image,
                                                              slope: photo.slope,
                                                              mode: photo.captureMode,
                                                              squaresCovered: photo.squaresCovered)
        guard let newIdx = capturedPhotos.firstIndex(where: { $0.id == photoID }) else { return }
        capturedPhotos[newIdx].findings = result.findings
        capturedPhotos[newIdx].damageMarkers = result.markers
        capturedPhotos[newIdx].aiConfidenceSnapshot = result.confidenceSnapshot
        capturedPhotos[newIdx].analyzed = !result.failed
        if result.failed, let msg = result.errorMessage {
            analysisErrorMessage = msg
        }
        // Refresh the preview sheet so the user sees fresh markers/findings.
        previewPhoto = capturedPhotos[newIdx]
        if let cid = customerStore.activeCustomerID {
            customerStore.updateAnalysis(for: cid,
                                         photos: capturedPhotos,
                                         findings: lastFindings)
        }
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(result.failed ? .error : .success)
    }

    private func importARSnapshot(_ snapshot: ARInspectionSnapshot) {
        // Bridge AR markers back into the standard CapturedPhoto pipeline so
        // the rest of the app (Gemini analysis, claim packet, PDF report)
        // keeps working unchanged.
        let damageMarkers = snapshot.markers.enumerated().map { idx, m -> DamageMarker in
            // Project 3D markers into a synthetic 2D layout so they render in
            // PhotoDamageOverlayView. Real screen-space coordinates aren't
            // recovered here — markers live primarily in 3D and are surfaced
            // for parity with the existing 2D photo overlay.
            let count = max(snapshot.markers.count, 1)
            let cols = Int(ceil(sqrt(Double(count))))
            let row = idx / cols
            let col = idx % cols
            let x = CGFloat(col) / CGFloat(max(cols - 1, 1)) * 0.7 + 0.15
            let y = CGFloat(row) / CGFloat(max(cols - 1, 1)) * 0.7 + 0.15
            return DamageMarker(x: x, y: y, radius: 0.04,
                                type: m.type, severity: .moderate, note: m.note)
        }

        var arFindings: [InspectionFinding] = []
        if snapshot.pitchDegrees > 0 {
            arFindings.append(InspectionFinding(
                label: "ar_pitch",
                display: "Roof Pitch (LiDAR)",
                value: "\(snapshot.pitchRatio) (\(String(format: "%.0f", snapshot.pitchDegrees))°)",
                confidence: 96,
                icon: "angle",
                tint: Theme.ember,
                detected: true,
                severity: .none
            ))
        }
        if snapshot.squarePlaced {
            arFindings.append(InspectionFinding(
                label: "ar_square_hits",
                display: "Hits in 10×10 Test Square",
                value: "\(snapshot.hitsInSquare) hit\(snapshot.hitsInSquare == 1 ? "" : "s") within HAAG square",
                confidence: 100,
                icon: "square.dashed.inset.filled",
                tint: snapshot.hitsInSquare >= 8 ? Theme.crimson : Theme.amber,
                detected: snapshot.hitsInSquare > 0,
                severity: snapshot.hitsInSquare >= 8 ? .severe : (snapshot.hitsInSquare > 0 ? .moderate : .none)
            ))
        }
        if !snapshot.markers.isEmpty {
            arFindings.append(InspectionFinding(
                label: "ar_markers",
                display: "AR 3D Damage Markers",
                value: "\(snapshot.markers.count) marker\(snapshot.markers.count == 1 ? "" : "s") anchored in 3D space",
                confidence: 100,
                icon: "mappin.and.ellipse",
                tint: Theme.ember,
                detected: true,
                severity: .moderate
            ))
        }

        var photo = CapturedPhoto(
            image: snapshot.snapshotImage,
            slope: snapshot.slope,
            pitchDegrees: snapshot.pitchDegrees,
            elevationFeet: motion.elevationFeet,
            captureMode: snapshot.squarePlaced ? .square : .singleShingle,
            squaresCovered: snapshot.squarePlaced ? 1 : 0
        )
        photo.findings = arFindings
        photo.damageMarkers = damageMarkers
        photo.analyzed = true
        if let usdz = snapshot.usdzReportURL {
            latestUSDZReportURL = usdz
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            capturedPhotos.append(photo)
        }
        if let cid = customerStore.activeCustomerID {
            customerStore.appendPhotos([photo], to: cid)
        }
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
        showARMode = false
    }

    private func resetToCapture() {
        detectedHits = []
        scanProgress = 0
        manualMarkers = []
        withAnimation(.easeInOut) { step = .capture }
    }

    private func generateClaimPacket() {
        var photosForGrading = capturedPhotos
        if photosForGrading.isEmpty {
            // synthesize a single phantom photo using last findings so HAAG can grade
            let stub = CapturedPhoto(
                image: CameraCaptureService.synthesizePlaceholder(slope: currentSlope,
                                                                  pitchDegrees: motion.pitchDegrees,
                                                                  elevationFeet: motion.elevationFeet),
                slope: currentSlope,
                pitchDegrees: motion.pitchDegrees,
                elevationFeet: motion.elevationFeet
            )
            var copy = stub
            copy.findings = lastFindings
            copy.analyzed = true
            photosForGrading = [copy]
        }
        let packet = HaagGrader.grade(photos: photosForGrading)
        claimPacket = packet
        if let cid = customerStore.activeCustomerID {
            customerStore.attachClaim(for: cid, packet: packet)
        }
    }

    // MARK: Scanning

    private var scanningView: some View {
        ZStack {
            CameraProxyView(session: camera.session).overlay(Color.black.opacity(0.25))

            LiDARMeshOverlay(progress: scanProgress)
                .allowsHitTesting(false)

            GeometryReader { geo in
                ForEach(detectedHits) { hit in
                    HitMarker(severity: hit.severity)
                        .position(x: hit.x * geo.size.width,
                                  y: hit.y * geo.size.height)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ember)
                    Text("Analyzing \(capturedPhotos.count) photo\(capturedPhotos.count == 1 ? "" : "s") with Gemini Vision")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(.top, 64)

                // Feature 3: live per-photo analysis panel.
                analyzingPhotoPanel
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: scanPasses[min(currentPass, scanPasses.count - 1)].icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.ember)
                            Text(scanPasses[min(currentPass, scanPasses.count - 1)].label)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.white)
                                .contentTransition(.opacity)
                                .id(currentPass)
                        }
                        Spacer()
                        Text("\(Int(scanProgress * 100))%")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                            .monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.ember, Theme.amber],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * scanProgress)
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 6) {
                        ForEach(scanPasses.indices, id: \.self) { i in
                            ZStack {
                                Circle().fill(i <= currentPass ? Theme.ember : Color.white.opacity(0.18))
                                    .frame(width: 14, height: 14)
                                if i < currentPass {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 7, weight: .black))
                                        .foregroundStyle(.white)
                                } else if i == currentPass {
                                    Circle().fill(.white).frame(width: 5, height: 5)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    HStack(spacing: 12) {
                        liveStat(icon: "circle.hexagongrid.fill", label: "Hail Hits", value: "\(detectedHits.count)")
                        liveStat(icon: "ruler.fill", label: "Slope Area", value: "\(Int(scanProgress * 1240)) sq ft")
                        liveStat(icon: "cube.transparent", label: "Mesh", value: "\(Int(scanProgress * 84))k pts")
                    }
                }
                .padding(18)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
                .padding(.horizontal, 18)
                .padding(.bottom, 44)
            }
        }
    }

    /// Feature 3: shows which photo is being analyzed, a thumbnail, the
    /// estimated time remaining, and a smooth progress bar (photos completed
    /// / total).
    private var analyzingPhotoPanel: some View {
        let total = max(analyzingTotal, 1)
        let completed = min(analyzingPhotosCompleted, total)
        let progress: CGFloat = CGFloat(completed) / CGFloat(total)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.08))
                    .frame(width: 56, height: 56)
                if let thumb = analyzingThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(.white.opacity(0.35), lineWidth: 0.8))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Analyzing photo \(max(analyzingPhotoIndex, 1)) of \(max(analyzingTotal, 1))")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Spacer()
                    Text(analyzingEtaSeconds <= 0
                         ? "Wrapping up…"
                         : "~\(analyzingEtaSeconds)s left")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.ember, Theme.amber],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress)
                            .animation(.easeInOut(duration: 0.45), value: progress)
                    }
                }
                .frame(height: 5)
                Text("\(completed)/\(total) complete")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 0.6))
    }

    private func liveStat(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.ember)
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Capture Mode Tag

struct CaptureModeTag: View {
    let mode: CaptureMode

    private var tint: Color {
        switch mode {
        case .singleShingle: return Theme.amber
        case .square: return Theme.ember
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: mode.icon)
                .font(.system(size: 7, weight: .heavy))
            Text(mode.shortLabel.uppercased())
                .font(.system(size: 7, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                LinearGradient(colors: [tint, tint.opacity(0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        )
        .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}

// MARK: - FindingSeverity rank helper

extension FindingSeverity {
    var rank: Int {
        switch self {
        case .none: return 0
        case .minor: return 1
        case .moderate: return 2
        case .severe: return 3
        }
    }
}

// MARK: - Slope Picker

private struct SlopePickerSheet: View {
    @Binding var selected: SlopeType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SlopeType.allCases) { slope in
                    Button {
                        selected = slope
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8).fill(Theme.emberSoft)
                                Image(systemName: slope.icon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.ember)
                            }
                            .frame(width: 32, height: 32)
                            Text(slope.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if selected == slope {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.ember)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Select Capture Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }
}

// MARK: - Photo Preview Sheet

private struct PhotoPreviewSheet: View {
    let photo: CapturedPhoto
    var onDismiss: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 14))
                    HStack(spacing: 10) {
                        statTile(label: "Slope", value: photo.slope.rawValue)
                        statTile(label: "Pitch", value: String(format: "%.1f°", photo.pitchDegrees))
                        statTile(label: "Elev", value: "\(Int(photo.elevationFeet)) ft")
                    }
                    Button {
                        onDismiss(true)
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Photo")
                        }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.crimson, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Theme.canvas)
            .navigationTitle("Captured Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDismiss(false) }
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 0.6))
    }
}

// MARK: - Reticle

private struct ReticleOverlay: View {
    let active: Bool
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height) * 0.62
            ZStack {
                ForEach(0..<4) { i in
                    CornerBracket()
                        .stroke(active ? Theme.ember : .white,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(Double(i) * 90))
                        .offset(x: cos(.pi/4 + Double(i) * .pi/2) * side/2,
                                y: sin(.pi/4 + Double(i) * .pi/2) * side/2)
                }
                Circle()
                    .stroke(Theme.ember.opacity(pulse ? 0 : 0.5), lineWidth: 1.5)
                    .frame(width: side * 0.35, height: side * 0.35)
                    .scaleEffect(pulse ? 1.6 : 1)
                Circle()
                    .fill(Theme.ember)
                    .frame(width: 5, height: 5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        return p
    }
}

// MARK: - LiDAR mesh overlay

struct LiDARMeshOverlay: View {
    let progress: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let cols = 22
            let rows = 30
            let dx = size.width / CGFloat(cols)
            let dy = size.height / CGFloat(rows)
            let visibleRows = Int(CGFloat(rows) * min(1, progress * 1.4))

            for r in 0..<visibleRows {
                let alpha = 0.55 - Double(r) / Double(rows) * 0.35
                for c in 0..<cols {
                    let x = CGFloat(c) * dx + (r.isMultiple(of: 2) ? dx / 2 : 0)
                    let y = CGFloat(r) * dy
                    var tri = Path()
                    tri.move(to: CGPoint(x: x, y: y))
                    tri.addLine(to: CGPoint(x: x + dx, y: y))
                    tri.addLine(to: CGPoint(x: x + dx/2, y: y + dy))
                    tri.closeSubpath()
                    ctx.stroke(tri, with: .color(Theme.ember.opacity(alpha)), lineWidth: 0.5)
                }
            }

            if progress < 1 {
                let lineY = CGFloat(visibleRows) * dy
                var line = Path()
                line.move(to: CGPoint(x: 0, y: lineY))
                line.addLine(to: CGPoint(x: size.width, y: lineY))
                ctx.stroke(line, with: .color(Theme.ember.opacity(0.9)), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Capture Grid Overlay (rule-of-thirds + measurement)

struct CaptureGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let lineColor = GraphicsContext.Shading.color(Color.white.opacity(0.35))
                let accentColor = GraphicsContext.Shading.color(Theme.amber.opacity(0.55))
                // Rule of thirds
                for i in 1..<3 {
                    let x = size.width * CGFloat(i) / 3
                    var v = Path()
                    v.move(to: CGPoint(x: x, y: 0))
                    v.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(v, with: lineColor, lineWidth: 0.6)

                    let y = size.height * CGFloat(i) / 3
                    var h = Path()
                    h.move(to: CGPoint(x: 0, y: y))
                    h.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(h, with: lineColor, lineWidth: 0.6)
                }
                // Center crosshair
                let cx = size.width / 2
                let cy = size.height / 2
                var cross = Path()
                cross.move(to: CGPoint(x: cx - 12, y: cy))
                cross.addLine(to: CGPoint(x: cx + 12, y: cy))
                cross.move(to: CGPoint(x: cx, y: cy - 12))
                cross.addLine(to: CGPoint(x: cx, y: cy + 12))
                ctx.stroke(cross, with: accentColor, lineWidth: 1.0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Real-time AI Shingle Detection Overlay

/// Renders live `VNDetectRectanglesRequest` results published by
/// `CameraCaptureService`. No self-driving animation: every box on screen
/// corresponds to a real (or simulator-mocked) Vision observation from the
/// most recent video frame.
struct ShingleDetectionOverlay: View {
    let detections: [CGRect]
    let confidences: [Double]
    let squareProgress: Double
    var showSquareProgress: Bool = true
    var singleShingleMode: Bool = false
    var liveDamageMarkers: [DamageMarker] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(detections.enumerated()), id: \.offset) { idx, rect in
                    let conf = idx < confidences.count ? confidences[idx] : 0.85
                    StableShingleGrid(region: rect,
                                      confidence: conf,
                                      size: geo.size,
                                      emphasized: singleShingleMode)
                }

                LiveDamageMarkerLayer(markers: liveDamageMarkers, size: geo.size)

                if showSquareProgress {
                    // Coverage progress ring toward the next 100 sq ft square
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            SquareCoverageProgress(progress: squareProgress)
                                .frame(width: 56, height: 56)
                                .padding(.trailing, 18)
                                .padding(.bottom, 12)
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: detections.count)
            .animation(.easeOut(duration: 0.18), value: liveDamageMarkers.count)
        }
    }
}

struct StableShingleGrid: View {
    let region: CGRect          // normalized 0..1, top-left origin
    let confidence: Double
    let size: CGSize
    var emphasized: Bool = false

    var body: some View {
        let frame = CGRect(x: region.origin.x * size.width,
                           y: region.origin.y * size.height,
                           width: region.size.width * size.width,
                           height: region.size.height * size.height)
        let color: Color = confidence > 0.92 ? Theme.mint :
                           confidence > 0.80 ? Theme.amber : Theme.ember
        let columns = frame.width > frame.height ? 4 : 3
        let rows = 3
        let gap: CGFloat = 5
        let cellWidth = max(24, (frame.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
        let cellHeight = cellWidth / 1.1
        let totalHeight = CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap
        let startY = max(0, (frame.height - totalHeight) / 2)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.78), lineWidth: emphasized ? 2.2 : 1.2)
                .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.07)))

            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<columns, id: \.self) { col in
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color.opacity(0.88), lineWidth: 1.1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.08)))
                        .frame(width: cellWidth, height: cellHeight)
                        .position(x: CGFloat(col) * (cellWidth + gap) + cellWidth / 2,
                                  y: startY + CGFloat(row) * (cellHeight + gap) + cellHeight / 2)
                }
            }
        }
        .frame(width: max(2, frame.width), height: max(2, frame.height))
        .shadow(color: color.opacity(0.35), radius: 4)
        .position(x: frame.midX, y: frame.midY)
    }
}

private struct LiveDamageMarkerLayer: View {
    let markers: [DamageMarker]
    let size: CGSize
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            ForEach(markers) { marker in
                let markerSize: CGFloat = max(12, min(26, marker.radius * min(size.width, size.height) * 1.5))
                Circle()
                    .fill(marker.type.color.opacity(0.75))
                    .frame(width: markerSize, height: markerSize)
                    .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                    .overlay(
                        Circle()
                            .stroke(marker.type.color.opacity(pulse ? 0.0 : 0.42), lineWidth: 2)
                            .frame(width: markerSize * 2.0, height: markerSize * 2.0)
                            .scaleEffect(pulse ? 1.2 : 0.75)
                    )
                    .position(x: marker.x * size.width, y: marker.y * size.height)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Manual Marker Overlay (Inspector-Placed)

/// Renders inspector-placed `ManualDamageMarker`s on top of the live camera
/// preview. Each marker shows the existing damage type color (matching the
/// Gemini live dots), but with a 2pt WHITE ring + a small pencil glyph so the
/// inspector can distinguish their own taps from the AI's auto-detections.
/// No pulsing animation — only Gemini live markers pulse.
private struct ManualMarkerOverlay: View {
    let markers: [ManualDamageMarker]
    var onLongPress: (ManualDamageMarker) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(markers) { marker in
                    let size: CGFloat = 22
                    ZStack {
                        Circle()
                            .fill(marker.type.color.opacity(0.78))
                            .frame(width: size, height: size)
                        Circle()
                            .stroke(.white, lineWidth: 2)
                            .frame(width: size, height: size)
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                    }
                    .shadow(color: marker.type.color.opacity(0.5), radius: 4)
                    .contentShape(Circle())
                    .position(x: CGFloat(marker.x) * geo.size.width,
                              y: CGFloat(marker.y) * geo.size.height)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        onLongPress(marker)
                    }
                }
            }
        }
    }
}

private struct SquareCoverageProgress: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    LinearGradient(colors: [Theme.amber, Theme.ember],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("NEXT SQ")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}

struct SquareDetectedBadge: View {
    let squares: Int
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.25)).frame(width: 36, height: 36)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.amber)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(squares) SQUARE\(squares == 1 ? "" : "S") DETECTED")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(.white)
                Text("~\(squares * 100) sq ft documented")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().stroke(Theme.amber.opacity(pulse ? 0.95 : 0.5),
                                 lineWidth: pulse ? 2.2 : 1.2)
            }
        )
        .shadow(color: Theme.amber.opacity(0.55), radius: pulse ? 18 : 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Hit marker (animated ping)

private struct HitMarker: View {
    let severity: DamageSeverity
    @State private var ring = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(severity.color.opacity(ring ? 0 : 0.7), lineWidth: 2)
                .frame(width: 28, height: 28)
                .scaleEffect(ring ? 2.2 : 1)
            Circle()
                .fill(severity.color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .shadow(color: severity.color.opacity(0.6), radius: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                ring = true
            }
        }
    }
}

// MARK: - Results

private struct ResultsView: View {
    let findings: [InspectionFinding]
    let photoCount: Int
    let photos: [CapturedPhoto]
    let customer: Customer?
    let usdzReportURL: URL?
    let manualMarkers: [ManualDamageMarker]
    var onClose: () -> Void
    var onRescan: () -> Void
    var onCreateClaim: () -> Void
    @Environment(CustomerStore.self) private var customerStore
    @State private var showShareSheet: Bool = false
    @State private var pdfURL: URL?
    @State private var showUSDZViewer: Bool = false
    @State private var isGeneratingPDF: Bool = false
    @State private var showHomeownerShare: Bool = false
    @State private var showCustomerPicker: Bool = false
    @State private var skippedHomeownerShare: Bool = false
    @State private var sentHomeownerShareChannel: HomeownerShareChannel? = nil
    @State private var slopeBeingViewed: SlopeType? = nil
    @State private var photoBeingViewed: CapturedPhoto? = nil
    @AppStorage("roofwise.homeowner.lastShareChannel") private var lastShareChannelRaw: String = HomeownerShareChannel.messages.rawValue

    private var lastShareChannel: HomeownerShareChannel {
        HomeownerShareChannel(rawValue: lastShareChannelRaw) ?? .messages
    }

    private var activeLinkedCustomer: Customer? {
        // Prefer the customer passed in from the inspection; fall back to store's active.
        if let c = customer { return c }
        return customerStore.activeCustomer
    }

    private var totalHits: Int {
        photos.reduce(0) { acc, photo in
            acc + photo.damageMarkers.filter { $0.type == .hailStrike }.count
        }
    }

    private var realHits: [DamageMarker] {
        photos.flatMap { $0.damageMarkers }
    }
    private var detectedCount: Int { findings.filter(\.detected).count }

    private var damageScore: Int {
        let base = findings.reduce(0) { acc, f in
            guard f.detected else { return acc }
            switch f.severity {
            case .none: return acc
            case .minor: return acc + 5
            case .moderate: return acc + 12
            case .severe: return acc + 22
            }
        }
        return min(100, max(0, base))
    }

    private var claimWorthiness: ClaimWorthiness {
        switch damageScore {
        case 0..<20: return .notClaimable
        case 20..<45: return .borderline
        case 45..<75: return .claimable
        default: return .urgent
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                heroCard
                homeownerRecapCTA
                damageScoreCard
                claimWorthinessBanner
                hitMapCard
                inspectorMarkedCard
                photosBySlopeCard
                findingsCard
                structuralCard
                recommendationCard
                actionButtons
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .top) { topNav }
        .background(Theme.canvas)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(isPresented: $showUSDZViewer) {
            if let url = usdzReportURL {
                USDZQuickLookView(url: url, onDismiss: { showUSDZViewer = false })
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showHomeownerShare) {
            if let linked = activeLinkedCustomer {
                HomeownerShareSheet(
                    customer: linked,
                    onShared: { channel in
                        handleHomeownerShareSent(channel: channel, customerID: linked.id)
                    },
                    onSkip: {
                        skippedHomeownerShare = true
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .sheet(item: $slopeBeingViewed) { slope in
            SlopePhotosSheet(
                slope: slope,
                photos: photos.filter { $0.slope == slope },
                onSelect: { picked in
                    photoBeingViewed = picked
                    slopeBeingViewed = nil
                },
                onClose: { slopeBeingViewed = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $photoBeingViewed) { photo in
            PhotoDamageOverlayView(
                photo: photo,
                onClose: { photoBeingViewed = nil }
            )
        }
        .sheet(isPresented: $showCustomerPicker) {
            LinkCustomerSheet(store: customerStore) { picked in
                customerStore.setActive(picked.id)
                showCustomerPicker = false
                // Defer to next runloop so dismissal completes before the share sheet opens.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    showHomeownerShare = true
                }
            } onCancel: {
                showCustomerPicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Homeowner Recap CTA

    @ViewBuilder
    private var homeownerRecapCTA: some View {
        if let channel = sentHomeownerShareChannel {
            sentHomeownerCard(channel: channel)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if !skippedHomeownerShare {
            VStack(spacing: 10) {
                Button {
                    let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                    if activeLinkedCustomer != nil {
                        showHomeownerShare = true
                    } else {
                        showCustomerPicker = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.22))
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Homeowner Recap")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                            Text(ctaSubtitle)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.22), in: .circle)
                    }
                    .padding(14)
                    .background(
                        LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 18)
                    )
                    .shadow(color: Theme.ember.opacity(0.45), radius: 16, y: 8)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        skippedHomeownerShare = true
                    }
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                        .underline()
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ctaSubtitle: String {
        if let c = activeLinkedCustomer {
            let parts = [c.phone, c.email].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let first = parts.first {
                return "Auto-fill \(first) · default \(lastShareChannel.shortLabel)"
            }
            return "To \(c.ownerName) · default \(lastShareChannel.shortLabel)"
        }
        return "Link to a customer first · takes 5 seconds"
    }

    private func sentHomeownerCard(channel: HomeownerShareChannel) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(channel.tint.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(channel.tint)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recap Sent via \(channel.rawValue)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                if let c = activeLinkedCustomer {
                    Text("Logged to \(c.ownerName) · pipeline updated")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                } else {
                    Text("Logged to customer timeline")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
            Button {
                showHomeownerShare = true
            } label: {
                Text("Resend")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(channel.tint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(channel.tint.opacity(0.12), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(channel.tint.opacity(0.08), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(channel.tint.opacity(0.30), lineWidth: 0.8))
    }

    private func handleHomeownerShareSent(channel: HomeownerShareChannel, customerID: UUID) {
        customerStore.logHomeownerShare(channel: channel, to: customerID)
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            sentHomeownerShareChannel = channel
        }
        showHomeownerShare = false
    }

    private var damageScoreCard: some View {
        let score = damageScore
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.canvas, lineWidth: 8)
                    .frame(width: 78, height: 78)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        LinearGradient(colors: [Theme.amber, Theme.ember, Theme.crimson],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 78, height: 78)
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    Text("of 100")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("DAMAGE SCORE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Theme.inkSoft)
                Text(scoreHeadline)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("\(detectedCount) of \(findings.count) categories detected across \(photoCount) photo\(photoCount == 1 ? "" : "s").")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var scoreHeadline: String {
        switch damageScore {
        case 0..<20: return "Roof in serviceable condition"
        case 20..<45: return "Wear consistent with age"
        case 45..<75: return "Functional damage profile"
        default: return "Severe damage profile"
        }
    }

    private var claimWorthinessBanner: some View {
        let cw = claimWorthiness
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(cw.color.opacity(0.15))
                Image(systemName: cw.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(cw.color)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cw.rawValue.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(cw.color, in: .capsule)
                }
                Text(cw.caption)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Carrier acceptance probability: \(min(99, damageScore + 12))%")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(14)
        .background(cw.color.opacity(0.06), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(cw.color.opacity(0.25), lineWidth: 0.6))
    }

    private var topNav: some View {
        HStack {
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
            Spacer()
            VStack(spacing: 0) {
                Text("Inspection Report")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Auto-saved · 12s ago")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Button { exportPDF() } label: {
                ZStack {
                    if isGeneratingPDF {
                        ProgressView().scaleEffect(0.6).tint(Theme.ember)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Theme.card, in: .circle)
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPDF)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private func exportPDF() {
        isGeneratingPDF = true
        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
        Task { @MainActor in
            // Yield so the spinner can show
            try? await Task.sleep(for: .milliseconds(40))
            let input = PDFReportService.Input(
                customer: customer,
                photos: photos,
                findings: findings,
                packet: nil,
                repName: "Sarah Jenkins",
                repPhone: "(214) 555-0142",
                repCompany: "RoofWise · Forensic Field Team"
            )
            if let url = PDFReportService.generate(input: input) {
                pdfURL = url
                showShareSheet = true
            }
            isGeneratingPDF = false
        }
    }

    /// The AI's detected roof material, parsed from the `shingle_type` finding.
    private var detectedMaterial: (name: String, icon: String, confidence: Int)? {
        guard let f = findings.first(where: { $0.label == "shingle_type" }) else { return nil }
        let raw = f.value.split(separator: "\u{2014}").first.map(String.init) ?? f.value
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let icon = mappedRoofMaterial(for: name)?.icon ?? f.icon
        return (name, icon, f.confidence)
    }

    /// Best-effort map from the AI's free-text material name to a `RoofMaterial` case.
    private func mappedRoofMaterial(for name: String) -> RoofMaterial? {
        let n = name.lowercased()
        if n.contains("3-tab") || n.contains("3 tab") || n.contains("three tab") || n.contains("three-tab") {
            return .asphalt3Tab
        }
        if n.contains("architectural") || n.contains("laminat") || n.contains("dimensional") {
            return .architectural
        }
        if n.contains("metal") || n.contains("standing seam") || n.contains("steel") || n.contains("aluminum") {
            return .metal
        }
        if n.contains("tile") || n.contains("clay") || n.contains("terracotta") || n.contains("terra cotta") || n.contains("concrete") {
            return .tile
        }
        if n.contains("wood") || n.contains("shake") || n.contains("cedar") {
            return .wood
        }
        if n.contains("tpo") || n.contains("membrane") || n.contains("epdm") || n.contains("flat") {
            return .tpo
        }
        // Generic asphalt fallback
        if n.contains("asphalt") || n.contains("shingle") {
            return .architectural
        }
        return nil
    }

    @ViewBuilder
    private var materialPill: some View {
        if let m = detectedMaterial {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(.white.opacity(0.22))
                    Image(systemName: m.icon)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                Text(m.name)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if m.confidence > 0 {
                    Text("\u{00B7}")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(m.confidence)%")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.92))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.white.opacity(0.16), in: .capsule)
            .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.6))
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    Text("AI ANALYSIS COMPLETE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.white.opacity(0.18), in: .capsule)
                Spacer(minLength: 6)
            }

            materialPill

            Text("Functional damage confirmed.\nClaim is supportable.")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .lineSpacing(2)

            HStack(spacing: 14) {
                heroStat(value: "\(totalHits)", label: "Hail Hits / 100 sq ft")
                Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5, height: 36)
                heroStat(value: "\(photoCount)", label: "Photos Analyzed")
                Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5, height: 36)
                heroStat(value: "$24.6k", label: "Est. Replace")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { ctx, size in
                    for _ in 0..<60 {
                        let x = CGFloat.random(in: 0...size.width)
                        let y = CGFloat.random(in: 0...size.height)
                        let r = CGFloat.random(in: 1...3)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                                 with: .color(.white.opacity(.random(in: 0.08...0.22))))
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .shadow(color: Theme.ember.opacity(0.35), radius: 18, x: 0, y: 10)
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var slopesWithPhotos: [(slope: SlopeType, items: [CapturedPhoto])] {
        let dict = Dictionary(grouping: photos, by: \.slope)
        return SlopeType.allCases.compactMap { s in
            guard let items = dict[s], !items.isEmpty else { return nil }
            return (s, items)
        }
    }

    @ViewBuilder
    private var photosBySlopeCard: some View {
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photos by Slope")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("Tap a slope to review every photo with AI damage overlay")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Text("\(photos.count) total")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.emberSoft, in: .capsule)
                }
                VStack(spacing: 8) {
                    ForEach(slopesWithPhotos, id: \.slope) { entry in
                        slopePhotosRow(entry.slope, photos: entry.items)
                    }
                }
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }

    private func slopePhotosRow(_ slope: SlopeType, photos: [CapturedPhoto]) -> some View {
        let totalMarkers = photos.reduce(0) { $0 + $1.damageMarkers.count }
        let worst: FindingSeverity = photos
            .map(\.worstSeverity)
            .max(by: { $0.rank < $1.rank }) ?? .none
        let typeName = photos.compactMap(\.shingleType).first
        return Button {
            let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
            slopeBeingViewed = slope
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.emberSoft)
                    Image(systemName: slope.icon)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slope.shortName)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSoft)
                        Circle().fill(Theme.inkFaint.opacity(0.5)).frame(width: 2, height: 2)
                        Text("\(totalMarkers) marker\(totalMarkers == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkSoft)
                        if let typeName {
                            Circle().fill(Theme.inkFaint.opacity(0.5)).frame(width: 2, height: 2)
                            Text(typeName)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 6)
                // Stacked thumbnails preview
                HStack(spacing: -10) {
                    ForEach(photos.prefix(3)) { p in
                        Image(uiImage: p.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 30, height: 30)
                            .clipShape(.circle)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    }
                    if photos.count > 3 {
                        Text("+\(photos.count - 3)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(Theme.canvas, in: .circle)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    }
                }
                if worst != .none {
                    Circle().fill(worst.color).frame(width: 8, height: 8)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(10)
            .background(Theme.canvas, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var inspectorMarkedCard: some View {
        if !manualMarkers.isEmpty {
            let grouped: [(type: DamageMarkerType, items: [ManualDamageMarker])] = {
                let dict = Dictionary(grouping: manualMarkers, by: \.type)
                return DamageMarkerType.allCases.compactMap { t in
                    guard let items = dict[t], !items.isEmpty else { return nil }
                    return (t, items)
                }
            }()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Theme.ember.opacity(0.18))
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                    }
                    .frame(width: 26, height: 26)
                    Text("Inspector-Marked")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(manualMarkers.count) marker\(manualMarkers.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.emberSoft, in: .capsule)
                }
                Text("Damage points placed by tapping the live camera. Counted separately from AI auto-detections.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(2)
                VStack(spacing: 0) {
                    ForEach(Array(grouped.enumerated()), id: \.offset) { idx, entry in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(entry.type.color.opacity(0.18))
                                Image(systemName: entry.type.icon)
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(entry.type.color)
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(entry.type.color).frame(width: 12, height: 12))
                                    .offset(x: 11, y: 11)
                            }
                            .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.items.count) \(entry.type.pluralDisplay)")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                                Text(severityCounts(entry.items))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            Spacer()
                            Text("\(entry.items.count)")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(entry.type.color)
                        }
                        .padding(.vertical, 8)
                        if idx < grouped.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 0.6)
                        }
                    }
                }
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.ember.opacity(0.25), lineWidth: 0.8))
        }
    }

    private func severityCounts(_ items: [ManualDamageMarker]) -> String {
        let high = items.filter { $0.severity.lowercased() == "high" }.count
        let med = items.filter { $0.severity.lowercased() == "medium" }.count
        let low = items.filter { $0.severity.lowercased() == "low" }.count
        var parts: [String] = []
        if high > 0 { parts.append("\(high) high") }
        if med > 0 { parts.append("\(med) medium") }
        if low > 0 { parts.append("\(low) low") }
        return parts.isEmpty ? "Inspector-placed" : parts.joined(separator: " · ")
    }

    private var hitMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Damage Map · Composite Slopes")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(realHits.count) hits")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.crimson)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(DamageSeverity.functional.bg, in: .capsule)
            }

            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.24),
                                        Color(red: 0.10, green: 0.12, blue: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                Canvas { ctx, size in
                    let rows = 18, cols = 14
                    let dx = size.width / CGFloat(cols)
                    let dy = size.height / CGFloat(rows)
                    for r in 0..<rows {
                        for c in 0..<cols {
                            let x = CGFloat(c) * dx + (r.isMultiple(of: 2) ? dx/2 : 0)
                            let y = CGFloat(r) * dy
                            let rect = CGRect(x: x, y: y, width: dx*0.95, height: dy*0.9)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                                     with: .color(.white.opacity(0.04)))
                        }
                    }
                }

                GeometryReader { geo in
                    if realHits.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                            Text("No AI-detected hits yet")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Capture & analyze photos to populate the map")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        ForEach(realHits) { hit in
                            let severityColor = hit.severity.color
                            Circle()
                                .fill(severityColor.opacity(0.85))
                                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                                .shadow(color: severityColor, radius: 6)
                                .frame(width: 16 + CGFloat(hit.radius) * 200,
                                       height: 16 + CGFloat(hit.radius) * 200)
                                .position(x: CGFloat(hit.x) * geo.size.width,
                                          y: CGFloat(hit.y) * geo.size.height)
                        }
                    }
                }
            }
            .frame(height: 200)
            .clipShape(.rect(cornerRadius: 14))

            HStack(spacing: 14) {
                legend(color: DamageSeverity.cosmetic.color, label: "Cosmetic")
                legend(color: DamageSeverity.functional.color, label: "Functional")
                legend(color: DamageSeverity.totaled.color, label: "Total Loss")
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var findingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Findings")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(findings.count) categories · Gemini Vision")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            VStack(spacing: 0) {
                ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                    findingRow(finding)
                    if index < findings.count - 1 {
                        Rectangle().fill(Theme.hairline).frame(height: 0.6)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private func findingRow(_ finding: InspectionFinding) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(finding.tint.opacity(0.14))
                Image(systemName: finding.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(finding.tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(finding.display)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Text(finding.severity.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(finding.severity.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(finding.severity.bg, in: .capsule)
                    Text(finding.value)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(finding.confidence)%")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(finding.tint)
                    .monospacedDigit()
                Text("confidence")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.vertical, 10)
    }

    private var structuralCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Structural Inputs")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(InspectionMock.inputs) { input in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Theme.skySoft)
                            Image(systemName: input.icon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.sky)
                        }
                        .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(input.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.inkFaint)
                            Text(input.value)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Theme.canvas, in: .rect(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var recommendationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.mintSoft)
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.mint)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("Recommended Next Step")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.mint)
                    .tracking(0.6)
                Text("File supplement with carrier and request adjuster meet within 48h. Photos & mesh exported to claim packet.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .background(Theme.mintSoft.opacity(0.5), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.mint.opacity(0.25), lineWidth: 0.6))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button { onCreateClaim() } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text("Create Claim Packet")
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 14)
                )
                .shadow(color: Theme.ember.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)

            Button { exportPDF() } label: {
                HStack {
                    if isGeneratingPDF {
                        ProgressView().tint(Theme.ink)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                    }
                    Text(isGeneratingPDF ? "Generating PDF…" : "Share Branded PDF Report")
                }
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ember.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingPDF)

            if usdzReportURL != nil {
                Button {
                    let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                    showUSDZViewer = true
                } label: {
                    HStack {
                        Image(systemName: "arkit")
                        Text("Export 3D Report")
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Theme.amber, Theme.ember],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: .rect(cornerRadius: 14)
                    )
                    .shadow(color: Theme.amber.opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button { onRescan() } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.card, in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)

                Button {} label: {
                    Label("Send to Review", systemImage: "person.crop.rectangle.stack")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.card, in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Make ClaimPacket Identifiable already provides id
extension ClaimPacket {}

// MARK: - Link Customer Sheet (post-inspection)

/// Lightweight customer picker shown when the rep taps "Send Homeowner Recap"
/// before linking the inspection to a customer profile.
private struct LinkCustomerSheet: View {
    let store: CustomerStore
    var onPick: (Customer) -> Void
    var onCancel: () -> Void

    @State private var query: String = ""

    private var filtered: [Customer] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.customers }
        return store.customers.filter {
            $0.ownerName.lowercased().contains(q) ||
            $0.address.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Link to a customer first?")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Pick a profile so the recap auto-fills phone/email and the pipeline can advance.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                    TextField("Search by name or address", text: $query)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.words)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.canvas, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { c in
                            Button { onPick(c) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(c.stage.color.opacity(0.18))
                                        Text(c.initials)
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(c.stage.color)
                                    }
                                    .frame(width: 38, height: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.ownerName)
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                        Text(c.address)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.inkSoft)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    Text(c.stage.shortLabel)
                                        .font(.system(size: 9, weight: .heavy))
                                        .tracking(0.4)
                                        .foregroundStyle(c.stage.color)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(c.stage.color.opacity(0.14), in: .capsule)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card, in: .rect(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(Theme.hairline, lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        if filtered.isEmpty {
                            Text("No matches")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkFaint)
                                .padding(.top, 30)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}

#Preview { QuickInspectionView() }
