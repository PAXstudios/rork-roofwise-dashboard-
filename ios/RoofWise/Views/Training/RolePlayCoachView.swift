import SwiftUI

struct RolePlayCoachView: View {
    @Bindable var progress: TrainingProgressStore
    /// When supplied, the coach is locked to this customer's scenario
    /// and uses their real context (objections, stage, insurance) in prompts.
    var customerContext: CustomerCoachContext? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var pitch: String = ""
    @State private var scenario: Scenario = .knockColdStorm
    @State private var feedback: CoachFeedback? = nil
    @State private var isCoaching = false

    enum Scenario: String, CaseIterable, Identifiable {
        case knockColdStorm = "Cold knock — post-storm"
        case followupAdjuster = "Follow-up — adjuster scheduled"
        case objectionRoofer = "Objection — already have a roofer"
        case closeAfterInspection = "Close — after inspection"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .knockColdStorm: return "cloud.bolt.rain.fill"
            case .followupAdjuster: return "calendar.badge.clock"
            case .objectionRoofer: return "bubble.left.and.exclamationmark.bubble.right.fill"
            case .closeAfterInspection: return "checkmark.seal.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    if let ctx = customerContext {
                        customerScenarioCard(ctx)
                    } else {
                        scenarioPicker
                    }
                    pitchEditor
                    runButton

                    if let fb = feedback {
                        feedbackBlock(fb)
                    } else if isCoaching {
                        coachingShimmer
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Role-Play Coach")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.ember)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.sky, Color(red: 0.12, green: 0.36, blue: 0.78)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "mic.and.signal.meter.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pitch coach powered by Gemini")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Type your door-knock pitch. Get a score, strengths, fixes, and a sharper rewrite you can use today.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var scenarioPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenario")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Scenario.allCases) { s in
                        Button {
                            withAnimation(.spring(duration: 0.25)) { scenario = s }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: s.icon).font(.system(size: 11, weight: .bold))
                                Text(s.rawValue).font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(scenario == s ? .white : Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(scenario == s ? Theme.ink : Theme.card,
                                        in: .capsule)
                            .overlay(Capsule().stroke(Theme.hairline, lineWidth: scenario == s ? 0 : 0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    private var pitchEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your pitch")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)
            ZStack(alignment: .topLeading) {
                if pitch.isEmpty {
                    Text("Hi, I'm Jordan with RoofWise — we've been on three roofs this morning that took serious hail damage from last week's storm…")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(14)
                }
                TextEditor(text: $pitch)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
            }
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))

            HStack {
                Text("\(pitch.split(separator: " ").count) words")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                if !pitch.isEmpty {
                    Button("Clear") { pitch = ""; feedback = nil }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private var runButton: some View {
        Button {
            Task { await coach() }
        } label: {
            HStack(spacing: 8) {
                if isCoaching {
                    ProgressView().tint(.white).controlSize(.small)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .bold))
                }
                Text(isCoaching ? "Coaching…" : "Coach my pitch")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Theme.sky, Color(red: 0.12, green: 0.36, blue: 0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: .rect(cornerRadius: 16)
            )
            .shadow(color: Theme.sky.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(pitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCoaching)
        .opacity(pitch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
    }

    private var coachingShimmer: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.canvas)
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6)
                    )
                    .opacity(0.7)
            }
        }
    }

    private func feedbackBlock(_ fb: CoachFeedback) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Score header
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.hairline, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: Double(fb.overallScore) / 100.0)
                        .stroke(scoreGradient(fb.overallScore),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.6), value: fb.overallScore)
                    VStack(spacing: 0) {
                        Text("\(fb.overallScore)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text("/100")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scoreLabel(fb.overallScore))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text("Tone read: \(fb.tone)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            .cardStyle()

            // Strengths
            feedbackList(title: "What worked", items: fb.strengths,
                         icon: "checkmark.circle.fill", tint: Theme.mint, bg: Theme.mintSoft)

            // Improvements
            feedbackList(title: "What to fix", items: fb.improvements,
                         icon: "arrow.up.right.circle.fill", tint: Theme.ember, bg: Theme.emberSoft)

            // Rewritten pitch
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.amber)
                    Text("Sharper rewrite")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = fb.rewrittenPitch
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ember)
                    }
                }
                Text(fb.rewrittenPitch)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.amberSoft.opacity(0.5), in: .rect(cornerRadius: 14))
            }
            .cardStyle()
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func feedbackList(title: String, items: [String], icon: String,
                              tint: Color, bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 5))
                        .foregroundStyle(tint).padding(.top, 6)
                    Text(item).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(bg, in: .rect(cornerRadius: 16))
    }

    // MARK: - Logic

    private var resolvedScenarioLabel: String {
        if let ctx = customerContext { return ctx.scenarioTitle }
        return scenario.rawValue
    }

    private var resolvedCategory: LessonCategory {
        if let ctx = customerContext {
            switch ctx.stage {
            case .knocked: return .objections
            case .interested, .inspectionComplete, .recapSent, .jobComplete: return .homeowner
            case .inspectionScheduled: return .hailDamage
            case .claimFiled, .approved, .materialOrdered: return .claims
            case .adjusterMeeting: return .adjusters
            case .paid: return .objections
            }
        }
        switch scenario {
        case .knockColdStorm: return .objections
        case .followupAdjuster: return .adjusters
        case .objectionRoofer: return .objections
        case .closeAfterInspection: return .homeowner
        }
    }

    private func coach() async {
        isCoaching = true
        feedback = nil
        let result = await TrainingCoachService.coachPitch(
            pitch,
            scenario: resolvedScenarioLabel,
            customerBrief: customerContext?.promptBrief
        )
        await MainActor.run {
            withAnimation(.spring(duration: 0.4)) {
                feedback = result
            }
            progress.recordCoachSession(
                score: result.overallScore,
                category: resolvedCategory,
                customerID: customerContext?.customerID
            )
            isCoaching = false
        }
    }

    // MARK: - Customer-aware scenario card

    private func customerScenarioCard(_ ctx: CustomerCoachContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ctx.stage.color)
                Text("Practicing with")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                Spacer()
                Text(ctx.stage.shortLabel.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(ctx.stage.color, in: .capsule)
            }
            Text(ctx.ownerName)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(ctx.address)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
            if !ctx.insuranceCompany.isEmpty {
                contextChip(icon: "shield.lefthalf.filled",
                            label: "Carrier: \(ctx.insuranceCompany)")
            }
            if !ctx.recentObjections.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Their objections / notes")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(Theme.inkSoft)
                        .textCase(.uppercase)
                    ForEach(ctx.recentObjections.prefix(3), id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.amber)
                                .padding(.top, 3)
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.amberSoft.opacity(0.5), in: .rect(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ctx.stage.color.opacity(0.35), lineWidth: 0.8))
    }

    private func contextChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(label).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Theme.canvas, in: .capsule)
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 90...: return "Closer-grade pitch"
        case 75..<90: return "Strong — small tweaks"
        case 60..<75: return "Solid base, needs sharpening"
        default: return "Let's tighten this up"
        }
    }

    private func scoreGradient(_ score: Int) -> LinearGradient {
        let colors: [Color]
        switch score {
        case 80...: colors = [Theme.mint, Color(red: 0.10, green: 0.55, blue: 0.35)]
        case 60..<80: colors = [Theme.amber, Theme.ember]
        default: colors = [Theme.ember, Theme.crimson]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
