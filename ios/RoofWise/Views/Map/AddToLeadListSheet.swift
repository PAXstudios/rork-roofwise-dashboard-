import SwiftUI

// MARK: - Add to Lead List (Step 6)
//
// There's no home-density data source wired in, so "Add to Lead List" is an
// honest manual flow: the inspector searches real addresses (Places autocomplete
// via MapsService) or types one in, stacks up the homes hit by this storm, then
// commits them as fresh storm-tagged leads. No fabricated addresses.

struct AddToLeadListSheet: View {
    @Environment(\.dismiss) private var dismiss

    let service: MapsService
    let stormHeadline: String
    var onAdd: ([AddressSuggestion]) -> Void

    @State private var query: String = ""
    @State private var results: [AddressSuggestion] = []
    @State private var pending: [AddressSuggestion] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !pending.isEmpty { pendingSection }
                    suggestionsSection
                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 20)
            }
            if !pending.isEmpty { commitBar }
        }
        .background(Theme.canvas)
        .task { await refresh() }
        .onChange(of: query) { _, _ in Task { await refresh() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add to Lead List")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Homes hit by \(stormHeadline)")
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                .foregroundStyle(Theme.inkFaint)
            TextField("Street, city, ZIP…", text: $query)
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .onSubmit { addTyped() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }
            Button {
                // Focus the field so the keyboard's built-in dictation (mic key)
                // is available for hands-free address entry.
                focused = true
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.ink, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: Pending

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(pending.count) HOME\(pending.count == 1 ? "" : "S") TO ADD")
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
            ForEach(pending) { s in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.ember.opacity(0.14))
                        Image(systemName: "house.fill")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                            .foregroundStyle(Theme.ember)
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title)
                            .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if !s.subtitle.isEmpty {
                            Text(s.subtitle)
                                .font(.system(size: Theme.TypeRamp.caption))
                                .foregroundStyle(Theme.inkSoft)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        pending.removeAll { $0.id == s.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                            .foregroundStyle(Theme.crimson)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .frame(minHeight: 56)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
            }
        }
    }

    // MARK: Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !results.isEmpty {
                    ForEach(results) { suggestionRow($0) }
                }
                typedRow
            }
        } else if pending.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                Text("Search or type the addresses you canvassed")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
        }
    }

    private func suggestionRow(_ s: AddressSuggestion) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            addPending(s)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.skySoft)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(Theme.sky)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(s.subtitle)
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: pending.contains(where: { $0.fullAddress == s.fullAddress })
                      ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                    .foregroundStyle(pending.contains(where: { $0.fullAddress == s.fullAddress }) ? Theme.mint : Theme.ember)
            }
            .padding(14)
            .frame(minHeight: 64)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var typedRow: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !results.contains(where: { $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            Button {
                addTyped()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.ink.opacity(0.08))
                        Image(systemName: "pencil.and.scribble")
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(width: 40, height: 40)
                    Text("Add “\(trimmed)”")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .padding(14)
                .frame(minHeight: 64)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Commit

    private var commitBar: some View {
        VStack(spacing: 0) {
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onAdd(pending)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("Add \(pending.count) lead\(pending.count == 1 ? "" : "s")")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    // MARK: Actions

    private func addPending(_ s: AddressSuggestion) {
        guard !pending.contains(where: { $0.fullAddress == s.fullAddress }) else { return }
        pending.append(s)
        query = ""
    }

    private func addTyped() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let suggestion = AddressSuggestion(title: trimmed, subtitle: "", latitude: 0, longitude: 0)
        addPending(suggestion)
    }

    private func refresh() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            await MainActor.run { results = [] }
            return
        }
        let r = await service.suggestAddresses(query: trimmed)
        await MainActor.run { results = r }
    }
}
