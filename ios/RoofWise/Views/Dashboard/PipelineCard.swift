import SwiftUI

struct PipelineCard: View {
    @Environment(CustomerStore.self) private var store

    private var columns: [PipelineColumn] {
        HomeLiveData.pipelineColumns(customers: store.customers)
    }

    private var summary: String {
        HomeLiveData.pipelineSummary(customers: store.customers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sales Pipeline")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            if columns.allSatisfy({ $0.count == 0 }) {
                emptyState
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(columns) { col in
                            PipelineColumnCard(column: col)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.inkFaint)
            VStack(alignment: .leading, spacing: 2) {
                Text("No pipeline yet")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("New leads and jobs will fill these stages automatically.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }
}

private struct PipelineColumnCard: View {
    let column: PipelineColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(column.stage.color).frame(width: 8, height: 8)
                Text(column.stage.rawValue.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.inkSoft)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(column.count)")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(column.value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(column.stage.color.opacity(0.15))
                    Capsule().fill(column.stage.color)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)
        }
        .frame(width: 134, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var progress: CGFloat {
        // Honest fill based on count, capped so empty columns stay thin.
        let c = CGFloat(column.count)
        if c <= 0 { return 0.08 }
        return min(0.95, 0.18 + c * 0.12)
    }
}
