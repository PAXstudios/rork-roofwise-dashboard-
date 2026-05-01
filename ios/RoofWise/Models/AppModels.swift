import SwiftUI
import CoreLocation

// MARK: - KPI

struct KPIMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let delta: String
    let deltaPositive: Bool
    let icon: String
    let tint: Color
}

// MARK: - Pipeline

enum PipelineStage: String, CaseIterable, Identifiable {
    case new = "New"
    case contacted = "Contacted"
    case proposal = "Proposal"
    case won = "Won"
    case lost = "Lost"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .new: return Theme.sky
        case .contacted: return Theme.ember
        case .proposal: return Theme.amber
        case .won: return Theme.mint
        case .lost: return Theme.inkFaint
        }
    }
}

struct PipelineColumn: Identifiable {
    let id = UUID()
    let stage: PipelineStage
    let count: Int
    let value: String
}

// MARK: - Schedule

enum ScheduleKind: String {
    case inspection = "Inspection"
    case estimate = "Estimate Review"
    case install = "Install"
    case followUp = "Follow Up"

    var icon: String {
        switch self {
        case .inspection: return "binoculars.fill"
        case .estimate: return "doc.text.magnifyingglass"
        case .install: return "hammer.fill"
        case .followUp: return "phone.arrow.up.right.fill"
        }
    }
}

struct ScheduleItem: Identifiable {
    let id = UUID()
    let time: String
    let kind: ScheduleKind
    let title: String
    let address: String
    let assignee: String
    let assigneeColor: Color
    let priority: Priority
}

enum Priority: String {
    case high = "High Priority"
    case normal = "Standard"
    case storm = "Storm Route"
    var color: Color {
        switch self {
        case .high: return Theme.crimson
        case .normal: return Theme.sky
        case .storm: return Theme.ember
        }
    }
    var bg: Color {
        switch self {
        case .high: return Color(red: 1.0, green: 0.92, blue: 0.93)
        case .normal: return Theme.skySoft
        case .storm: return Theme.emberSoft
        }
    }
}

// MARK: - Recent Jobs

enum JobStatus: String {
    case done = "Done"
    case active = "Active"
    case scheduled = "Scheduled"
    case awaiting = "Awaiting Adjuster"

    var color: Color {
        switch self {
        case .done: return Theme.mint
        case .active: return Theme.ember
        case .scheduled: return Theme.sky
        case .awaiting: return Theme.amber
        }
    }
}

struct RecentJob: Identifiable {
    let id = UUID()
    let title: String
    let address: String
    let status: JobStatus
    let subtitle: String
    let imageURL: String
}

// MARK: - Storms

enum StormType: String, CaseIterable, Identifiable {
    case hail = "Hail"
    case wind = "Wind"
    var id: String { rawValue }
    var color: Color { self == .hail ? Theme.sky : Theme.ember }
    var icon: String { self == .hail ? "cloud.hail.fill" : "wind" }
}

struct StormEvent: Identifiable {
    let id = UUID()
    let type: StormType
    let year: Int
    let date: String
    let intensity: Double      // 0-1
    let sizeInches: Double?    // hail
    let windMPH: Int?          // wind
    let x: CGFloat             // 0-1 normalized within map view
    let y: CGFloat
    let radius: CGFloat        // 0-1
}

// MARK: - Leads on map

enum LeadKind: String {
    case lead, job, storm
    var color: Color {
        switch self {
        case .lead: return Theme.sky
        case .job: return Theme.mint
        case .storm: return Theme.ember
        }
    }
    var icon: String {
        switch self {
        case .lead: return "mappin"
        case .job: return "hammer.fill"
        case .storm: return "bolt.fill"
        }
    }
}

struct MapPin: Identifiable {
    let id = UUID()
    let kind: LeadKind
    let label: String
    let x: CGFloat
    let y: CGFloat
}

// MARK: - AI Training

struct AIReviewItem: Identifiable {
    let id = UUID()
    let address: String
    let damageType: String
    let confidence: Int   // 0-100
    let imageURL: String
    let aiTags: [String]
}

// MARK: - Tasks

struct TaskItem: Identifiable {
    let id = UUID()
    var title: String
    var due: String
    var done: Bool
    let tag: String
    let tagColor: Color
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    let time: String
}
