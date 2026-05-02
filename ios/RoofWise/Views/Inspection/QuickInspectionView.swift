import SwiftUI
import UIKit
import Combine

// MARK: - Flow

enum InspectionStep {
    case capture       // viewfinder, big shutter
    case scanning      // LiDAR mesh + AI progress
    case results       // structured findings
}

struct QuickInspectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: InspectionStep = .capture
    @State private var scanProgress: CGFloat = 0
    @State private var detectedHits: [DetectedHit] = []
    @State private var flashOn: Bool = false
    @State private var currentPass: Int = 0
    @State private var pingedCells: Set<Int> = []
    @State private var detectedShingles: Int = 0
    @State private var squaresDetected: Int = 0
    @State private var showSquareBadge: Bool = false
    @State private var lidarAssist: Bool = true
    @State private var currentSlope: SlopeType = .frontSlope
    @State private var showSlopePicker: Bool = false
    @State private var capturedPhotos: [CapturedPhoto] = []
    @State private var previewPhoto: CapturedPhoto?
    @State private var lastFindings: [InspectionFinding] = []
    @State private var claimPacket: ClaimPacket?
    @State private var motion = MotionElevationService()
    @State private var camera = CameraCaptureService()

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
                ResultsView(findings: lastFindings.isEmpty ? InspectionMock.findings : lastFindings,
                            photoCount: capturedPhotos.count,
                            onClose: { dismiss() },
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
        .sheet(item: $previewPhoto) { photo in
            PhotoPreviewSheet(photo: photo) { remove in
                if remove { capturedPhotos.removeAll { $0.id == photo.id } }
                previewPhoto = nil
            }
        }
        .fullScreenCover(item: $claimPacket) { packet in
            ClaimPacketView(packet: packet,
                            photoCount: capturedPhotos.count) {
                claimPacket = nil
            }
        }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }

    // MARK: Capture

    private var captureView: some View {
        ZStack {
            CameraProxyView()

            // Subtle vignette
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                           center: .center, startRadius: 180, endRadius: 520)
                .allowsHitTesting(false)

            // Real-time AI shingle detection overlay
            ShingleDetectionOverlay(lidarAssist: lidarAssist,
                                    onDetectedCount: { count in
                                        detectedShingles = count
                                        let newSquares = count / 33
                                        if newSquares > squaresDetected {
                                            squaresDetected = newSquares
                                            triggerSquareBadge()
                                        }
                                    })
                .allowsHitTesting(false)

            // Targeting reticle
            ReticleOverlay(active: true)
                .allowsHitTesting(false)

            // Square Detected badge
            VStack {
                Spacer().frame(height: 170)
                if showSquareBadge {
                    SquareDetectedBadge(squares: squaresDetected)
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

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomCaptureBar
            }
        }
    }

    private var detectionStatsBar: some View {
        HStack(spacing: 10) {
            statPill(icon: "square.grid.3x3.topleft.filled", tint: Theme.amber,
                     label: "SHINGLES", value: "\(detectedShingles)")
            statPill(icon: "square.stack.3d.up.fill", tint: Theme.ember,
                     label: "SQUARES", value: String(format: "%.1f", Double(detectedShingles) / 33.0))
            statPill(icon: lidarAssist ? "cube.transparent.fill" : "cube.transparent",
                     tint: lidarAssist ? Theme.mint : .white.opacity(0.5),
                     label: "LIDAR", value: lidarAssist ? "ON" : "OFF")
                .onTapGesture {
                    let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                    withAnimation(.easeInOut) { lidarAssist.toggle() }
                }
                .allowsHitTesting(true)
        }
        .padding(.horizontal, 18)
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

            slopeDropdown
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
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

    private var bottomCaptureBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                photoStripThumb

                Spacer()

                // Shutter
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
                 ? "Aim at the \(currentSlope.shortName.lowercased()). Capture multiple angles for HAAG-grade documentation."
                 : "\(capturedPhotos.count) photo\(capturedPhotos.count == 1 ? "" : "s") · tap Done to analyze with AI.")
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
        } else {
            VStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16, weight: .bold))
                Text("Library")
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: 60, height: 60)
            .background(.ultraThinMaterial, in: .circle)
        }
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
        Task { @MainActor in
            let img = await camera.capture(slope: slope, pitchDegrees: pitch, elevationFeet: elev)
            let captured = CapturedPhoto(image: img, slope: slope,
                                         pitchDegrees: pitch, elevationFeet: elev)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                capturedPhotos.append(captured)
            }
        }
    }

    private func finishSession() {
        let gen = UIImpactFeedbackGenerator(style: .heavy); gen.impactOccurred()
        withAnimation(.easeInOut(duration: 0.4)) { step = .scanning }
        runScan()
    }

    private func runScan() {
        scanProgress = 0
        detectedHits = []
        currentPass = 0
        pingedCells = []
        Task { @MainActor in
            let passes: [(CGFloat, Int)] = [
                (0.20, 700),  // Detecting hail
                (0.42, 700),  // Analyzing granules
                (0.62, 700),  // Checking wind damage
                (0.82, 700),  // Inspecting flashing
                (1.00, 800)   // Generating report
            ]

            // Kick off Gemini analysis in parallel for all photos
            let analyzeTask = Task<[InspectionFinding], Never> { @MainActor in
                guard !capturedPhotos.isEmpty else { return InspectionMock.findings }
                var results: [String: InspectionFinding] = [:]
                for i in capturedPhotos.indices {
                    let photo = capturedPhotos[i]
                    let findings = await GeminiAnalysisService.analyze(image: photo.image,
                                                                       slope: photo.slope)
                    capturedPhotos[i].findings = findings
                    capturedPhotos[i].analyzed = true
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
                let order = ["bruising", "granule_loss", "missing_shingles", "wind_creasing",
                             "blistering", "cracking_splitting", "flashing_damage",
                             "algae_moss", "ponding_water", "structural_sagging",
                             "hail_damage"]
                return order.compactMap { results[$0] } + results.filter { !order.contains($0.key) }.values
            }

            for (i, pass) in passes.enumerated() {
                withAnimation(.easeInOut(duration: 0.4)) { currentPass = i }
                withAnimation(.easeOut(duration: 0.65)) { scanProgress = pass.0 }

                if i == 0 {
                    for hit in InspectionMock.hits.prefix(6) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            detectedHits.append(hit)
                        }
                        pingCell()
                        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                } else if i == 2 {
                    for hit in InspectionMock.hits.suffix(6) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            detectedHits.append(hit)
                        }
                        pingCell()
                        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                        try? await Task.sleep(for: .milliseconds(80))
                    }
                }

                try? await Task.sleep(for: .milliseconds(pass.1))
            }

            lastFindings = await analyzeTask.value

            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                step = .results
            }
        }
    }

    private func pingCell() {
        let cell = Int.random(in: 0..<(ShingleGridOverlay.rows * ShingleGridOverlay.cols))
        withAnimation(.easeOut(duration: 0.4)) {
            pingedCells.insert(cell)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeIn(duration: 0.4)) {
                _ = pingedCells.remove(cell)
            }
        }
    }

    private func resetToCapture() {
        detectedHits = []
        scanProgress = 0
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
            copy.findings = lastFindings.isEmpty ? InspectionMock.findings : lastFindings
            copy.analyzed = true
            photosForGrading = [copy]
        }
        claimPacket = HaagGrader.grade(photos: photosForGrading)
    }

    // MARK: Scanning

    private var scanningView: some View {
        ZStack {
            CameraProxyView().overlay(Color.black.opacity(0.25))

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

// MARK: - Shingle Grid Overlay (perspective-corrected)

struct ShingleGridOverlay: View {
    static let rows: Int = 14
    static let cols: Int = 10

    let pinged: Set<Int>

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<Self.rows, id: \.self) { r in
                    ForEach(0..<Self.cols, id: \.self) { c in
                        cell(row: r, col: c, size: geo.size)
                    }
                }
            }
        }
    }

    private func cell(row: Int, col: Int, size: CGSize) -> some View {
        // Perspective: rows further away (top) are narrower & shorter.
        let progress = CGFloat(row) / CGFloat(Self.rows)
        let perspective = 0.45 + progress * 0.55
        let rowHeight = size.height / CGFloat(Self.rows + 4) * (0.55 + progress * 0.85)
        let totalRowWidth = size.width * perspective
        let cellWidth = totalRowWidth / CGFloat(Self.cols)
        let stagger: CGFloat = row.isMultiple(of: 2) ? cellWidth / 2 : 0
        let xOrigin = (size.width - totalRowWidth) / 2 + CGFloat(col) * cellWidth + stagger
        var yOrigin: CGFloat = size.height * 0.18
        for rr in 0..<row {
            let p = CGFloat(rr) / CGFloat(Self.rows)
            yOrigin += size.height / CGFloat(Self.rows + 4) * (0.55 + p * 0.85)
        }
        let index = row * Self.cols + col
        let isPinged = pinged.contains(index)
        return RoundedRectangle(cornerRadius: 2)
            .stroke(Theme.ember.opacity(0.55), lineWidth: 0.8)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPinged ? Theme.ember.opacity(0.55) : Color.white.opacity(0.04))
            )
            .frame(width: max(0, cellWidth - 2),
                   height: max(0, rowHeight * 0.92))
            .position(x: xOrigin + cellWidth / 2, y: yOrigin + rowHeight / 2)
            .animation(.easeOut(duration: 0.25), value: isPinged)
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

// MARK: - Real-time AI Shingle Detection Overlay

struct DetectedShingle: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect          // normalized 0..1
    var confidence: Double    // 0..1
    var bornAt: Date = Date()
    var lifespan: TimeInterval
}

struct ShingleDetectionOverlay: View {
    let lidarAssist: Bool
    var onDetectedCount: (Int) -> Void

    @State private var active: [DetectedShingle] = []
    @State private var totalDetected: Int = 0
    @State private var scanY: CGFloat = 0.05
    @State private var ticker: Date = Date()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // optional LiDAR mesh wash
                if lidarAssist {
                    LiDARMeshOverlay(progress: 1.0)
                        .opacity(0.18)
                        .blendMode(.plusLighter)
                }

                // Active scan line — sweeps top→bottom of the viewfinder
                Rectangle()
                    .fill(
                        LinearGradient(colors: [.clear,
                                                Theme.ember.opacity(0.55),
                                                Theme.amber.opacity(0.85),
                                                Theme.ember.opacity(0.55),
                                                .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 60)
                    .blur(radius: 4)
                    .position(x: w / 2, y: scanY * h)
                    .blendMode(.plusLighter)

                // Detected shingle bounding boxes
                ForEach(active) { s in
                    ShingleBoundingBox(detection: s,
                                       size: CGSize(width: w, height: h))
                }
            }
            .onAppear { startEngine(in: geo.size) }
            .onChange(of: ticker) { _, _ in tick(in: geo.size) }
        }
        .onReceive(Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()) { now in
            ticker = now
        }
    }

    private func startEngine(in size: CGSize) {
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: true)) {
            scanY = 0.92
        }
    }

    private func tick(in size: CGSize) {
        let now = Date()
        // expire old detections
        active.removeAll { now.timeIntervalSince($0.bornAt) > $0.lifespan }

        // spawn new ones near the scan line
        let spawnCount = Int.random(in: 1...3)
        for _ in 0..<spawnCount {
            let widthFraction = Double.random(in: 0.13...0.22)
            let heightFraction = widthFraction / 3.0
            let cx = Double.random(in: 0.18...0.82)
            let centerY = Double(scanY) + Double.random(in: -0.06...0.06)
            let cy = max(0.1, min(0.9, centerY))
            let rect = CGRect(x: cx - widthFraction / 2,
                              y: cy - heightFraction / 2,
                              width: widthFraction,
                              height: heightFraction)
            let conf = Double.random(in: 0.78...0.98)
            let life = TimeInterval.random(in: 1.1...1.9)
            active.append(DetectedShingle(rect: rect, confidence: conf, lifespan: life))
            totalDetected += 1
        }
        // cap concurrent boxes for perf
        if active.count > 14 {
            active.removeFirst(active.count - 14)
        }
        onDetectedCount(totalDetected)
    }
}

struct ShingleBoundingBox: View {
    let detection: DetectedShingle
    let size: CGSize
    @State private var appeared = false

    var body: some View {
        let r = detection.rect
        let frame = CGRect(x: r.origin.x * size.width,
                           y: r.origin.y * size.height,
                           width: r.size.width * size.width,
                           height: r.size.height * size.height)
        let color: Color = detection.confidence > 0.92 ? Theme.mint :
                           detection.confidence > 0.85 ? Theme.amber : Theme.ember

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, dash: [3, 2]))
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.12))
                )
                .frame(width: frame.width, height: frame.height)
                .overlay(alignment: .topLeading) {
                    Text("shingle \(Int(detection.confidence * 100))%")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(color, in: .rect(cornerRadius: 2))
                        .offset(x: 0, y: -12)
                }
                // corner ticks
                .overlay {
                    ZStack {
                        cornerTick(color).position(x: 2, y: 2)
                        cornerTick(color).rotationEffect(.degrees(90)).position(x: frame.width - 2, y: 2)
                        cornerTick(color).rotationEffect(.degrees(180)).position(x: frame.width - 2, y: frame.height - 2)
                        cornerTick(color).rotationEffect(.degrees(270)).position(x: 2, y: frame.height - 2)
                    }
                }
        }
        .position(x: frame.midX, y: frame.midY)
        .scaleEffect(appeared ? 1 : 0.7)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { appeared = true }
        }
        .transition(.opacity)
    }

    private func cornerTick(_ color: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 6))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 6, y: 0))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        .frame(width: 6, height: 6)
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
    var onClose: () -> Void
    var onRescan: () -> Void
    var onCreateClaim: () -> Void

    private var totalHits: Int { InspectionMock.hits.count }
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
                damageScoreCard
                claimWorthinessBanner
                hitMapCard
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
            Button {} label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 38, height: 38)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 8)
        .background(Theme.canvas)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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

    private var hitMapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Damage Map · Composite Slopes")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(InspectionMock.hits.count) hits")
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
                    ForEach(InspectionMock.hits) { hit in
                        Circle()
                            .fill(hit.severity.color.opacity(0.85))
                            .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                            .shadow(color: hit.severity.color, radius: 6)
                            .frame(width: 16 + hit.size * 60, height: 16 + hit.size * 60)
                            .position(x: hit.x * geo.size.width, y: hit.y * geo.size.height)
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

#Preview { QuickInspectionView() }
