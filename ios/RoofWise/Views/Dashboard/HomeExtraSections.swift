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

// MARK: 1. Pipeline funnel (real CustomerStore data — no fake targets)

struct TodaysGoalsCard: View {
    @Environment(CustomerStore.self) private var store

    private struct Goal: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let value: Int
        let denominator: Int
        var fraction: Double { min(1.0, Double(value) / Double(max(1, denominator))) }
    }

    private var metrics: SalesMetrics { SalesMetrics.compute(from: store.customers) }

    private var goals: [Goal] {
        let m = metrics
        let top = max(1, m.knocked)
        return [
            .init(label: "Leads", icon: "hand.tap.fill", value: m.knocked, denominator: top),
            .init(label: "Inspections", icon: "camera.viewfinder", value: m.inspectionsCompleted, denominator: top),
            .init(label: "Approved", icon: "checkmark.seal.fill", value: m.approved, denominator: top)
        ]
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
                    Text("Pipeline Funnel")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Leads → Inspections → Approved")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                if metrics.knocked > 0 {
                    Text("\(Int((metrics.conversionRate * 100).rounded()))%")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                        .monospacedDigit()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.emberSoft, in: .capsule)
                }
            }

            if metrics.knocked == 0 {
                EmptyHint(icon: "person.2.badge.plus",
                          text: "Your pipeline is empty. Log a knock or create a job to start tracking conversion.")
            } else {
                VStack(spacing: 10) {
                    ForEach(goals) { goal in
                        goalRow(goal)
                    }
                }
            }
        }
        .homeSectionCard()
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
                    Text("\(goal.value)")
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

// MARK: 2. Recent Wins feed (real CustomerStore data)

struct RecentWinsCard: View {
    @Environment(CustomerStore.self) private var store

    /// Closed / approved jobs from the real pipeline.
    private var wins: [Customer] {
        store.customers.filter {
            $0.stage == .approved || $0.stage == .materialOrdered ||
            $0.stage == .jobComplete || $0.stage == .paid
        }
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
                    Text("Approved & closed jobs")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
            }

            if wins.isEmpty {
                EmptyHint(icon: "trophy",
                          text: "No closed jobs yet. Approved and paid jobs will appear here.")
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

    private func winRow(_ win: Customer) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.mint.opacity(0.16))
                Text(initials(win.ownerName))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.mint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(win.ownerName.isEmpty ? "Unnamed job" : win.ownerName)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                    Text(win.stage.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
                if !win.address.isEmpty {
                    Text(win.address)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !win.estimatedValue.isEmpty {
                Text(win.estimatedValue)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").compactMap { $0.first }
        return parts.isEmpty ? "•" : parts.prefix(2).map(String.init).joined()
    }
}
