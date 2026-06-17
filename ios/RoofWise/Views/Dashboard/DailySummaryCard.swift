import SwiftUI

struct DailySummaryCard: View {
    @Environment(CustomerStore.self) private var store
    var embedded: Bool = false

    private var metrics: SalesMetrics { SalesMetrics.compute(from: store.customers) }

    private var summaryHeadline: String {
        if metrics.scheduled == 0 {
            return "Quiet day — focus tomorrow on door knocks in storm-impacted ZIPs."
        }
        if metrics.conversionRate >= 0.25 {
            return "Crushing it — your conversion is well above the 18% benchmark."
        }
        if metrics.claimsFiled >= 3 {
            return "Big claim day. Adjuster follow-ups should be priority #1 tomorrow."
        }
        return "Solid effort. Re-knock no-answers within 48 hours for the highest lift."
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [Theme.mint, Theme.sky],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "sun.horizon.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Wrap-Up")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text(dateLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                Spacer()
                Text("AUTO")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.mintSoft, in: .capsule)
            }

            // Bullet stats
            VStack(alignment: .leading, spacing: 10) {
                bullet(icon: "hand.tap.fill", tint: Theme.sky,
                       text: "**\(metrics.knocked)** doors knocked across your routes")
                bullet(icon: "binoculars.fill", tint: Theme.amber,
                       text: "**\(metrics.inspectionsCompleted)** inspections completed")
                bullet(icon: "doc.badge.plus", tint: Theme.ember,
                       text: "**\(metrics.claimsFiled)** claims filed with carriers")
                bullet(icon: "dollarsign.circle.fill", tint: Theme.mint,
                       text: "**\(SalesMetrics.formatCurrency(metrics.pipelineRevenue))** estimated open pipeline")
            }

            // Insight ribbon
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                       startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 8)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Coach")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.ember)
                    Text(summaryHeadline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(12)
            .background(Theme.emberSoft.opacity(0.7), in: .rect(cornerRadius: 14))
        }
        .cardStyle(padding: 18, radius: 22)
        .padding(.horizontal, embedded ? 0 : 20)
    }

    private func bullet(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 7))
            Text(.init(text))
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
    }
}
