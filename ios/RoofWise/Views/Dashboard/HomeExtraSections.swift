import SwiftUI

// MARK: - Section card chrome

private extension View {
    func homeSectionCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.hairline, lineWidth: 0.6)
            )
            .shadow(color: Theme.ink.opacity(0.05), radius: 12, x: 0, y: 6)
            .padding(.horizontal, 20)
    }
}

// MARK: 1. Today's Goals

struct TodaysGoalsCard: View {
    private struct Goal: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let value: Int
        let target: Int
        var fraction: Double { min(1.0, Double(value) / Double(max(1, target))) }
    }

    private let goals: [Goal] = [
        .init(label: "Doors Knocked", icon: "hand.tap.fill", value: 42, target: 60),
        .init(label: "Inspections", icon: "camera.viewfinder", value: 3, target: 5),
        .init(label: "Leads Booked", icon: "calendar.badge.plus", value: 2, target: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's Goals")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Daily targets · resets at midnight")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Text("\(overallPercent)%")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ember)
                    .monospacedDigit()
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.emberSoft, in: .capsule)
            }

            VStack(spacing: 10) {
                ForEach(goals) { goal in
                    goalRow(goal)
                }
            }
        }
        .homeSectionCard()
    }

    private var overallPercent: Int {
        let avg = goals.map(\.fraction).reduce(0, +) / Double(goals.count)
        return Int((avg * 100).rounded())
    }

    private func goalRow(_ goal: Goal) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.ink.opacity(0.06))
                Image(systemName: goal.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(goal.label)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(goal.value)/\(goal.target)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.canvas)
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * goal.fraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

// MARK: 2. Live Leaderboard

struct LeaderboardCard: View {
    private struct Rep: Identifiable {
        let id = UUID()
        let initials: String
        let name: String
        let signed: Int
        let revenue: String
        let trend: Int
    }

    private let reps: [Rep] = [
        .init(initials: "MR", name: "Mia Rivera", signed: 7, revenue: "$84.2k", trend: 18),
        .init(initials: "AC", name: "Alex Coleman", signed: 5, revenue: "$61.0k", trend: 9),
        .init(initials: "JT", name: "Jordan Tate", signed: 4, revenue: "$48.7k", trend: -3)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.amber)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Team Leaderboard")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("This week · contracts signed")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button {} label: {
                    Text("View all")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(reps.enumerated()), id: \.element.id) { index, rep in
                    repRow(rank: index + 1, rep: rep)
                }
            }
        }
        .homeSectionCard()
    }

    private func repRow(rank: Int, rep: Rep) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(rankColor(rank))
                .frame(width: 18, height: 18)
                .background(rankColor(rank).opacity(0.14), in: .rect(cornerRadius: 5))

            ZStack {
                Circle().fill(Theme.ink.opacity(0.08))
                Text(rep.initials)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(rep.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("\(rep.signed) signed · \(rep.revenue)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: rep.trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("\(abs(rep.trend))%")
                    .font(.system(size: 11, weight: .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(rep.trend >= 0 ? Theme.mint : Theme.crimson)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((rep.trend >= 0 ? Theme.mintSoft : Theme.emberSoft), in: .capsule)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Theme.amber
        case 2: return Theme.inkSoft
        default: return Theme.ember
        }
    }
}

// MARK: 3. Recent Wins feed

struct RecentWinsCard: View {
    private struct Win: Identifiable {
        let id = UUID()
        let initials: String
        let name: String
        let amount: String
        let address: String
        let minutesAgo: Int
        let tint: Color
    }

    private let wins: [Win] = [
        .init(initials: "MR", name: "Mia Rivera",
              amount: "$18,450", address: "412 Chestnut St",
              minutesAgo: 22, tint: Theme.ember),
        .init(initials: "AC", name: "You",
              amount: "$12,800", address: "88 Ridgeview Dr",
              minutesAgo: 96, tint: Theme.sky),
        .init(initials: "JT", name: "Jordan Tate",
              amount: "$9,200", address: "1207 Maple Ln",
              minutesAgo: 184, tint: Theme.mint)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Theme.mint, Color(red: 0.10, green: 0.55, blue: 0.35)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Wins")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Live feed · contracts signed today")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Theme.mint).frame(width: 7, height: 7)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Theme.mint)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.mintSoft, in: .capsule)
            }

            VStack(spacing: 10) {
                ForEach(wins) { win in
                    winRow(win)
                }
            }
        }
        .homeSectionCard()
    }

    private func winRow(_ win: Win) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(win.tint.opacity(0.16))
                Text(win.initials)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(win.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(win.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                    Text(timeLabel(win.minutesAgo))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Text(win.address)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
            Spacer()
            Text(win.amount)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }

    private func timeLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m ago" }
        let h = minutes / 60
        return "\(h)h ago"
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 22) {
            TodaysGoalsCard()
            LeaderboardCard()
            RecentWinsCard()
        }
        .padding(.vertical, 20)
    }
    .background(Theme.canvas)
}
