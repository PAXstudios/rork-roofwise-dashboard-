import SwiftUI

/// Phase 9F. Aggregate AI-accuracy tile shown on the dashboard once the user
/// has logged at least 5 corrections. Hidden entirely below that threshold so
/// we never display a fake number.
struct AICalibrationCard: View {
    @State private var corrections = CorrectionsStore.shared
    @State private var engine = LocalLearningEngine.shared

    private var totalCount: Int { corrections.totalCount }

    /// Weighted accuracy across categories: sum(correct) / sum(total).
    private var weightedAccuracy: Double? {
        let recent = corrections.recent(100)
        guard !recent.isEmpty else { return nil }
        let totals = Dictionary(grouping: recent.flatMap { $0.categoriesAffected }, by: { $0 })
            .mapValues { $0.count }
        guard !totals.isEmpty else { return nil }

        var correct = 0
        var total = 0
        for c in recent {
            total += c.categoriesAffected.count
            if c.correctionType == .confirmed {
                correct += c.categoriesAffected.count
            }
        }
        guard total > 0 else { return nil }
        return Double(correct) / Double(total)
    }

    /// Week-over-week accuracy delta. `nil` when we lack a prior week.
    private var weeklyDelta: Double? {
        let now = Date()
        let lastWeekStart = now.addingTimeInterval(-7 * 86_400)
        let twoWeeksStart = now.addingTimeInterval(-14 * 86_400)
        let lastWeek = corrections.items.filter { $0.correctedAt >= lastWeekStart }
        let priorWeek = corrections.items.filter { $0.correctedAt >= twoWeeksStart && $0.correctedAt < lastWeekStart }
        guard !lastWeek.isEmpty, !priorWeek.isEmpty else { return nil }
        func acc(_ list: [Correction]) -> Double {
            let total = list.flatMap { $0.categoriesAffected }.count
            guard total > 0 else { return 0 }
            let correct = list.filter { $0.correctionType == .confirmed }.flatMap { $0.categoriesAffected }.count
            return Double(correct) / Double(total)
        }
        return acc(lastWeek) - acc(priorWeek)
    }

    var body: some View {
        if totalCount >= 5, let acc = weightedAccuracy {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Theme.skySoft)
                        Image(systemName: "sparkles")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.sky)
                    }
                    .frame(width: 44, height: 44)
                    Text("AI ACCURACY ON YOUR JOBS")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 0)
                }
                Text("\(Int((acc * 100).rounded()))%")
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                if let delta = weeklyDelta, abs(delta) >= 0.005 {
                    let sign = delta >= 0 ? "+" : ""
                    Text("\(sign)\(Int((delta * 100).rounded()))% this week")
                        .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                        .foregroundStyle(delta >= 0 ? Theme.mint : Theme.crimson)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 16, radius: 18)
            .padding(.horizontal, 18)
        }
    }
}
