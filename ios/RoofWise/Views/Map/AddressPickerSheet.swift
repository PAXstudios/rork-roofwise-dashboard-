import SwiftUI

/// Reusable Address Picker. Used by the Map tab search field today and
/// will be reused by the Phase 4E Cost Estimator. Driven by `MapsService`.
struct AddressPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let service: MapsService
    var onPick: (AddressSuggestion) -> Void

    @State private var query: String = ""
    @State private var results: [AddressSuggestion] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            queryField
            list
        }
        .background(Theme.canvas)
        .task { await refresh() }
        .onChange(of: query) { _, _ in
            Task { await refresh() }
        }
    }

    private var header: some View {
        HStack {
            Text("Pick an address")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Cancel") { dismiss() }
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var queryField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                .foregroundStyle(Theme.inkFaint)
            TextField("Street, city, ZIP…", text: $query)
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }
            Button {
                // Mic affordance — placeholder for future Speech integration.
                // Kept visual only for now; not a stub the user can mistakenly tap.
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
        .padding(.bottom, 16)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var list: some View {
        if results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                Text("No matches yet")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Text("Try a street, city, or ZIP")
                    .font(.system(size: Theme.TypeRamp.metaSm))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results) { row(for: $0) }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func row(for s: AddressSuggestion) -> some View {
        Button {
            let g = UISelectionFeedbackGenerator(); g.selectionChanged()
            onPick(s)
            dismiss()
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
                    Text(s.subtitle)
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .frame(minHeight: 64)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        let r = await service.suggestAddresses(query: query)
        await MainActor.run { self.results = r }
    }
}
