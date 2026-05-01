import SwiftUI

struct PipelineCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sales Pipeline")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("44 leads · $370k weighted")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button {} label: {
                    Text("Manage")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                }
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MockData.pipeline) { col in
                        PipelineColumnCard(column: col)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
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

            // progress sparkline
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
        switch column.stage {
        case .new: return 0.55
        case .contacted: return 0.70
        case .proposal: return 0.85
        case .won: return 0.95
        case .lost: return 0.30
        }
    }
}
