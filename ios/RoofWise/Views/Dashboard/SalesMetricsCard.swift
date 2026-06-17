import SwiftUI

struct SalesMetricsCard: View {
    @Environment(CustomerStore.self) private var store
    var embedded: Bool = false

    private var metrics: SalesMetrics { SalesMetrics.compute(from: store.customers) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            // Conversion hero
            conversionHero

            // 4-up grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                metricTile(icon: "binoculars.fill",
                           label: "Inspections",
                           value: "\(metrics.inspectionsCompleted)",
                           sub: "completed",
                           tint: Theme.amber)
                metricTile(icon: "doc.badge.plus",
                           label: "Claims",
                           value: "\(metrics.claimsFiled)",
                           sub: "filed",
                           tint: Theme.ember)
                metricTile(icon: "hand.tap.fill",
                           label: "Doors Knocked",
                           value: "\(metrics.knocked)",
                           sub: "this period",
                           tint: Theme.sky)
                metricTile(icon: "calendar.badge.clock",
                           label: "Booked",
                           value: "\(metrics.scheduled)",
                           sub: "inspections",
                           tint: Theme.mint)
            }

            // Pipeline revenue bar
            pipelineRevenueBar
        }
        .cardStyle(padding: 18, radius: 22)
        .padding(.horizontal, embedded ? 0 : 20)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "chart.bar.xaxis.ascending")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sales Performance")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Live from your pipeline · auto-tracked")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            Spacer()
            Text("THIS WEEK")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.ember)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.emberSoft, in: .capsule)
        }
    }

    private var conversionHero: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.canvas, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.02, metrics.conversionRate))
                    .stroke(
                        LinearGradient(colors: [Theme.ember, Theme.amber],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: .init(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(metrics.conversionRate * 100))%")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("conv.")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text("Knock → Booked Inspection")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                Text("\(metrics.scheduled) of \(metrics.knocked) knocks converted")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 4) {
                    Image(systemName: metrics.conversionDeltaUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(metrics.conversionDeltaLabel)
                        .font(.system(size: 11, weight: .heavy))
                }
                .foregroundStyle(metrics.conversionDeltaUp ? Theme.mint : Theme.crimson)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((metrics.conversionDeltaUp ? Theme.mintSoft : Color(red: 1.0, green: 0.92, blue: 0.93)),
                            in: .capsule)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.canvas, in: .rect(cornerRadius: 16))
    }

    private func metricTile(icon: String, label: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 7))
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(sub)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }

    private var pipelineRevenueBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated Pipeline Revenue")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkSoft)
                    Text(SalesMetrics.formatCurrency(metrics.pipelineRevenue))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Won")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.mint)
                    Text(SalesMetrics.formatCurrency(metrics.wonRevenue))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
            }

            // Stacked bar by pipeline phase
            GeometryReader { geo in
                let total = max(1.0, metrics.pipelineRevenue + metrics.wonRevenue)
                let segs: [(Double, Color, String)] = [
                    (metrics.earlyValue, Theme.sky, "Early"),
                    (metrics.midValue, Theme.amber, "Mid"),
                    (metrics.lateValue, Theme.ember, "Late"),
                    (metrics.wonRevenue, Theme.mint, "Won")
                ]
                HStack(spacing: 2) {
                    ForEach(segs.indices, id: \.self) { i in
                        let s = segs[i]
                        let w = max(0, CGFloat(s.0 / total) * geo.size.width - 2)
                        Rectangle()
                            .fill(s.1)
                            .frame(width: w)
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
            }
            .frame(height: 10)

            HStack(spacing: 12) {
                legendDot(color: Theme.sky, label: "Early")
                legendDot(color: Theme.amber, label: "Mid")
                legendDot(color: Theme.ember, label: "Late")
                legendDot(color: Theme.mint, label: "Won")
                Spacer()
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - Metrics computation

struct SalesMetrics {
    var knocked: Int
    var interested: Int
    var scheduled: Int
    var inspectionsCompleted: Int
    var claimsFiled: Int
    var approved: Int
    var pipelineRevenue: Double
    var wonRevenue: Double
    var earlyValue: Double
    var midValue: Double
    var lateValue: Double
    var conversionRate: Double  // scheduled / knocked
    var conversionDeltaUp: Bool
    var conversionDeltaLabel: String

    static func compute(from customers: [Customer]) -> SalesMetrics {
        // Counts (cumulative — anyone past stage X has reached X)
        let stageIdx = { (c: Customer) -> Int in c.stage.stepIndex }
        let knocked = customers.count
        let interested = customers.filter { stageIdx($0) >= JobPipelineStage.interested.stepIndex }.count
        let scheduled = customers.filter { stageIdx($0) >= JobPipelineStage.inspectionScheduled.stepIndex }.count
        let inspections = customers.filter { stageIdx($0) >= JobPipelineStage.inspectionComplete.stepIndex }.count
        let claims = customers.filter { stageIdx($0) >= JobPipelineStage.claimFiled.stepIndex }.count
        let approved = customers.filter { stageIdx($0) >= JobPipelineStage.approved.stepIndex }.count

        // Revenue buckets
        let early = customers.filter {
            let i = stageIdx($0)
            return i >= JobPipelineStage.knocked.stepIndex && i <= JobPipelineStage.inspectionScheduled.stepIndex
        }.reduce(0.0) { $0 + parseValue($1.estimatedValue) }

        let mid = customers.filter {
            let i = stageIdx($0)
            return i >= JobPipelineStage.inspectionComplete.stepIndex && i <= JobPipelineStage.adjusterMeeting.stepIndex
        }.reduce(0.0) { $0 + parseValue($1.estimatedValue) }

        let late = customers.filter {
            let i = stageIdx($0)
            return i >= JobPipelineStage.approved.stepIndex && i <= JobPipelineStage.jobComplete.stepIndex
        }.reduce(0.0) { $0 + parseValue($1.estimatedValue) }

        let won = customers.filter { $0.stage == .paid }
            .reduce(0.0) { $0 + parseValue($1.estimatedValue) }

        let openPipeline = early + mid + late
        let convRate = knocked == 0 ? 0 : Double(scheduled) / Double(knocked)
        // Mock baseline = 0.18 (industry avg); compare
        let deltaUp = convRate >= 0.18
        let deltaPct = Int(((convRate - 0.18) * 100).rounded())
        let deltaLabel = deltaUp
            ? "+\(max(deltaPct, 1)) pts vs. 18% benchmark"
            : "\(deltaPct) pts vs. 18% benchmark"

        return SalesMetrics(
            knocked: knocked,
            interested: interested,
            scheduled: scheduled,
            inspectionsCompleted: inspections,
            claimsFiled: claims,
            approved: approved,
            pipelineRevenue: openPipeline,
            wonRevenue: won,
            earlyValue: early,
            midValue: mid,
            lateValue: late,
            conversionRate: convRate,
            conversionDeltaUp: deltaUp,
            conversionDeltaLabel: deltaLabel
        )
    }

    static func parseValue(_ s: String) -> Double {
        let cleaned = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.lowercased().hasSuffix("k") {
            return (Double(cleaned.dropLast()) ?? 0) * 1_000
        }
        if cleaned.lowercased().hasSuffix("m") {
            return (Double(cleaned.dropLast()) ?? 0) * 1_000_000
        }
        return Double(cleaned) ?? 0
    }

    static func formatCurrency(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.1fk", v / 1_000) }
        return String(format: "$%.0f", v)
    }
}
