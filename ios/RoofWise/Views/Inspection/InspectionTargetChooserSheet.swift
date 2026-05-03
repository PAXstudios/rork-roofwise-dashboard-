import SwiftUI

/// Lets the user decide where photos from a fresh inspection should land:
/// continue with the active customer, pick an existing one, or create a new one.
struct InspectionTargetChooserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CustomerStore.self) private var store

    var onProceed: () -> Void

    @State private var showNewCustomer = false
    @State private var showExistingPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let active = store.activeCustomer {
                        optionCard(
                            icon: "person.crop.circle.badge.checkmark",
                            tint: Theme.ember,
                            title: "Continue with \(active.ownerName)",
                            subtitle: "Photos attach to this active customer.",
                            badge: "ACTIVE"
                        ) {
                            onProceed()
                            dismiss()
                        }
                    }

                    optionCard(
                        icon: "person.crop.circle.badge.plus",
                        tint: Theme.sky,
                        title: "New Customer",
                        subtitle: "Create a customer profile, then capture photos.",
                        badge: nil
                    ) {
                        showNewCustomer = true
                    }

                    optionCard(
                        icon: "person.2.fill",
                        tint: Theme.mint,
                        title: "Existing Customer",
                        subtitle: "Add photos to a customer already in your pipeline.",
                        badge: "\(store.customers.count)"
                    ) {
                        showExistingPicker = true
                    }

                    optionCard(
                        icon: "tray.and.arrow.down.fill",
                        tint: Theme.amber,
                        title: "Save Without Customer",
                        subtitle: "Capture now, attach a property later.",
                        badge: "LATER"
                    ) {
                        store.createUnassignedDraft()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(120))
                            onProceed()
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .sheet(isPresented: $showNewCustomer) {
            InspectionNewCustomerSheet { newCustomer in
                store.add(newCustomer, makeActive: true)
                showNewCustomer = false
                // Defer so the inner sheet finishes dismissing before we close & proceed.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(280))
                    onProceed()
                    dismiss()
                }
            } onCancel: {
                showNewCustomer = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showExistingPicker) {
            InspectionCustomerPickerSheet(store: store) { picked in
                store.setActive(picked.id)
                showExistingPicker = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(280))
                    onProceed()
                    dismiss()
                }
            } onCancel: {
                showExistingPicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add Photos To…")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Choose where this inspection's photos and findings should be saved.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: Option Card

    private func optionCard(icon: String,
                            tint: Color,
                            title: String,
                            subtitle: String,
                            badge: String?,
                            action: @escaping () -> Void) -> some View {
        Button {
            let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(tint.opacity(0.14))
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.5)
                                .foregroundStyle(tint)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(tint.opacity(0.14), in: .capsule)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 0.6))
            .shadow(color: Theme.ink.opacity(0.04), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Customer Sheet (mirrors LeadsView's, exposed here for reuse)

private struct InspectionNewCustomerSheet: View {
    @State private var name = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var insurance = ""
    @State private var policy = ""
    @State private var stage: JobPipelineStage = .inspectionScheduled
    @State private var stormTagged = true

    let onSave: (Customer) -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Owner Name *", text: $name)
                    field("Address *", text: $address)
                    field("Phone", text: $phone, keyboard: .phonePad)
                    field("Email", text: $email, keyboard: .emailAddress)
                    field("Insurance Company", text: $insurance)
                    field("Policy Number", text: $policy)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Initial Stage")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(Theme.inkFaint)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(JobPipelineStage.allCases) { s in
                                    Button { stage = s } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: s.icon)
                                                .font(.system(size: 9, weight: .bold))
                                            Text(s.shortLabel)
                                                .font(.system(size: 11, weight: .heavy))
                                        }
                                        .foregroundStyle(stage == s ? .white : s.color)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(stage == s ? s.color : s.color.opacity(0.12),
                                                    in: .capsule)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .contentMargins(.horizontal, 0)
                    }

                    Toggle(isOn: $stormTagged) {
                        Label("Storm-tagged lead", systemImage: "bolt.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.ember)
                    .padding(12)
                    .background(Theme.card, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("New Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(Theme.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let c = Customer(
                            ownerName: name,
                            address: address,
                            phone: phone,
                            email: email,
                            insuranceCompany: insurance,
                            policyNumber: policy,
                            stage: stage,
                            stormTagged: stormTagged
                        )
                        onSave(c)
                    } label: {
                        Text("Save & Continue")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(canSave ? Theme.ember : Theme.inkFaint)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.inkFaint)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .phonePad)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .padding(12)
                .background(Theme.card, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }
}

// MARK: - Existing Customer Picker Sheet

private struct InspectionCustomerPickerSheet: View {
    let store: CustomerStore
    var onPick: (Customer) -> Void
    var onCancel: () -> Void

    @State private var query: String = ""

    private var filtered: [Customer] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.customers }
        return store.customers.filter {
            $0.ownerName.lowercased().contains(q) ||
            $0.address.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick an Existing Customer")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Photos and findings from this inspection will attach here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                    TextField("Search by name or address", text: $query)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.words)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.canvas, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 0.6))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { c in
                            Button { onPick(c) } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(c.stage.color.opacity(0.18))
                                        Text(c.initials)
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(c.stage.color)
                                    }
                                    .frame(width: 38, height: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.ownerName)
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                        Text(c.address)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.inkSoft)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                    if !c.photos.isEmpty {
                                        HStack(spacing: 3) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 9, weight: .bold))
                                            Text("\(c.photos.count)")
                                                .font(.system(size: 11, weight: .heavy))
                                        }
                                        .foregroundStyle(Theme.inkSoft)
                                    }
                                    Text(c.stage.shortLabel)
                                        .font(.system(size: 9, weight: .heavy))
                                        .tracking(0.4)
                                        .foregroundStyle(c.stage.color)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(c.stage.color.opacity(0.14), in: .capsule)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card, in: .rect(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(Theme.hairline, lineWidth: 0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        if filtered.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Theme.inkFaint)
                                Text("No matches")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }
}
