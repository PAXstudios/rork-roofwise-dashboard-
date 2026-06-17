import Foundation
import Observation

// MARK: - Safety Assessment Store
//
// Persists the latest roof-walk safety assessments per inspection (keyed by
// report id), keeping the most recent 5 so the inspector can see how conditions
// changed over the day. Stored as JSON in the app's Documents directory — the
// same pattern as InspectionStore.

@Observable
final class SafetyAssessmentStore {
    static let shared = SafetyAssessmentStore()

    /// reportId → assessments, newest first.
    private(set) var assessmentsByReport: [String: [SafetyAssessment]] = [:]

    private let filename = "safety_assessments.json"
    private let maxPerInspection = 5

    init() { load() }

    /// Records a new assessment for an inspection, trimming to the latest 5.
    func record(_ assessment: SafetyAssessment, for reportId: String) {
        var list = assessmentsByReport[reportId] ?? []
        list.insert(assessment, at: 0)
        if list.count > maxPerInspection { list = Array(list.prefix(maxPerInspection)) }
        assessmentsByReport[reportId] = list
        save()
    }

    /// The most recent assessment for an inspection, if any.
    func latest(for reportId: String) -> SafetyAssessment? {
        assessmentsByReport[reportId]?.first
    }

    /// Full history (newest first) for an inspection.
    func history(for reportId: String) -> [SafetyAssessment] {
        assessmentsByReport[reportId] ?? []
    }

    // MARK: - Persistence

    private var fileURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: [SafetyAssessment]].self, from: data) {
            assessmentsByReport = decoded
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(assessmentsByReport) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
