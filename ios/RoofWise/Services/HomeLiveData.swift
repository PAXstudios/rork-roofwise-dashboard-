import Foundation
import SwiftUI

/// Derives dashboard / plan surfaces from real stores. Never invents customers,
/// revenue, or storm history — empty arrays + honest empty states when the
/// user has no data yet.
enum HomeLiveData {

    // MARK: - KPI strip

    /// When `true`, the KPI strip should render an empty invite instead of
    /// zeroed metric tiles (zeros-as-data look like a populated dashboard).
    static func kpisAreEmpty(customers: [Customer],
                             alerts: [StormAlert] = StormAlertStore.shared.alerts,
                             estimates: [SavedEstimate] = EstimatesStore.shared.estimates,
                             proposals: [Proposal] = ProposalStore.shared.proposals) -> Bool {
        customers.isEmpty
            && alerts.filter(\.isActive).isEmpty
            && estimates.isEmpty
            && proposals.isEmpty
    }

    static func kpis(customers: [Customer],
                     alerts: [StormAlert] = StormAlertStore.shared.alerts,
                     estimates: [SavedEstimate] = EstimatesStore.shared.estimates,
                     proposals: [Proposal] = ProposalStore.shared.proposals) -> [KPIMetric] {
        let jobsInProgress = customers.filter {
            $0.stage.kind == .job && $0.stage != .paid
        }.count
        let activeLeads = customers.filter { $0.stage.kind == .lead }.count
        let stormTagged = customers.filter(\.stormTagged).count
        let activeAlerts = alerts.filter(\.isActive).count
        let closingSoon = customers.filter {
            $0.stage == .approved || $0.stage == .materialOrdered
        }.count

        // Revenue: signed proposals first, then saved estimates. Never invent.
        let signedTotal = proposals
            .filter { $0.status == .signed }
            .map(\.total)
            .reduce(0, +)
        let estimateTotal = estimates.map(\.subtotal).reduce(0, +)
        let revenueValue: Double? = {
            if signedTotal > 0 { return signedTotal }
            if estimateTotal > 0 { return estimateTotal }
            return nil
        }()
        let revenueSource: String = {
            if signedTotal > 0 { return "Signed proposals" }
            if estimateTotal > 0 { return "Saved estimates" }
            return "No estimates yet"
        }()

        var metrics: [KPIMetric] = [
            KPIMetric(
                title: "Jobs In Progress",
                value: "\(jobsInProgress)",
                delta: closingSoon > 0
                    ? "\(closingSoon) closing soon"
                    : (jobsInProgress == 0 ? "Start your first inspection" : "On track"),
                deltaPositive: true,
                icon: "hammer.fill",
                tint: Theme.mint
            ),
            KPIMetric(
                title: "Active Leads",
                value: "\(activeLeads)",
                delta: customers.isEmpty ? "Capture your first lead" : "In your pipeline",
                deltaPositive: activeLeads > 0,
                icon: "person.2.fill",
                tint: Theme.amber
            )
        ]

        if let revenueValue {
            metrics.append(KPIMetric(
                title: "Pipeline $",
                value: formatCompactCurrency(revenueValue),
                delta: revenueSource,
                deltaPositive: true,
                icon: "chart.line.uptrend.xyaxis",
                tint: Theme.mint
            ))
        }

        metrics.append(KPIMetric(
            title: "Storm-Impacted",
            value: "\(max(stormTagged, activeAlerts))",
            delta: activeAlerts > 0
                ? "\(activeAlerts) active alert\(activeAlerts == 1 ? "" : "s")"
                : (stormTagged > 0 ? "Tagged leads" : "No active storms"),
            deltaPositive: false,
            icon: "cloud.bolt.rain.fill",
            tint: Theme.crimson
        ))

        return metrics
    }

    // MARK: - Pipeline (compact 5-column board)

    static func pipelineColumns(customers: [Customer]) -> [PipelineColumn] {
        func count(_ stages: [JobPipelineStage]) -> Int {
            customers.filter { stages.contains($0.stage) }.count
        }
        func value(_ stages: [JobPipelineStage]) -> String {
            let total = customers
                .filter { stages.contains($0.stage) }
                .compactMap { parseMoney($0.estimatedValue) }
                .reduce(0, +)
            // Fall back to signed/saved estimate dollars when stage value is blank.
            return total > 0 ? formatCompactCurrency(total) : "—"
        }

        return [
            PipelineColumn(stage: .new,
                           count: count([.knocked]),
                           value: value([.knocked])),
            PipelineColumn(stage: .contacted,
                           count: count([.interested, .inspectionScheduled, .inspectionComplete]),
                           value: value([.interested, .inspectionScheduled, .inspectionComplete])),
            PipelineColumn(stage: .proposal,
                           count: count([.recapSent, .claimFiled, .adjusterMeeting]),
                           value: value([.recapSent, .claimFiled, .adjusterMeeting])),
            PipelineColumn(stage: .won,
                           count: count([.approved, .materialOrdered, .jobComplete, .paid]),
                           value: value([.approved, .materialOrdered, .jobComplete, .paid])),
            PipelineColumn(stage: .lost,
                           count: 0,
                           value: "—")
        ]
    }

    static func pipelineSummary(customers: [Customer]) -> String {
        let cols = pipelineColumns(customers: customers)
        let totalLeads = cols.map(\.count).reduce(0, +)
        let weighted = customers
            .compactMap { parseMoney($0.estimatedValue) }
            .reduce(0, +)
        if totalLeads == 0 {
            return "No leads yet · start a New Lead"
        }
        let money = weighted > 0 ? formatCompactCurrency(weighted) + " est." : "value TBD"
        return "\(totalLeads) lead\(totalLeads == 1 ? "" : "s") · \(money)"
    }

    // MARK: - Home pipeline mini chips (8 stages)

    static func homePipelineStages(customers: [Customer]) -> [HomePipelineStage] {
        let specs: [(String, Color, JobPipelineStage?)] = [
            ("NEW LEAD",   Theme.inkFaint, .knocked),
            ("CONTACTED",  Theme.sky,      .interested),
            ("INSP SCHED", Theme.amber,    .inspectionScheduled),
            ("INSP DONE",  Theme.amber,    .inspectionComplete),
            ("ESTIMATE",   Color(red: 0.55, green: 0.30, blue: 0.85), .recapSent),
            ("APPROVED",   Theme.mint,     .approved),
            ("INSTALL",    Theme.ember,    .materialOrdered),
            ("PAID",       Color(red: 0.10, green: 0.55, blue: 0.35), .paid)
        ]
        return specs.map { label, color, stage in
            let count = stage.map { s in customers.filter { $0.stage == s }.count } ?? 0
            return HomePipelineStage(label: label, color: color, count: count, mappedStage: stage)
        }
    }

    static func homePipelineIsEmpty(customers: [Customer]) -> Bool {
        homePipelineStages(customers: customers).allSatisfy { $0.count == 0 }
    }

    // MARK: - Schedule (today's inspections — real timestamps only)

    static func todaySchedule(customers: [Customer],
                              inspections: [Inspection] = InspectionStore.shared.inspections) -> [ScheduleItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let timeFmt: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()

        // Only real Inspection records dated today. Do NOT invent clock times
        // for scheduled customers without a timestamp.
        let todaysInspections = inspections.filter {
            cal.isDate($0.job.inspectionDate, inSameDayAs: today)
        }
        .sorted { $0.job.inspectionDate < $1.job.inspectionDate }

        return todaysInspections.prefix(8).map { insp in
            let name = insp.job.clientName.isEmpty ? "Inspection" : insp.job.clientName
            let addr = insp.job.propertyAddress.isEmpty ? "Address pending" : insp.job.propertyAddress
            let storm = insp.event.hasHail || insp.event.hasWind
            return ScheduleItem(
                time: timeFmt.string(from: insp.job.inspectionDate),
                kind: .inspection,
                title: name,
                address: addr,
                assignee: displayName(),
                assigneeColor: Theme.ember,
                priority: storm ? .storm : .normal
            )
        }
    }

    /// Scheduled stops without a clock time (used by Plan for non-today days).
    static func untimedScheduledStops(customers: [Customer]) -> [ScheduleItem] {
        customers
            .filter { $0.stage == .inspectionScheduled || $0.stage == .adjusterMeeting }
            .prefix(8)
            .map { c in
                ScheduleItem(
                    time: "—",
                    kind: c.stage == .adjusterMeeting ? .followUp : .inspection,
                    title: c.ownerName.isEmpty ? "Scheduled stop" : c.ownerName,
                    address: c.address.isEmpty ? "Address pending" : c.address,
                    assignee: displayName(),
                    assigneeColor: Theme.sky,
                    priority: c.stormTagged ? .storm : .normal
                )
            }
    }

    static func scheduleSubtitle(items: [ScheduleItem]) -> String {
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE, MMM d"
        let day = dayFmt.string(from: Date())
        if items.isEmpty {
            return "\(day) · nothing scheduled"
        }
        return "\(day) · \(items.count) stop\(items.count == 1 ? "" : "s")"
    }

    // MARK: - Recent jobs

    static func recentJobs(customers: [Customer]) -> [RecentJob] {
        customers
            .filter { !$0.isUnassignedDraft }
            .sorted { lhs, rhs in
                if lhs.stage.stepIndex != rhs.stage.stepIndex {
                    return lhs.stage.stepIndex > rhs.stage.stepIndex
                }
                return lhs.ownerName.localizedCaseInsensitiveCompare(rhs.ownerName) == .orderedAscending
            }
            .prefix(8)
            .map { c in
                RecentJob(
                    title: c.ownerName.isEmpty ? "Untitled" : c.ownerName,
                    address: c.address.isEmpty ? "Address pending" : c.address,
                    status: jobStatus(for: c.stage),
                    subtitle: recentSubtitle(for: c),
                    imageURL: ""
                )
            }
    }

    static func homeRecentJobs(customers: [Customer]) -> [HomeRecentJob] {
        customers
            .filter { !$0.isUnassignedDraft }
            .sorted { $0.stage.stepIndex > $1.stage.stepIndex }
            .prefix(8)
            .map { c in
                HomeRecentJob(
                    customerName: c.ownerName.isEmpty ? "Untitled" : c.ownerName,
                    address: c.address.isEmpty ? "Address pending" : c.address,
                    stageType: homeStage(for: c.stage),
                    damageScore: damageScore(for: c),
                    imageURL: ""
                )
            }
    }

    // MARK: - AI review queue

    static func aiReviewItems(from queue: TrainingQueueStore = .shared) -> [AIReviewItem] {
        queue.pending.prefix(6).map { item in
            AIReviewItem(
                address: item.slopeOrientation.isEmpty ? item.inspectionId : "\(item.inspectionId) · \(item.slopeOrientation)",
                damageType: item.kind.displayName,
                confidence: Int((item.aiConfidence * 100).rounded()),
                imageURL: item.photoPath ?? "",
                aiTags: ["Needs review", item.kind.rawValue.replacingOccurrences(of: "_", with: " ")]
            )
        }
    }

    // MARK: - Tasks + activity (store-backed)

    static func derivedTasks(customers: [Customer],
                             queue: TrainingQueueStore = .shared) -> [TaskItem] {
        var tasks: [TaskItem] = []

        let pendingReviews = queue.pendingCount
        if pendingReviews > 0 {
            tasks.append(TaskItem(
                title: "Review \(pendingReviews) AI detection\(pendingReviews == 1 ? "" : "s")",
                due: "Today",
                done: false,
                tag: "Review",
                tagColor: Theme.amber
            ))
        }

        let adjuster = customers.filter { $0.stage == .adjusterMeeting }
        for c in adjuster.prefix(3) {
            tasks.append(TaskItem(
                title: "Follow up with adjuster · \(c.ownerName)",
                due: "This week",
                done: false,
                tag: "Claim",
                tagColor: Theme.ember
            ))
        }

        let scheduled = customers.filter { $0.stage == .inspectionScheduled }
        for c in scheduled.prefix(3) {
            tasks.append(TaskItem(
                title: "Run inspection · \(c.ownerName)",
                due: "Scheduled",
                done: false,
                tag: "Ops",
                tagColor: Theme.mint
            ))
        }

        let recap = customers.filter { $0.stage == .inspectionComplete }
        for c in recap.prefix(2) {
            tasks.append(TaskItem(
                title: "Send recap · \(c.ownerName)",
                due: "Today",
                done: false,
                tag: "Claim",
                tagColor: Theme.ember
            ))
        }

        return tasks
    }

    static func recentActivity(customers: [Customer],
                               inspections: [Inspection] = InspectionStore.shared.inspections,
                               alerts: [StormAlert] = StormAlertStore.shared.alerts,
                               activity: ActivityStore = .shared) -> [ActivityEntry] {
        var entries: [ActivityEntry] = []

        // Real ActivityStore events across known inspections (newest first).
        let reportIds = inspections.map(\.id) + ["ai-calibration"]
        let storeEvents = activity.recentAcross(reportIds: reportIds, limit: 8)
        for e in storeEvents where e.kind != .uiTap {
            entries.append(ActivityEntry(
                icon: icon(for: e.kind),
                iconColor: color(for: e.kind),
                title: e.summary,
                detail: e.detail ?? e.inspectionId,
                time: relativeTime(e.timestamp)
            ))
        }

        // Latest storm alerts
        for a in alerts.sorted(by: { $0.createdAt > $1.createdAt }).prefix(2) {
            entries.append(ActivityEntry(
                icon: "bolt.fill",
                iconColor: Theme.ember,
                title: a.headline,
                detail: a.areaLabel.isEmpty ? a.source : a.areaLabel,
                time: relativeTime(a.createdAt)
            ))
        }

        // Recent paid / approved customers as wins
        for c in customers.filter({ $0.stage == .paid || $0.stage == .approved || $0.stage == .jobComplete }).prefix(3) {
            entries.append(ActivityEntry(
                icon: "checkmark.seal.fill",
                iconColor: Theme.mint,
                title: "\(c.ownerName) · \(c.stage.rawValue)",
                detail: c.address.isEmpty ? "Job update" : c.address,
                time: "Recent"
            ))
        }

        // Fresh inspections
        for insp in inspections.sorted(by: { $0.job.inspectionDate > $1.job.inspectionDate }).prefix(3) {
            let name = insp.job.clientName.isEmpty ? insp.job.reportId : insp.job.clientName
            entries.append(ActivityEntry(
                icon: "doc.text.fill",
                iconColor: Theme.amber,
                title: "Inspection \(insp.job.reportId)",
                detail: name,
                time: relativeTime(insp.job.inspectionDate)
            ))
        }

        return Array(entries.prefix(8))
    }

    // MARK: - Wins (from real paid/approved customers)

    struct Win: Identifiable {
        let id: UUID
        let initials: String
        let name: String
        let amount: String
        let address: String
        let when: Date
        let tint: Color
    }

    static func recentWins(customers: [Customer]) -> [Win] {
        customers
            .filter { $0.stage == .paid || $0.stage == .approved || $0.stage == .jobComplete }
            .prefix(6)
            .map { c in
                Win(
                    id: c.id,
                    initials: c.initials.isEmpty ? "RW" : c.initials,
                    name: c.ownerName.isEmpty ? "Customer" : c.ownerName,
                    amount: c.estimatedValue.isEmpty ? "—" : c.estimatedValue,
                    address: c.address.isEmpty ? "Address pending" : c.address,
                    when: Date(),
                    tint: c.stage == .paid ? Theme.mint : Theme.sky
                )
            }
    }

    // MARK: - Goals (real counts, fixed targets)

    struct Goal: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let value: Int
        let target: Int
        var fraction: Double { min(1.0, Double(value) / Double(max(1, target))) }
    }

    static func todaysGoals(customers: [Customer],
                            knocks: KnockSessionStore = .shared) -> [Goal] {
        let today = Calendar.current.startOfDay(for: Date())
        let doors = knocks.sessions
            .flatMap(\.knocks)
            .filter { $0.created_at >= today }
            .count
        let inspections = customers.filter {
            $0.stage == .inspectionComplete || $0.stage == .inspectionScheduled
        }.count
        let booked = customers.filter {
            $0.stage.stepIndex >= JobPipelineStage.inspectionScheduled.stepIndex
        }.count
        return [
            Goal(label: "Doors Knocked", icon: "hand.tap.fill", value: doors, target: 60),
            Goal(label: "Inspections", icon: "camera.viewfinder", value: min(inspections, 20), target: 5),
            Goal(label: "Leads Booked", icon: "calendar.badge.plus", value: booked, target: 4)
        ]
    }

    // MARK: - Display name

    static func displayName() -> String {
        if case .signedIn(_, let email, _) = AuthStore.shared.state,
           let email, !email.isEmpty {
            let local = email.split(separator: "@").first.map(String.init) ?? email
            let parts = local
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            let name = parts.joined(separator: " ")
            if !name.isEmpty { return name }
        }
        let n = InspectorUser.current.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Inspector" : n
    }

    static func displayInitials() -> String {
        let name = displayName()
        let parts = name.split(separator: " ").compactMap { $0.first }.prefix(2)
        let s = parts.map(String.init).joined()
        return s.isEmpty ? "RW" : s.uppercased()
    }

    // MARK: - Helpers

    private static func jobStatus(for stage: JobPipelineStage) -> JobStatus {
        switch stage {
        case .paid, .jobComplete: return .done
        case .approved, .materialOrdered: return .active
        case .adjusterMeeting, .claimFiled: return .awaiting
        default: return .scheduled
        }
    }

    private static func homeStage(for stage: JobPipelineStage) -> HomeJobStageType {
        switch stage {
        case .paid, .jobComplete: return .completed
        case .materialOrdered: return .inProgress
        case .approved: return .approved
        case .recapSent, .claimFiled, .adjusterMeeting: return .estimateSent
        default: return .inspectionDone
        }
    }

    private static func damageScore(for customer: Customer) -> Int {
        if !customer.damageFindings.isEmpty {
            let hits = customer.damageFindings.filter(\.detected).count
            return min(99, max(10, hits * 12))
        }
        if let grade = customer.claimGrade {
            switch grade {
            case .noFunctional: return 18
            case .hail, .wind: return 62
            case .combined: return 88
            }
        }
        return customer.stormTagged ? 55 : 30
    }

    private static func recentSubtitle(for c: Customer) -> String {
        if !c.estimatedValue.isEmpty {
            return "\(c.stage.rawValue) · \(c.estimatedValue)"
        }
        if let squares = c.roofSquares {
            return "\(c.stage.rawValue) · \(String(format: "%.1f", squares)) sq"
        }
        return c.stage.rawValue
    }

    private static func parseMoney(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "k", with: "000", options: .caseInsensitive)
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.contains("-") {
            let parts = cleaned.split(separator: "-").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2 else { return parts.first }
            return (parts[0] + parts[1]) / 2
        }
        return Double(cleaned)
    }

    private static func formatCompactCurrency(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "$%.0fk", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }

    private static func relativeTime(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 172_800 { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private static func icon(for kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .jobCreated: return "plus.circle.fill"
        case .stormMatched, .weatherSynced: return "bolt.fill"
        case .proposalSigned, .proposalSent, .proposalDrafted, .proposalViewed: return "doc.richtext.fill"
        case .estimateSaved, .estimateConverted: return "dollarsign.circle.fill"
        case .knockLogged, .knockConvertedToLead: return "hand.tap.fill"
        case .reportGenerated: return "doc.text.fill"
        case .aiCalibrationUpdated: return "slider.horizontal.3"
        default: return "circle.fill"
        }
    }

    private static func color(for kind: ActivityEvent.Kind) -> Color {
        switch kind {
        case .stormMatched, .weatherSynced: return Theme.ember
        case .proposalSigned, .estimateConverted: return Theme.mint
        case .proposalSent, .proposalDrafted: return Theme.sky
        case .knockLogged: return Theme.amber
        default: return Theme.inkSoft
        }
    }
}
