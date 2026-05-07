import SwiftUI

struct DamageAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var analysisStore = DamageAnalysisStore.shared
    let reportId: String

    private var run: DamageAnalysisRun? {
        analysisStore.run(for: reportId)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.ink.ignoresSafeArea()
                animatedBackground
                content
                stickyBar
            }
            .navigationTitle("AI Damage Detection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(minHeight: 56)
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task(id: reportId) {
                analysisStore.start(reportId: reportId)
            }
        }
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                heroCard
                photoScanCard
                progressCard
                markerSummaryCard
                if let error = run?.lastError {
                    errorCard(error)
                }
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var heroCard: some View {
        let isRunning = run?.isRunning ?? true
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.ember.opacity(0.22))
                    Image(systemName: isRunning ? "sparkles" : "checkmark.seal.fill")
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                        .foregroundStyle(isRunning ? Theme.amber : Theme.mint)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isRunning ? "DETECTING DAMAGE" : "ANALYSIS COMPLETE")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(run?.passLabel ?? "Preparing roof images")
                        .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Text("You can go back to the job now. RoofWise will keep analyzing in the background and update the job when it finishes.")
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.10), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var photoScanCard: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.28)
                if let image = run?.currentThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.4))
                }

                DamageScanBeam(progress: run?.progress ?? 0)
                    .allowsHitTesting(false)

                ForEach(run?.currentMarkers ?? []) { marker in
                    AnalysisMarker(marker: marker)
                        .position(x: marker.x * geo.size.width,
                                  y: marker.y * geo.size.height)
                }
            }
            .clipShape(.rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.ember.opacity(0.45), lineWidth: 1))
        }
        .frame(height: 340)
    }

    private var progressCard: some View {
        let progress = run?.progress ?? 0
        let total = max(run?.total ?? 0, 1)
        let current = min(run?.currentIndex ?? 0, total)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photo \(current) of \(total)")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.canvas)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.ember, Theme.amber], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.35), value: progress)
                }
            }
            .frame(height: 10)
        }
        .cardStyle(padding: 18, radius: 20)
    }

    private var markerSummaryCard: some View {
        let markerCount = run?.hits.count ?? 0
        let photoCount = run?.photos.count ?? 0
        return HStack(spacing: 10) {
            statTile(value: "\(markerCount)", label: "Markers", icon: "scope", tint: Theme.crimson)
            statTile(value: "\(photoCount)", label: "Analyzed", icon: "photo.stack.fill", tint: Theme.sky)
            statTile(value: run?.isRunning == true ? "Live" : "Done", label: "Status", icon: "dot.radiowaves.left.and.right", tint: Theme.mint)
        }
    }

    private func statTile(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .cardStyle(padding: 14, radius: 18)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.amber)
            Text(message)
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .cardStyle(padding: 16, radius: 18)
    }

    private var stickyBar: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text(run?.isRunning == true ? "Back to Job · Keep Running" : "Back to Job")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 18))
                    .shadow(color: Theme.ink.opacity(0.28), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(minHeight: 88)
        .background(Theme.canvas.opacity(0.96))
    }

    private var animatedBackground: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<22 {
                    let x = (sin(t * 0.28 + Double(index)) + 1) * 0.5 * size.width
                    let y = (cos(t * 0.21 + Double(index) * 1.7) + 1) * 0.5 * size.height
                    let radius = CGFloat(18 + (index % 5) * 9)
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                                 with: .color(Theme.ember.opacity(0.035)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct DamageScanBeam: View {
    let progress: Double
    @State private var glow = false

    var body: some View {
        GeometryReader { geo in
            let y = geo.size.height * max(0.05, min(0.95, progress))
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Theme.amber.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))
                .frame(height: 74)
                .position(x: geo.size.width / 2, y: y)
                .blur(radius: glow ? 12 : 4)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: glow)
                .onAppear { glow = true }
        }
    }
}

private struct AnalysisMarker: View {
    let marker: DamageMarker
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(marker.type.color.opacity(pulse ? 0 : 0.75), lineWidth: 2)
                .frame(width: 34, height: 34)
                .scaleEffect(pulse ? 1.85 : 0.8)
            Circle()
                .fill(marker.type.color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white, lineWidth: 1.4))
                .shadow(color: marker.type.color.opacity(0.7), radius: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
