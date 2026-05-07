import SwiftUI

struct ServiceAreaView: View {
    @State private var store = ServiceAreaStore.shared
    @State private var query: String = ""
    @State private var errorMessage: String? = nil
    @State private var pendingDelete: ServiceArea? = nil
    @State private var showRationale: Bool = false
    @FocusState private var focused: Bool

    private let didAskNotificationsKey = "rw.notifications.didAsk"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                inputCard

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                        .foregroundStyle(Theme.crimson)
                        .padding(.horizontal, 4)
                }

                pushSettingsLink

                if store.areas.isEmpty {
                    emptyState
                } else {
                    Text("SAVED AREAS")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 4)

                    VStack(spacing: 12) {
                        ForEach(store.areas) { area in
                            row(for: area)
                        }
                    }
                }

                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Service Area")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            pendingDelete.map { "Remove \($0.label)?" } ?? "Remove area?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pendingDelete { store.remove(id: pendingDelete.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .sheet(isPresented: $showRationale) {
            NotificationsRationaleView()
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Service Area")
                .font(.system(size: Theme.TypeRamp.title, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Storms in these areas trigger alerts.")
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
                TextField("ZIP (75024) or City ST", text: $query)
                    .font(.system(size: Theme.TypeRamp.body))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit { addCurrent() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    // Mic affordance — visual stub matching AddressPickerSheet.
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
            .frame(minHeight: 64)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))

            Button(action: addCurrent) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("Add to my service area")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }

    private func addCurrent() {
        guard let area = ServiceArea.parse(query) else {
            errorMessage = "Enter a 5-digit ZIP or 'City ST' (e.g. Plano TX)."
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let wasEmpty = store.areas.isEmpty
        store.add(area)
        query = ""
        errorMessage = nil
        focused = false
        // First-area transition (0 -> 1): present the notifications rationale
        // sheet exactly once per install.
        if wasEmpty && !store.areas.isEmpty {
            let didAsk = UserDefaults.standard.bool(forKey: didAskNotificationsKey)
            if !didAsk {
                UserDefaults.standard.set(true, forKey: didAskNotificationsKey)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showRationale = true
                }
            }
        }
    }

    // MARK: - Push settings link

    private var pushSettingsLink: some View {
        NavigationLink(value: DashboardRoute.pushSettings) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.emberSoft)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        .foregroundStyle(Theme.ember)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Push alerts, sound, snooze duration")
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.amberSoft)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.amber)
            }
            .frame(width: 64, height: 64)
            Text("No service area yet")
                .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Add at least one ZIP or city to start receiving storm alerts.")
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 22, radius: 22)
    }

    // MARK: - Row

    private func row(for area: ServiceArea) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.skySoft)
                Image(systemName: area.kind == .zip ? "number" : "building.2.fill")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.sky)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(area.label)
                    .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    Text(area.kind == .zip ? "ZIP" : "CITY")
                        .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.canvas, in: .rect(cornerRadius: 8))
                    Text(area.addedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 8)

            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                pendingDelete = area
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                    .foregroundStyle(Theme.crimson)
                    .frame(width: 56, height: 56)
                    .background(Theme.crimson.opacity(0.10), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = area
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

#Preview {
    NavigationStack { ServiceAreaView() }
}
