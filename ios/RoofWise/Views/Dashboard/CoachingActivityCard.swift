import SwiftUI

/// Rep Performance Dashboard surface for coaching activity. Persists every
/// AI Role-Play Coach session, lessons completed, and per-category mastery
/// so managers can see who is training and improving.
struct CoachingActivityCard: View {
    @Environment(TrainingProgressStore.self) private var progress
    @Environment(CustomerStore.self) private var customers
    var onOpenTraining: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            heroRow
            categoryBars
            customerActivityRow
            footerCTA
        }
        .cardStyle(padding: 18, radius: 22)
        .padding(.horizontal, 20)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Theme.sky, Color(red: 0.12, green: 0.36, blue: 0.78)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "mic.and.signal.meter.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rep Coaching Activity")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("AI role-plays · lessons · mastery — auto-logged")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            Spacer()
            Text(streakLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Theme.mint)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.mintSoft, in: .capsule)
        }
    }

    // MARK: Hero — score ring + KPI tiles

    private var heroRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().stroke(Theme.canvas, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.02, Double(avgScore) / 100.0))
                    .stroke(scoreGradient,
                            style: .init(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.6), value: avgScore)
                VStack(spacing: 0) {
                    Text("\(avgScore)")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    Text("avg")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .frame(width: 76, height: 76)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    miniTile(value: "\(progress.coachSessionsCompleted)",
                             label: "Role-plays",
                             icon: "waveform",
                             tint: Theme.sky)
                    miniTile(value: "\(progress.completedCount)",
                             label: "Lessons",
                             icon: "book.fill",
                             tint: Theme.amber)
                }
                HStack(spacing: 8) {
                    miniTile(value: "\(customerPracticeCount)",
                             label: "Customers reps'd",
                             icon: "person.2.fill",
                             tint: Theme.mint)
                    miniTile(value: trendLabel,
                             label: "Trend",
                             icon: trendIcon,
                             tint: trendColor)
                }
            }
        }
    }

    private func miniTile(value: String, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: .rect(cornerRadius: 12))
    }

    // MARK: Category mastery bars

    private var categoryBars: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mastery by Skill Area")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                Spacer()
                if let weak = weakestLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "target")
                            .font(.system(size: 9, weight: .bold))
                        Text("Focus: \(weak)")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(Theme.ember)
                }
            }
            VStack(spacing: 6) {
                ForEach(LessonCategory.allCases) { cat in
                    masteryRow(cat)
                }
            }
        }
        .padding(12)
        .background(Theme.canvas, in: .rect(cornerRadius: 14))
    }

    private func masteryRow(_ cat: LessonCategory) -> some View {
        let score = progress.categoryScores[cat]
        let frac = Double(score ?? 0) / 100.0
        return HStack(spacing: 10) {
            Image(systemName: cat.icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(cat.tint)
                .frame(width: 18, height: 18)
                .background(cat.tint.opacity(0.14), in: .rect(cornerRadius: 5))
            Text(cat.rawValue)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline.opacity(0.6))
                    Capsule()
                        .fill(LinearGradient(colors: [cat.tint, cat.tint.opacity(0.7)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * CGFloat(frac)))
                }
            }
            .frame(height: 6)
            Text(score.map { "\($0)" } ?? "—")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(score == nil ? Theme.inkFaint : Theme.ink)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: Customer-tagged practice

    private var customerActivityRow: some View {
        let top = topCustomers
        if top.isEmpty {
            return AnyView(EmptyView())
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Practiced With")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(top, id: \.id) { c in
                            customerChip(c)
                        }
                    }
                }
                .contentMargins(.horizontal, 0)
            }
        )
    }

    private func customerChip(_ c: Customer) -> some View {
        let count = progress.customerCoachSessions[c.id] ?? 0
        let last = progress.customerCoachLastScore[c.id]
        return HStack(spacing: 8) {
            ZStack {
                Circle().fill(c.stage.color.opacity(0.16))
                Text(c.initials)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(c.stage.color)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.ownerName)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(count) rep\(count == 1 ? "" : "s")")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                    if let last {
                        Text("·").font(.system(size: 9)).foregroundStyle(Theme.inkFaint)
                        Text("\(last)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Theme.sky)
                    }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.canvas, in: .capsule)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
    }

    // MARK: Footer CTA

    private var footerCTA: some View {
        Button(action: onOpenTraining) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(progress.coachSessionsCompleted == 0
                     ? "Run your first role-play"
                     : "Continue training")
                    .font(.system(size: 13, weight: .heavy))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(
                LinearGradient(colors: [Theme.ink, Color(red: 0.18, green: 0.25, blue: 0.45)],
                               startPoint: .leading, endPoint: .trailing),
                in: .rect(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Derived state

    private var avgScore: Int {
        let scores = progress.categoryScores.values
        guard !scores.isEmpty else { return progress.lastCoachScore ?? 0 }
        return scores.reduce(0, +) / scores.count
    }

    private var scoreGradient: LinearGradient {
        let colors: [Color]
        switch avgScore {
        case 80...: colors = [Theme.mint, Color(red: 0.10, green: 0.55, blue: 0.35)]
        case 60..<80: colors = [Theme.amber, Theme.ember]
        default: colors = [Theme.ember, Theme.crimson]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var streakLabel: String {
        let total = progress.coachSessionsCompleted + progress.completedCount
        if total == 0 { return "GET STARTED" }
        if total >= 10 { return "ON FIRE" }
        return "TRAINING"
    }

    private var weakestLabel: String? {
        guard !progress.categoryScores.isEmpty else { return nil }
        return progress.weakestCategory.rawValue
    }

    private var customerPracticeCount: Int {
        progress.customerCoachSessions.keys.count
    }

    private var trendLabel: String {
        guard let last = progress.lastCoachScore else { return "—" }
        let avg = avgScore
        let delta = last - avg
        if delta == 0 { return "Steady" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private var trendIcon: String {
        guard let last = progress.lastCoachScore else { return "minus" }
        if last > avgScore { return "arrow.up.right" }
        if last < avgScore { return "arrow.down.right" }
        return "equal"
    }

    private var trendColor: Color {
        guard let last = progress.lastCoachScore else { return Theme.inkFaint }
        if last > avgScore { return Theme.mint }
        if last < avgScore { return Theme.crimson }
        return Theme.inkSoft
    }

    private var topCustomers: [Customer] {
        let pairs = progress.customerCoachSessions
            .sorted { $0.value > $1.value }
            .prefix(6)
        return pairs.compactMap { id, _ in
            customers.customers.first { $0.id == id }
        }
    }
}

#Preview {
    let p = TrainingProgressStore()
    p.recordCoachSession(score: 78, category: .objections)
    p.recordCoachSession(score: 65, category: .homeowner)
    p.recordCoachSession(score: 82, category: .adjusters)
    p.markComplete("hail-101")
    return ScrollView {
        CoachingActivityCard()
            .environment(p)
            .environment(CustomerStore())
    }
    .background(Theme.canvas)
}
