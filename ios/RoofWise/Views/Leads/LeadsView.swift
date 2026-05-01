import SwiftUI

struct LeadsView: View {
    @State private var filter: PipelineStage? = nil

    private let leads: [(name: String, address: String, stage: PipelineStage, value: String, score: Int, storm: Bool)] = [
        ("Smith Residence", "734 Cedar Hollow Rd", .proposal, "$28,400", 92, true),
        ("Patel Custom Build", "5501 Stonebriar Pkwy", .contacted, "$54,200", 84, true),
        ("Hawthorn Apts", "210 Hawthorn Blvd", .new, "$112k", 78, true),
        ("J. Whitman", "12 Ridge Vista", .proposal, "$18,900", 71, false),
        ("Oak Valley HOA", "Oak Valley Block 12", .contacted, "$240k", 68, true),
        ("M. Castellanos", "88 Maple Cove", .new, "$22,500", 60, false),
        ("R. Greene", "1247 Oakridge Ln", .new, "$31,800", 88, true),
        ("D. Park", "920 Bluebonnet Way", .won, "$36,400", 99, false)
    ]

    private var filtered: [(name: String, address: String, stage: PipelineStage, value: String, score: Int, storm: Bool)] {
        guard let filter else { return leads }
        return leads.filter { $0.stage == filter }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leads")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("47 active · 18 storm-tagged")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Search
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkFaint)
                        Text("Search address, owner, claim #")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkFaint)
                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))

                    Button {} label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Theme.ink, in: .rect(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 20)

                // Stage filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", active: filter == nil, color: Theme.ink) { filter = nil }
                        ForEach(PipelineStage.allCases) { stage in
                            FilterChip(label: stage.rawValue, active: filter == stage, color: stage.color) {
                                filter = stage
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Lead list
                VStack(spacing: 10) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, lead in
                        LeadCard(name: lead.name, address: lead.address,
                                 stage: lead.stage, value: lead.value,
                                 score: lead.score, storm: lead.storm)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
    }
}

private struct FilterChip: View {
    let label: String
    let active: Bool
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(active ? color : Theme.card, in: .capsule)
                .overlay(Capsule().stroke(active ? Color.clear : Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

private struct LeadCard: View {
    let name: String
    let address: String
    let stage: PipelineStage
    let value: String
    let score: Int
    let storm: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(stage.color.opacity(0.14))
                Text(initials)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(stage.color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    if storm {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.ember)
                    }
                }
                Text(address)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                HStack(spacing: 6) {
                    Text(stage.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(stage.color)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(stage.color.opacity(0.12), in: .capsule)
                    Text(value)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(scoreColor)
                Text("score")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.04), radius: 8, y: 3)
    }

    private var initials: String {
        name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined()
    }

    private var scoreColor: Color {
        switch score {
        case 85...: return Theme.mint
        case 70..<85: return Theme.amber
        default: return Theme.inkSoft
        }
    }
}
