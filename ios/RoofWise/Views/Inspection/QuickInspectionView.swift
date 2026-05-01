import SwiftUI

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
    @State private var lidarOn: Bool = true
    @State private var flashOn: Bool = false
    @State private var currentPass: Int = 0

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
                ResultsView(onClose: { dismiss() },
                            onRescan: { resetToCapture() })
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(step != .results)
        .preferredColorScheme(step == .results ? .light : .dark)
    }

    // MARK: Capture

    private var captureView: some View {
        ZStack {
            CameraProxyView()

            // Subtle vignette
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                           center: .center, startRadius: 180, endRadius: 520)
                .allowsHitTesting(false)

            // Targeting reticle
            ReticleOverlay(lidarOn: lidarOn)
                .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                bottomCaptureBar
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: .circle)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(Theme.ember).frame(width: 6, height: 6)
                Text("LiDAR + AI")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .tracking(1.1)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: .capsule)

            Spacer()

            Button { flashOn.toggle() } label: {
                Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: .circle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
    }

    private var bottomCaptureBar: some View {
        VStack(spacing: 18) {
            // mode segmented
            HStack(spacing: 8) {
                modeChip(icon: "viewfinder", title: "Slope", active: true)
                modeChip(icon: "cube.transparent", title: "3D Scan", active: false)
                modeChip(icon: "camera.macro", title: "Macro", active: false)
            }

            HStack(alignment: .center) {
                // LiDAR toggle
                Button { lidarOn.toggle() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .bold))
                        Text("LiDAR")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(lidarOn ? Theme.ember : .white.opacity(0.7))
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: .circle)
                }

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
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Gallery
                Button {} label: {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 16, weight: .bold))
                        Text("Library")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: .circle)
                }
            }

            Text("Aim at the slope. AI will detect hail hits, creases, granule loss.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 44)
    }

    private func modeChip(icon: String, title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(title).font(.system(size: 12, weight: .heavy))
        }
        .foregroundStyle(active ? Theme.ink : .white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(active ? Color.white : Color.white.opacity(0.14), in: .capsule)
    }

    private func capture() {
        let gen = UIImpactFeedbackGenerator(style: .heavy); gen.impactOccurred()
        withAnimation(.easeInOut(duration: 0.4)) { step = .scanning }
        runScan()
    }

    private func runScan() {
        scanProgress = 0
        detectedHits = []
        currentPass = 0
        Task { @MainActor in
            let passes: [(CGFloat, Int)] = [
                (0.20, 700),  // Detecting hail
                (0.42, 700),  // Analyzing granules
                (0.62, 700),  // Checking wind damage
                (0.82, 700),  // Inspecting flashing
                (1.00, 700)   // Generating report
            ]
            for (i, pass) in passes.enumerated() {
                withAnimation(.easeInOut(duration: 0.4)) { currentPass = i }
                withAnimation(.easeOut(duration: 0.65)) { scanProgress = pass.0 }

                // During hail-detection pass, drop hit markers progressively
                if i == 0 {
                    for hit in InspectionMock.hits.prefix(6) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            detectedHits.append(hit)
                        }
                        let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred()
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                } else if i == 2 {
                    for hit in InspectionMock.hits.suffix(6) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                            detectedHits.append(hit)
                        }
                        let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred()
                        try? await Task.sleep(for: .milliseconds(80))
                    }
                }

                try? await Task.sleep(for: .milliseconds(pass.1))
            }

            let success = UINotificationFeedbackGenerator()
            success.notificationOccurred(.success)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                step = .results
            }
        }
    }

    private func resetToCapture() {
        detectedHits = []
        scanProgress = 0
        withAnimation(.easeInOut) { step = .capture }
    }

    // MARK: Scanning

    private var scanningView: some View {
        ZStack {
            CameraProxyView().overlay(Color.black.opacity(0.25))

            // LiDAR mesh overlay
            LiDARMeshOverlay(progress: scanProgress)
                .allowsHitTesting(false)

            // Detected hit markers
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
                // Top
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.ember)
                    Text("Scanning roof surface")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(.top, 64)

                Spacer()

                // Bottom HUD
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

                    // Pass dots
                    HStack(spacing: 6) {
                        ForEach(scanPasses.indices, id: \.self) { i in
                            HStack(spacing: 4) {
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

// MARK: - Reticle

private struct ReticleOverlay: View {
    let lidarOn: Bool
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height) * 0.62
            ZStack {
                ForEach(0..<4) { i in
                    CornerBracket()
                        .stroke(lidarOn ? Theme.ember : .white,
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

private struct LiDARMeshOverlay: View {
    let progress: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let cols = 22
            let rows = 30
            let dx = size.width / CGFloat(cols)
            let dy = size.height / CGFloat(rows)
            let visibleRows = Int(CGFloat(rows) * min(1, progress * 1.4))

            // Mesh triangles
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

            // Scan line
            let lineY = CGFloat(visibleRows) * dy
            var line = Path()
            line.move(to: CGPoint(x: 0, y: lineY))
            line.addLine(to: CGPoint(x: size.width, y: lineY))
            ctx.stroke(line, with: .color(Theme.ember.opacity(0.9)), lineWidth: 1.5)
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
    var onClose: () -> Void
    var onRescan: () -> Void

    @State private var selectedFinding: InspectionFinding?

    private let totalHits = InspectionMock.hits.count
    private let functionalCount = InspectionMock.hits.filter { $0.severity == .functional || $0.severity == .totaled }.count

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
        let score = InspectionMock.damageScore
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
                Text("High damage profile")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("7 of 10 categories detected. Bruising, granule loss, and missing shingles drove the score.")
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

    private var claimWorthinessBanner: some View {
        let cw = InspectionMock.claimWorthiness
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
                Text("Carrier acceptance probability: 92%")
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
                heroStat(value: "\(Int(91))%", label: "Model Confidence")
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
                Text("Damage Map · SW Slope")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("12 hits")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.crimson)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(DamageSeverity.functional.bg, in: .capsule)
            }

            // Map view with simulated roof + hits
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.24),
                                        Color(red: 0.10, green: 0.12, blue: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // Shingle texture
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
                Text("\(InspectionMock.findings.count) detected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            VStack(spacing: 0) {
                ForEach(Array(InspectionMock.findings.enumerated()), id: \.element.id) { index, finding in
                    findingRow(finding)
                    if index < InspectionMock.findings.count - 1 {
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
            Button {} label: {
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

#Preview { QuickInspectionView() }
