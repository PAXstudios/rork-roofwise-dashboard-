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
    @Environment(CustomerStore.self) private var store

    private var goals: [HomeLiveData.Goal] {
        HomeLiveData.todaysGoals(customers: store.customers)
    }

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
        guard !goals.isEmpty else { return 0 }
        let avg = goals.map(\.fraction).reduce(0, +) / Double(goals.count)
        return Int((avg * 100).rounded())
    }

    private func goalRow(_ goal: HomeLiveData.Goal) -> some View {
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

// MARK: 2. Live Leaderboard (solo — no fake teammates)

struct LeaderboardCard: View {
    @Environment(CustomerStore.self) private var store

    private var signedCount: Int {
        store.customers.filter {
            $0.stage == .approved || $0.stage == .paid || $0.stage == .jobComplete
        }.count
    }

    private var revenueLabel: String {
        let total = store.customers
            .filter { $0.stage == .approved || $0.stage == .paid || $0.stage == .jobComplete }
            .compactMap { c -> Double? in
                let raw = c.estimatedValue
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "k", with: "000", options: .caseInsensitive)
                if raw.contains("-") {
                    let parts = raw.split(separator: "-").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    guard parts.count == 2 else { return parts.first }
                    return (parts[0] + parts[1]) / 2
                }
                return Double(raw)
            }
            .reduce(0, +)
        if total >= 1000 { return String(format: "$%.0fk", total / 1000) }
        if total > 0 { return String(format: "$%.0f", total) }
        return "—"
    }

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
                    Text("Your Scoreboard")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("This period · your contracts only")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.ink.opacity(0.08))
                    Text(HomeLiveData.displayInitials())
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(HomeLiveData.displayName())
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("\(signedCount) signed · \(revenueLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Text(signedCount == 0 ? "Get started" : "You")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.mintSoft, in: .capsule)
            }
        }
        .homeSectionCard()
    }
}

// MARK: 3. Recent Wins feed (real paid/approved customers only)

struct RecentWinsCard: View {
    @Environment(CustomerStore.self) private var store

    private var wins: [HomeLiveData.Win] {
        HomeLiveData.recentWins(customers: store.customers)
    }

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
                    Text(wins.isEmpty
                         ? "Approved and paid jobs land here"
                         : "Your approved & paid jobs")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
            }

            if wins.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "flag")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                    Text("No wins yet — close your first job to celebrate here.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(wins) { win in
                        winRow(win)
                    }
                }
            }
        }
        .homeSectionCard()
    }

    private func winRow(_ win: HomeLiveData.Win) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(win.tint.opacity(0.16))
                Text(win.initials)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(win.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(win.name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ink)
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
    .environment(CustomerStore())
}
