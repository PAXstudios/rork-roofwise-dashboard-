import Foundation

/// A single chronological event on an inspection. Stored per-inspection in
/// `activity-<reportId>.json`. Pure data; no UI here.
nonisolated struct ActivityEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let inspectionId: String
    let kind: Kind
    let timestamp: Date
    let summary: String
    let detail: String?

    init(id: UUID = UUID(),
         inspectionId: String,
         kind: Kind,
         timestamp: Date = .now,
         summary: String,
         detail: String? = nil) {
        self.id = id
        self.inspectionId = inspectionId
        self.kind = kind
        self.timestamp = timestamp
        self.summary = summary
        self.detail = detail
    }

    enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case jobCreated = "job_created"
        case addressGeocoded = "address_geocoded"
        case weatherSynced = "weather_synced"
        case stormMatched = "storm_matched"
        case roofDetected = "roof_detected"
        case slopeAdded = "slope_added"
        case slopeEdited = "slope_edited"
        case decisionComputed = "decision_computed"
        case signatureInspectorCaptured = "signature_inspector_captured"
        case signatureHomeownerCaptured = "signature_homeowner_captured"
        case reportGenerated = "report_generated"
        case estimateSaved = "estimate_saved"
        case estimateConverted = "estimate_converted"
        case noteAdded = "note_added"
        case knockLogged = "knock_logged"
        case knockConvertedToLead = "knock_converted_to_lead"
        case routeCompleted = "route_completed"
        case uiTap = "ui_tap"
        case proposalDrafted = "proposal_drafted"
        case proposalSent = "proposal_sent"
        case proposalViewed = "proposal_viewed"
        case proposalSigned = "proposal_signed"
        case aiCalibrationUpdated = "ai_calibration_updated"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case inspectionId = "inspection_id"
        case kind
        case timestamp
        case summary
        case detail
    }
}
