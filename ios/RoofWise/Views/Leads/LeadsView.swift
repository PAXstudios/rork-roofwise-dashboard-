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
                            })
                        }
                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Theme.inkFaint)
                                Text("No customers match")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                                Text("Adjust filters or add a new customer.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Leads")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                let stormCount = store.customers.filter(\.stormTagged).count
                Text("\(store.customers.count) active · \(stormCount) storm-tagged")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Button { showNewCustomer = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .heavy))
                    Text("New")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(LinearGradient(colors: [Theme.ember, Theme.emberDeep],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: .capsule)
                .shadow(color: Theme.ember.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                TextField("Search owner, address, policy #", text: $search)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Theme.card, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        }
        .padding(.horizontal, 20)
    }

    private var stageFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", active: filter == nil, color: Theme.ink) { filter = nil }
                ForEach(JobPipelineStage.allCases) { stage in
                    let count = store.customers.filter { $0.stage == stage }.count
                    FilterChip(label: "\(stage.shortLabel) · \(count)",
                               active: filter == stage,
                               color: stage.color) { filter = stage }
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
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.inkFaint)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stages.indices, id: \.self) { i in
                        let stage = stages[i]
                        let count = counts[i]
                        let width = geo.size.width * CGFloat(count) / CGFloat(total)
                        if count > 0 {
                            Rectangle()
                                .fill(stage.color)
                                .frame(width: max(width, 12))
                                .overlay(
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 20)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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
                    .font(.system(size: 14, weight: .heavy))
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if customer.stormTagged {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.ember)
                    }
                }
                Text(customer.address)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: customer.stage.icon)
                            .font(.system(size: 8, weight: .bold))
                        Text(customer.stage.shortLabel.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.4)
                    }
                    .foregroundStyle(customer.stage.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(customer.stage.color.opacity(0.12), in: .capsule)

                    if !customer.estimatedValue.isEmpty {
                        Text(customer.estimatedValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if !customer.photos.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(customer.photos.count)")
                            .font(.system(size: 11, weight: .heavy))
                    }
                    .foregroundStyle(Theme.inkSoft)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
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
                        Text("Save")
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
