import SwiftUI
import CoreLocation
import UIKit

// MARK: - Pin

struct KnockPinView: View {
    let house: KnockedHouse
    var emphasized: Bool = false
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            if emphasized {
                Circle()
                    .stroke(house.outcome.color.opacity(pulse ? 0 : 0.55), lineWidth: 2)
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.4 : 1)
            }
            Circle().fill(.white).frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle().fill(house.outcome.color).frame(width: 22, height: 22)
            Image(systemName: house.outcome.icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        }
        .onAppear {
            guard emphasized else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Knock Mode Overlay (tap-to-place)

struct KnockModeOverlay: View {
    @Bindable var store: KnockStore
    @Binding var editing: KnockedHouse?
    var emphasizedID: UUID?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Tap layer for placing new pins (under existing pins so taps on pins win)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        let nx = max(0.04, min(0.96, location.x / geo.size.width))
                        let ny = max(0.06, min(0.94, location.y / geo.size.height))
                        let h = store.add(at: CGPoint(x: nx, y: ny))
                        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                        editing = h
                    }

                ForEach(store.houses) { h in
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        editing = h
                    } label: {
                        KnockPinView(house: h, emphasized: h.id == emphasizedID)
                    }
                    .buttonStyle(.plain)
                    .position(x: h.x * geo.size.width,
                              y: h.y * geo.size.height)
                }
            }
        }
    }
}

// MARK: - Knock Outcome Sheet

struct KnockOutcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: KnockStore
    let houseID: UUID

    @State private var draftOutcome: KnockOutcome = .notKnocked
    @State private var draftNotes: String = ""
    @State private var showScripts: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    outcomePicker
                    notesField
                    scriptToggle
                    if showScripts {
                        ScriptAssistantPanel(outcome: draftOutcome)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    metadata
                    deleteRow
                    Color.clear.frame(height: 12)
                }
                .padding(18)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Knock Outcome")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Theme.ember, in: .capsule)
                    }
                }
            }
            .onAppear {
                if let h = store.houses.first(where: { $0.id == houseID }) {
                    draftOutcome = h.outcome
                    draftNotes = h.notes
                }
            }
        }
    }

    private var house: KnockedHouse? {
        store.houses.first { $0.id == houseID }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(draftOutcome.color.opacity(0.18))
                Image(systemName: draftOutcome.icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(draftOutcome.color)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(draftOutcome.rawValue.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(draftOutcome.color)
                Text(house?.prettyCoord ?? "GPS pending")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text(house.map { $0.loggedAt.formatted(date: .abbreviated, time: .shortened) } ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var outcomePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OUTCOME")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(KnockOutcome.allCases) { o in
                    Button {
                        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            draftOutcome = o
                        }
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(o.color)
                                Image(systemName: o.icon)
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 22, height: 22)
                            Text(o.rawValue)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(draftOutcome == o ? .white : Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if draftOutcome == o {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 10)
                        .background(
                            (draftOutcome == o ? AnyShapeStyle(o.color) : AnyShapeStyle(Theme.card)),
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(draftOutcome == o ? .clear : Theme.hairline, lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REP NOTES")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            TextEditor(text: $draftNotes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92)
                .padding(10)
                .background(Theme.card, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }

    private var scriptToggle: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                showScripts.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.amber.opacity(0.18))
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.amber)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Script Assistant")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(showScripts ? "Tap to hide" : "Tap to show what to say next")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Image(systemName: showScripts ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(12)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            metaTile(icon: "person.fill", label: "Rep",
                     value: house?.rep ?? "—")
            metaTile(icon: "clock.fill", label: "Logged",
                     value: house.map { $0.loggedAt.formatted(.relative(presentation: .numeric)) } ?? "now")
        }
    }

    private func metaTile(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.skySoft)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.sky)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.inkFaint)
                Text(value)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.card, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
    }

    private var deleteRow: some View {
        Button(role: .destructive) {
            store.remove(houseID)
            let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.warning)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Remove Pin")
            }
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.crimson)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.crimson.opacity(0.08), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard var h = house else { return }
        h.outcome = draftOutcome
        h.notes = draftNotes
        h.loggedAt = Date()
        store.update(h)
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
    }
}

// MARK: - Script Assistant

struct ScriptAssistantPanel: View {
    let outcome: KnockOutcome

    private var scripts: [String] {
        switch outcome {
        case .notKnocked, .noAnswer:
            return [
                "Hi! I'm with RoofWise — we noticed your block was hit hard by the April 18 storm. Have you had your roof checked since?",
                "We've already documented hail damage on \(neighborCount) homes nearby. I'd love to do a free 5-minute exterior look so you know where you stand before the claim window closes.",
                "Totally understand if now's not the time. Mind if I leave a card and circle back tomorrow afternoon?"
            ]
        case .interested:
            return [
                "Awesome — let's get you on the books. I have Thursday at 9am or Friday at 2pm. Which works?",
                "I'll need 30 minutes for the inspection. We document everything for your insurance carrier with photos and AI grading.",
                "Heads up — bring out your most recent insurance declarations page so I can ID your carrier and policy number on the spot."
            ]
        case .notInterested:
            return [
                "No worries at all — I appreciate your time. One quick thing: your neighbor at #\(randomHouseNo) had what looked like a sound roof and the carrier still totaled it. Would a no-cost photo log be worth 5 minutes?",
                "If you change your mind, save my number. Most carrier deadlines are 1 year from the storm date, so don't wait too long.",
                "Last thing — if a tarping crew shows up uninvited, do NOT sign anything. Call me first."
            ]
        case .scheduled:
            return [
                "You're booked. I'll text the day before with my ETA. Please clear gate access for me to walk the perimeter.",
                "If we find functional damage, I'll prep the supplement and you'll review before anything goes to the carrier.",
                "Confirm you'd like me to be present at the adjuster meeting. That's where claims get won or lost."
            ]
        }
    }

    private var neighborCount: Int { Int.random(in: 6...18) }
    private var randomHouseNo: Int { Int.random(in: 100...9000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(outcome.color.opacity(0.18))
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(outcome.color)
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("WHAT TO SAY · \(outcome.rawValue.uppercased())")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(outcome.color)
                    Text("Tap to copy a line")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
            }

            ForEach(Array(scripts.enumerated()), id: \.offset) { idx, line in
                Button {
                    UIPasteboard.general.string = line
                    let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(outcome.color, in: .circle)
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .padding(12)
                    .background(Theme.canvas, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Theme.amber.opacity(0.06), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.amber.opacity(0.3), lineWidth: 0.6))
    }
}

// MARK: - Knock Mode HUD (top + bottom)

struct KnockModeHUD: View {
    @Bindable var store: KnockStore
    @Binding var isOn: Bool
    @Binding var showScriptAssistant: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBanner
            Spacer()
            bottomBar
        }
    }

    private var topBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.ember.opacity(0.18))
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.ember)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("KNOCK MODE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(Theme.ember)
                Text("Tap a house to log · long-tap pin to edit")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { isOn = false }
            } label: {
                Text("Done")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.ember, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.ember.opacity(0.4), lineWidth: 1))
        .shadow(color: Theme.ember.opacity(0.2), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Outcome legend / counts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(KnockOutcome.allCases) { o in
                        outcomeChip(o)
                    }
                }
                .padding(.horizontal, 16)
            }

            Button {
                let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    showScriptAssistant.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.amber)
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Script Assistant")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                        Text(showScriptAssistant ? "Tap to hide quick lines" : "Door-knocking talk tracks · pick by outcome")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    Spacer()
                    Image(systemName: showScriptAssistant ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(12)
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
                .shadow(color: Theme.ink.opacity(0.10), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    private func outcomeChip(_ o: KnockOutcome) -> some View {
        HStack(spacing: 6) {
            Circle().fill(o.color).frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white, lineWidth: 1))
            Text(o.shortLabel)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text("\(store.count(of: o))")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(o.color)
                .monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(o.color.opacity(0.16), in: .capsule)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.5))
    }
}

// MARK: - Floating Script Sheet (overlays the bottom)

struct FloatingScriptCard: View {
    @Binding var outcome: KnockOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pick a knock outcome to see the right script")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(KnockOutcome.allCases) { o in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { outcome = o }
                            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: o.icon)
                                    .font(.system(size: 9, weight: .heavy))
                                Text(o.shortLabel)
                                    .font(.system(size: 10, weight: .heavy))
                            }
                            .foregroundStyle(outcome == o ? .white : Theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(
                                outcome == o ? AnyShapeStyle(o.color) : AnyShapeStyle(Theme.canvas),
                                in: .capsule
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ScriptAssistantPanel(outcome: outcome)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline, lineWidth: 0.6))
        .shadow(color: Theme.ink.opacity(0.12), radius: 18, y: 6)
        .padding(.horizontal, 16)
    }
}
