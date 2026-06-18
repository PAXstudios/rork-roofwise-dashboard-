import SwiftUI

struct LeadsView: View {
    @Environment(CustomerStore.self) private var store
    @Binding var filter: JobPipelineStage?
    @State private var search: String = ""
    @State private var showNewJob = false
    @State private var sync = LeadsSyncService.shared
    @State private var kind: PipelineKind = .lead
    @State private var stageFilter: JobPipelineStage? = nil

    init(filter: Binding<JobPipelineStage?> = .constant(nil)) {
        self._filter = filter
    }

    // MARK: Derived data

    private var bucket: [Customer] {
        store.customers.filter { $0.stage.kind == kind }
    }

    private var filtered: [Customer] {
        bucket
            .filter { c in
                (stageFilter == nil || c.stage == stageFilter!) &&
                (search.isEmpty ||
                 c.ownerName.localizedStandardContains(search) ||
                 c.address.localizedStandardContains(search) ||
                 c.policyNumber.localizedStandardContains(search))
            }
            .sorted { $0.stage.stepIndex > $1.stage.stepIndex }
    }

    private var leadCount: Int { store.customers.filter { $0.stage.kind == .lead }.count }
    private var jobCount: Int { store.customers.filter { $0.stage.kind == .job }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerBar
                        .onChange(of: store.customers.count) { _, _ in sync.noteLocalChange() }

                    segmentedToggle

                    searchBar

                    stageFilterRow

                    bucketSummary

                    list
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Theme.canvas)
            .refreshable { await sync.syncNow() }
            .navigationDestination(for: UUID.self) { id in
                CustomerProfileView(customerID: id)
            }
            .fullScreenCover(isPresented: $showNewJob) {
                NewJobWizard()
            }
        }
        .onAppear { consumeDeepLink() }
        .onChange(of: filter) { _, _ in consumeDeepLink() }
    }

    /// A deep-link from the dashboard (`onOpenLeadsStage`) arrives as a one-shot
    /// stage on the `filter` binding. Select the right bucket + stage, then clear
    /// the binding so manual taps aren't overridden on the next render.
    private func consumeDeepLink() {
        guard let f = filter else { return }
        withAnimation(Theme.Motion.standard) {
            kind = f.kind
            stageFilter = f
        }
        DispatchQueue.main.async { filter = nil }
    }

    private func selectKind(_ k: PipelineKind) {
        guard k != kind else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(Theme.Motion.standard) {
            kind = k
            stageFilter = nil
        }
    }

    // MARK: Sync badge

    @ViewBuilder
    private var syncBadge: some View {
        switch sync.status {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.65).tint(Theme.sky)
                Text("Syncing…")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
                    .foregroundStyle(Theme.sky)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.skySoft, in: .capsule)
        case .synced(let at):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("Synced \(at.formatted(.relative(presentation: .numeric)))")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            }
            .foregroundStyle(Theme.mint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.mintSoft, in: .capsule)
        case .failed:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 11, weight: .heavy))
                Text("Sync failed")
                    .font(.system(size: Theme.TypeRamp.captionSm, weight: .heavy))
            }
            .foregroundStyle(Theme.crimson)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.crimson.opacity(0.10), in: .capsule)
        }
    }

    // MARK: Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pipeline")
                        .font(.system(size: Theme.TypeRamp.display, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    let stormCount = store.customers.filter(\.stormTagged).count
                    Text("\(leadCount) leads · \(jobCount) jobs · \(stormCount) storm-tagged")
                        .font(.system(size: Theme.TypeRamp.metaSm))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                syncBadge
            }
            Button {
                ActivityStore.shared.logTap(target: "Leads.newLead")
                showNewJob = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: Theme.TypeRamp.bodyTight, weight: .heavy))
                    Text("New Lead")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                .shadow(color: Theme.ink.opacity(0.16), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Leads / Jobs segmented toggle

    private var segmentedToggle: some View {
        HStack(spacing: 6) {
            ForEach(PipelineKind.allCases) { k in
                let selected = kind == k
                let count = k == .lead ? leadCount : jobCount
                Button { selectKind(k) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: k.icon)
                            .font(.system(size: 13, weight: .heavy))
                        Text(k.title)
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                        Text("\(count)")
                            .font(.system(size: Theme.TypeRamp.caption, weight: .heavy))
                            .foregroundStyle(selected ? .white : Theme.inkSoft)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(selected ? Color.white.opacity(0.22) : Theme.canvas,
                                        in: .capsule)
                    }
                    .foregroundStyle(selected ? .white : Theme.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if selected {
                            Capsule().fill(
                                LinearGradient(colors: [k.accent, k.accent.opacity(0.82)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 20)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.TypeRamp.subhead, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            TextField("Search owner, address, policy #", text: $search)
                .font(.system(size: Theme.TypeRamp.meta))
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
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Theme.card, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 20)
    }

    private var stageFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", active: stageFilter == nil, color: kind.accent) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(Theme.Motion.snappy) { stageFilter = nil }
                    ActivityStore.shared.logTap(target: "Leads.filter.all")
                }
                ForEach(JobPipelineStage.stages(for: kind)) { stage in
                    let count = bucket.filter { $0.stage == stage }.count
                    FilterChip(label: "\(stage.shortLabel) · \(count)",
                               active: stageFilter == stage,
                               color: stage.color) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(Theme.Motion.snappy) { stageFilter = stage }
                        ActivityStore.shared.logTap(target: "Leads.filter.\(stage.shortLabel)")
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Bucket summary (funnel for leads, booked value for jobs)

    @ViewBuilder
    private var bucketSummary: some View {
        if kind == .lead {
            leadFunnel
        } else {
            jobsValueStrip
        }
    }

    private var leadFunnel: some View {
        let stages = JobPipelineStage.stages(for: .lead)
        let counts = stages.map { stage in bucket.filter { $0.stage == stage }.count }
        let total = max(counts.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("LEAD FUNNEL")
                .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(Theme.inkFaint)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(stages.indices, id: \.self) { i in
                        let stage = stages[i]
                        let count = counts[i]
                        if count > 0 {
                            let width = geo.size.width * CGFloat(count) / CGFloat(total)
                            Button {
                                withAnimation(Theme.Motion.snappy) { stageFilter = stage }
                            } label: {
                                Rectangle()
                                    .fill(stage.color)
                                    .frame(width: max(width, 14))
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

    private var jobsValueStrip: some View {
        let jobs = bucket
        let lows = jobs.compactMap(\.estimateLow)
        let highs = jobs.compactMap(\.estimateHigh)
        let sumLow = lows.reduce(0, +)
        let sumHigh = highs.reduce(0, +)
        let hasValue = sumHigh > 0
        return HStack(spacing: 12) {
            statBlock(value: "\(jobs.count)",
                      label: "ACTIVE JOBS",
                      icon: "hammer.fill",
                      tint: Theme.mint)
            Rectangle().fill(Theme.hairline).frame(width: 0.6, height: 36)
            statBlock(value: hasValue
                        ? RoofEstimateService.compactRange(low: sumLow, high: sumHigh)
                        : "—",
                      label: "BOOKED VALUE",
                      icon: "dollarsign.circle.fill",
                      tint: Theme.ember)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 0.6))
        .padding(.horizontal, 20)
    }

    private func statBlock(value: String, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: Theme.TypeRamp.titleSm, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: Theme.TypeRamp.micro, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 10) {
                ForEach(filtered) { customer in
                    NavigationLink(value: customer.id) {
                        Group {
                            if kind == .job {
                                JobCard(customer: customer,
                                        isActive: customer.id == store.activeCustomerID)
                            } else {
                                LeadCard(customer: customer,
                                         isActive: customer.id == store.activeCustomerID)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        store.setActive(customer.id)
                        ActivityStore.shared.logTap(target: "Leads.\(kind.rawValue)Card")
                    })
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: kind == .job ? "hammer" : "person.crop.circle.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(Theme.inkFaint)
            Text(kind == .job ? "No jobs yet" : "No leads match")
                .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(kind == .job
                 ? "Jobs appear here once a lead is approved."
                 : "Knock a door or add a lead to get started.")
                .font(.system(size: Theme.TypeRamp.metaSm))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
            if kind == .lead {
                Button {
                    ActivityStore.shared.logTap(target: "Leads.emptyState.newLead")
                    showNewJob = true
                } label: {
                    Text("Add a lead")
                        .font(.system(size: Theme.TypeRamp.cta, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Theme.inkGradient, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
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
                .font(.system(size: Theme.TypeRamp.metaSm, weight: .heavy))
                .foregroundStyle(active ? .white : Theme.inkSoft)
                .padding(.horizontal, 14)
                .frame(minHeight: 38)
                .background(active ? color : Theme.card, in: .capsule)
                .overlay(Capsule().stroke(active ? Color.clear : Theme.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lead Card

private struct LeadCard: View {
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
                    stageChip(customer.stage)
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
    }
}

// MARK: - Job Card

/// Distinct treatment for booked work: mint accent, a stage progress rail
/// across the four job stages, and prominent estimated value.
private struct JobCard: View {
    let customer: Customer
    let isActive: Bool

    private let jobStages = JobPipelineStage.stages(for: .job)
    private var currentIndex: Int { jobStages.firstIndex(of: customer.stage) ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(Theme.mintSoft)
                    Image(systemName: customer.stage.icon)
                        .font(.system(size: Theme.TypeRamp.body, weight: .heavy))
                        .foregroundStyle(customer.stage.color)
                }
                .frame(width: 46, height: 46)
                .overlay(alignment: .bottomTrailing) {
                    if isActive {
                        Circle().fill(Theme.ember)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
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
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    if !customer.estimatedValue.isEmpty {
                        Text(customer.estimatedValue)
                            .font(.system(size: Theme.TypeRamp.subhead, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text("VALUE")
                        .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.inkFaint)
                }
            }

            // Stage progress rail
            HStack(spacing: 4) {
                ForEach(jobStages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentIndex ? Theme.mint : Theme.hairline)
                        .frame(height: 5)
                }
            }

            HStack(spacing: 6) {
                stageChip(customer.stage)
                Spacer()
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
    }
}

// MARK: - Shared stage chip

private func stageChip(_ stage: JobPipelineStage) -> some View {
    HStack(spacing: 4) {
        Image(systemName: stage.icon)
            .font(.system(size: Theme.TypeRamp.microSm, weight: .bold))
        Text(stage.shortLabel.uppercased())
            .font(.system(size: Theme.TypeRamp.microSm, weight: .heavy))
            .tracking(0.4)
    }
    .foregroundStyle(stage.color)
    .padding(.horizontal, 8).padding(.vertical, 4)
    .background(stage.color.opacity(0.12), in: .capsule)
}
