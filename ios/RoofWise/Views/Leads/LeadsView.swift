import SwiftUI

struct LeadsView: View {
    @Environment(CustomerStore.self) private var store
    @Binding var filter: JobPipelineStage?
    @State private var search: String = ""
    @State private var showNewCustomer = false

    init(filter: Binding<JobPipelineStage?> = .constant(nil)) {
        self._filter = filter
    }

    private var filtered: [Customer] {
        store.customers.filter { c in
            (filter == nil || c.stage == filter!) &&
            (search.isEmpty ||
             c.ownerName.localizedStandardContains(search) ||
             c.address.localizedStandardContains(search) ||
             c.policyNumber.localizedStandardContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerBar

                    searchBar

                    stageFilter

                    pipelineSummary

                    // Customer list
                    VStack(spacing: 10) {
                        ForEach(filtered) { customer in
                            NavigationLink(value: customer.id) {
                                CustomerCard(customer: customer,
                                             isActive: customer.id == store.activeCustomerID)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                store.setActive(customer.id)
                                ActivityStore.shared.logTap(target: "Leads.customerCard")
                            })
                        }
                        if filtered.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Theme.canvas)
            .navigationDestination(for: UUID.self) { id in
                CustomerProfileView(customerID: id)
            }
            .sheet(isPresented: $showNewCustomer) {
                NewCustomerSheet { newCustomer in
                    store.add(newCustomer, makeActive: true)
                    showNewCustomer = false
                } onCancel: {
                    showNewCustomer = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leads")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    let stormCount = store.customers.filter(\.stormTagged).count
                    Text("\(store.customers.count) active · \(stormCount) storm-tagged")
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
            }
            Button {
                ActivityStore.shared.logTap(target: "Leads.newCustomer")
                showNewCustomer = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                    Text("New Customer")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.18), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 28)
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            TextField("Search owner, address, policy #", text: $search)
                .font(.system(size: Theme.TypeRamp.body))
                .foregroundStyle(Theme.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            if !search.isEmpty {
                Button {
                    search = ""
                    ActivityStore.shared.logTap(target: "Leads.searchClear")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Theme.TypeRamp.body))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 20)
    }

    private var stageFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", active: filter == nil, color: Theme.ink) {
                    filter = nil
                    ActivityStore.shared.logTap(target: "Leads.filter.all")
                }
                ForEach(JobPipelineStage.allCases) { stage in
                    let count = store.customers.filter { $0.stage == stage }.count
                    FilterChip(label: "\(stage.shortLabel) · \(count)",
                               active: filter == stage,
                               color: stage.color) {
                        filter = stage
                        ActivityStore.shared.logTap(target: "Leads.filter.\(stage.shortLabel)")
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var pipelineSummary: some View {
        let stages = JobPipelineStage.allCases
        let counts = stages.map { stage in
            store.customers.filter { $0.stage == stage }.count
        }
        let total = max(counts.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("PIPELINE")
                .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkFaint)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stages.indices, id: \.self) { i in
                        let stage = stages[i]
                        let count = counts[i]
                        let width = geo.size.width * CGFloat(count) / CGFloat(total)
                        if count > 0 {
                            Button {
                                filter = stage
                                ActivityStore.shared.logTap(target: "Leads.pipelineSegment.\(stage.shortLabel)")
                            } label: {
                                Rectangle()
                                    .fill(stage.color)
                                    .frame(width: max(width, 12))
                                    .overlay(
                                        Text("\(count)")
                                            .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                                            .foregroundStyle(.white)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: Theme.TypeRamp.display))
                .foregroundStyle(Theme.inkFaint)
            Text("No customers match")
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text("Adjust filters or add a new customer.")
                .font(.system(size: Theme.TypeRamp.metaSm))
                .foregroundStyle(Theme.inkFaint)
            Button {
                ActivityStore.shared.logTap(target: "Leads.emptyState.newCustomer")
                showNewCustomer = true
            } label: {
                Text("Add a customer")
                    .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let active: Bool
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(minHeight: 56)
                .background(active ? color : Theme.card, in: .capsule)
                .overlay(Capsule().stroke(active ? Color.clear : Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Customer Card

private struct CustomerCard: View {
    let customer: Customer
    let isActive: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(customer.stage.color.opacity(0.14))
                Text(customer.initials)
                    .font(.system(size: Theme.TypeRamp.meta, weight: .heavy))
                    .foregroundStyle(customer.stage.color)
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: .bottomTrailing) {
                if isActive {
                    Circle().fill(Theme.ember)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(customer.ownerName)
                        .font(.system(size: Theme.TypeRamp.body, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if customer.stormTagged {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: Theme.TypeRamp.microSm, weight: .bold))
                            .foregroundStyle(Theme.ember)
                    }
                }
                Text(customer.address)
                    .font(.system(size: Theme.TypeRamp.metaSm))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: customer.stage.icon)
                            .font(.system(size: Theme.TypeRamp.microSm, weight: .bold))
                        Text(customer.stage.shortLabel.uppercased())
                            .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                            .tracking(0.4)
                    }
                    .foregroundStyle(customer.stage.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(customer.stage.color.opacity(0.12), in: .capsule)

                    if !customer.estimatedValue.isEmpty {
                        Text(customer.estimatedValue)
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if !customer.photos.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: Theme.TypeRamp.microSm, weight: .bold))
                        Text("\(customer.photos.count)")
                            .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                    }
                    .foregroundStyle(Theme.inkSoft)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.TypeRamp.metaSm, weight: .bold))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(
            isActive ? Theme.ember.opacity(0.35) : Theme.hairline,
            lineWidth: isActive ? 1.2 : 0.6))
        .shadow(color: Theme.ink.opacity(0.04), radius: 8, y: 3)
    }
}

// MARK: - New Customer Sheet

private struct NewCustomerSheet: View {
    @State private var name = ""
    @State private var address = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var insurance = ""
    @State private var policy = ""
    @State private var stage: JobPipelineStage = .knocked
    @State private var stormTagged = false
    @State private var showDiscardConfirm = false

    let onSave: (Customer) -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasEdits: Bool {
        !name.isEmpty || !address.isEmpty || !phone.isEmpty || !email.isEmpty ||
        !insurance.isEmpty || !policy.isEmpty || stormTagged || stage != .knocked
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Initial Stage")
                            .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(Theme.inkFaint)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(JobPipelineStage.allCases) { s in
                                    Button {
                                        stage = s
                                        ActivityStore.shared.logTap(target: "NewCustomerSheet.stage.\(s.shortLabel)")
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: s.icon)
                                                .font(.system(size: Theme.TypeRamp.metaSm, weight: .bold))
                                            Text(s.shortLabel)
                                                .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                                        }
                                        .foregroundStyle(stage == s ? .white : s.color)
                                        .padding(.horizontal, 18).padding(.vertical, 12)
                                        .frame(minHeight: 56)
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
                            .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.ember)
                    .padding(14)
                    .frame(minHeight: 56)
                    .background(Theme.card, in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))

                    saveButton
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .navigationTitle("New Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if hasEdits {
                            showDiscardConfirm = true
                        } else {
                            onCancel()
                        }
                    }
                    .foregroundStyle(Theme.inkSoft)
                }
            }
            .confirmationDialog(
                "Discard this customer? You have unsaved changes.",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    ActivityStore.shared.logTap(target: "NewCustomerSheet.discard")
                    onCancel()
                }
                Button("Keep editing", role: .cancel) { }
            }
        }
    }

    private var saveButton: some View {
        Button {
            ActivityStore.shared.logTap(target: "NewCustomerSheet.save")
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
            Text("Save Customer")
                .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(canSave ? AnyShapeStyle(Theme.inkGradient) : AnyShapeStyle(Theme.inkFaint),
                            in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(canSave ? 0.18 : 0), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    private func field(_ label: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.inkFaint)
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: Theme.TypeRamp.body, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 28)
                TextField(label, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                    .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .phonePad)
                    .font(.system(size: Theme.TypeRamp.body))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
    }
}
