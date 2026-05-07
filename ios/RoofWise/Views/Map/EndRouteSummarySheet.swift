import SwiftUI

/// Wrap-up sheet shown when a knocking route ends. Reads the closed
/// `KnockSession` and reports totals + conversion ratio. Logging of
/// `.routeCompleted` happens on the Done CTA.
struct EndRouteSummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessionId: UUID
    /// Called after Done so the parent can pop DoorKnockingModeView.
    var onDone: () -> Void = {}

    private var session: KnockSession? {
        KnockSessionStore.shared.session(with: sessionId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headline
                    statGrid
                    elapsedRow
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Route Summary")
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
    }

    // MARK: - Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROUTE COMPLETE")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Theme.mint)
            Text("Route complete")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Nice work — here's what you logged.")
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            statTile(label: "Total Knocks", value: "\(totalKnocks)", color: Theme.ink)
            statTile(label: "Interested", value: "\(interestedCount)", color: Theme.mint)
            statTile(label: "Conversion", value: conversionLabel, color: Theme.ember)
            statTile(label: "Inspections", value: "\(scheduledCount)", color: Theme.sky)
        }
    }

    private func statTile(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            Text(value)
                .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: 96)
        .cardStyle(padding: 0, radius: 16)
    }

    private var elapsedRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.amberSoft)
                Image(systemName: "clock.fill")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("ELAPSED")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkFaint)
                Text(elapsedLabel)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(14)
        .cardStyle(padding: 0, radius: 16)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                if let s = session {
                    ActivityStore.shared.log(
                        .routeCompleted,
                        summary: "Route complete · \(totalKnocks) knocks · \(interestedCount) interested",
                        detail: s.route_storm_alert_id,
                        reportId: "doorKnocking.routeCompleted"
                    )
                }
                onDone()
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(minHeight: 88)
        .background(.ultraThinMaterial)
    }

    // MARK: - Stats

    private var totalKnocks: Int { session?.knocks.count ?? 0 }
    private var interestedCount: Int {
        session?.knocks.filter { $0.outcome == .interested }.count ?? 0
    }
    private var scheduledCount: Int {
        session?.knocks.filter { $0.outcome == .inspection_scheduled }.count ?? 0
    }
    private var conversionLabel: String {
        guard totalKnocks > 0 else { return "0%" }
        let positive = interestedCount + scheduledCount
        let pct = Int((Double(positive) / Double(totalKnocks)) * 100.0)
        return "\(pct)%"
    }
    private var elapsedLabel: String {
        guard let s = session else { return "—" }
        let end = s.ended_at ?? Date()
        let interval = end.timeIntervalSince(s.started_at)
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(m)m"
    }
}

#Preview {
    EndRouteSummarySheet(sessionId: UUID())
}
