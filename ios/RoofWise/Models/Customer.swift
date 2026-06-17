import SwiftUI

// MARK: - Job Pipeline

enum JobPipelineStage: String, CaseIterable, Identifiable, Codable {
    case knocked = "Knocked"
    case interested = "Interested"
    case inspectionScheduled = "Inspection Scheduled"
    case inspectionComplete = "Inspection Complete"
    case recapSent = "Recap Sent"
    case claimFiled = "Claim Filed"
    case adjusterMeeting = "Adjuster Meeting"
    case approved = "Approved"
    case materialOrdered = "Material Ordered"
    case jobComplete = "Job Complete"
    case paid = "Paid"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .knocked: return "Knocked"
        case .interested: return "Interested"
        case .inspectionScheduled: return "Insp. Scheduled"
        case .inspectionComplete: return "Insp. Done"
        case .recapSent: return "Recap Sent"
        case .claimFiled: return "Claim Filed"
        case .adjusterMeeting: return "Adjuster Mtg"
        case .approved: return "Approved"
        case .materialOrdered: return "Materials"
        case .jobComplete: return "Job Done"
        case .paid: return "Paid"
        }
    }

    var color: Color {
        switch self {
        case .knocked: return Theme.inkFaint
        case .interested: return Theme.sky
        case .inspectionScheduled: return Theme.amber
        case .inspectionComplete: return Theme.amber
        case .recapSent: return Theme.ember
        case .claimFiled: return Theme.ember
        case .adjusterMeeting: return Theme.ember
        case .approved: return Theme.mint
        case .materialOrdered: return Theme.mint
        case .jobComplete: return Theme.mint
        case .paid: return Color(red: 0.10, green: 0.55, blue: 0.35)
        }
    }

    var icon: String {
        switch self {
        case .knocked: return "hand.tap.fill"
        case .interested: return "hand.thumbsup.fill"
        case .inspectionScheduled: return "calendar.badge.clock"
        case .inspectionComplete: return "checkmark.seal.fill"
        case .recapSent: return "paperplane.fill"
        case .claimFiled: return "doc.badge.plus"
        case .adjusterMeeting: return "person.2.wave.2.fill"
        case .approved: return "checkmark.shield.fill"
        case .materialOrdered: return "shippingbox.fill"
        case .jobComplete: return "hammer.fill"
        case .paid: return "dollarsign.circle.fill"
        }
    }

    var stepIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

// MARK: - Customer

struct CustomerNote: Identifiable {
    let id: UUID = UUID()
    var text: String
    var date: Date = Date()
}

struct Customer: Identifiable {
    let id: UUID = UUID()

    // Contact
    var ownerName: String
    var address: String
    var phone: String = ""
    var email: String = ""

    // Insurance / claim
    var insuranceCompany: String = ""
    var policyNumber: String = ""
    var dateOfLoss: Date? = nil
    var adjusterName: String = ""
    var adjusterPhone: String = ""

    // Pipeline
    var stage: JobPipelineStage = .knocked
    var stormTagged: Bool = false
    var estimatedValue: String = ""

    /// Links this customer to its HAAG `Inspection` (`InspectionStore`) by
    /// report id, so the customer profile can open the inspection report and
    /// jobs created in the New Job wizard surface in the Leads list.
    var linkedReportId: String? = nil

    // Inspection data attached
    var photos: [CapturedPhoto] = []
    var damageFindings: [InspectionFinding] = []
    var claimPacketSummary: String = ""
    var claimGrade: HaagGrade? = nil

    // Notes
    var notes: [CustomerNote] = []

    var initials: String {
        ownerName.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined()
    }

    var isUnassignedDraft: Bool {
        ownerName == "Unassigned Inspection" && address.hasPrefix("Add property")
    }
}
