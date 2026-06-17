import SwiftUI

// MARK: - Insurance carrier catalog
//
// Major + mid-tier US property carriers the inspector can attribute a claim to.
// Surfaced through `CarrierPickerField` as a searchable dropdown so the user
// isn't limited to a handful of chips. "Other" lets them type anything not listed.

enum InsuranceCarriers {
    /// Alphabetical-ish, majors first then mid-tier. "Other" is appended by the picker.
    static let all: [String] = [
        // Majors
        "State Farm", "Allstate", "Liberty Mutual", "Farmers", "USAA",
        "Travelers", "Nationwide", "Progressive", "American Family", "Erie",
        // Mid-tier / regional
        "Chubb", "Auto-Owners", "Cincinnati Insurance", "The Hartford", "Safeco",
        "MetLife", "Mercury", "Amica", "Kemper", "The Hanover",
        "Selective", "Westfield", "Grange", "Shelter", "Country Financial",
        "AAA / Auto Club", "Foremost", "Homesite", "Lemonade", "Hippo",
        "Openly", "NJM", "Plymouth Rock", "MAPFRE", "Acuity",
        "Frankenmuth", "Encompass", "Pure", "Universal Property",
        "Texas Farm Bureau", "Germania", "Heritage", "Citizens"
    ]
}

// MARK: - CarrierPickerField

/// Big tappable field that opens a searchable carrier list. Writes the chosen
/// carrier name into `carrier`. Matches the New Job wizard field styling
/// (56pt target, Theme.card surface, hairline stroke).
struct CarrierPickerField: View {
    var label: String = "Carrier"
    @Binding var carrier: String

    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.inkSoft)
                .tracking(0.6)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .frame(width: 26)
                    Text(carrier.isEmpty ? "Select carrier" : carrier)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(carrier.isEmpty ? Theme.inkFaint : Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.card, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) {
            CarrierPickerSheet(carrier: $carrier)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - CarrierPickerSheet

private struct CarrierPickerSheet: View {
    @Binding var carrier: String
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var otherText: String = ""
    @FocusState private var otherFocused: Bool

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return InsuranceCarriers.all }
        return InsuranceCarriers.all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(matches, id: \.self) { name in
                            carrierRow(name)
                        }
                        otherRow
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Insurance Carrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            TextField("Search carriers", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func carrierRow(_ name: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            carrier = name
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 6)
                if carrier == name {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.ember)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(carrier == name ? Theme.emberSoft : Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(carrier == name ? Theme.ember.opacity(0.4) : Theme.hairline, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private var otherRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.sky)
                Text("Other carrier")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            HStack(spacing: 10) {
                TextField("Type carrier name", text: $otherText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($otherFocused)
                    .submitLabel(.done)
                    .onSubmit { commitOther() }
                Button {
                    commitOther()
                } label: {
                    Text("Use")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(otherText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? AnyShapeStyle(Theme.inkFaint) : AnyShapeStyle(Theme.ember),
                                    in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(otherText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.canvas, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.top, 8)
    }

    private func commitOther() {
        let trimmed = otherText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        carrier = trimmed
        dismiss()
    }
}
