import Foundation
import Observation
import UIKit

/// Source-of-truth store for Haag `Inspection` records.
/// Persists the full array as JSON inside the app's Documents directory.
@Observable
final class InspectionStore {
    static let shared = InspectionStore()

    private(set) var inspections: [Inspection] = []

    private let filename = "inspections.json"
    private let user: InspectorUser

    init(user: InspectorUser = .current) {
        self.user = user
        load()
    }

    // MARK: Report ID

    /// Generates the next report id in the form `RW-2026-####`.
    func nextReportId(for date: Date = .now) -> String {
        let year = Calendar.current.component(.year, from: date)
        let prefix = "RW-\(year)-"
        let usedNumbers: [Int] = inspections.compactMap { insp in
            guard insp.job.reportId.hasPrefix(prefix) else { return nil }
            return Int(insp.job.reportId.dropFirst(prefix.count))
        }
        let next = (usedNumbers.max() ?? 0) + 1
        return prefix + String(format: "%04d", next)
    }

    /// Builds an empty draft inspection ready for editing in the New Job wizard.
    func makeDraft() -> Inspection {
        Inspection(
            job: .empty(
                reportId: nextReportId(),
                inspectorName: user.name,
                companyName: user.company
            ),
            event: .empty,
            roof: .empty,
            slopes: [],
            collateral: .empty,
            summary: .empty
        )
    }

    // MARK: CRUD

    @discardableResult
    func add(_ inspection: Inspection) -> Inspection {
        inspections.append(inspection)
        save()
        return inspection
    }

    func update(_ inspection: Inspection) {
        guard let idx = inspections.firstIndex(where: { $0.id == inspection.id }) else { return }
        inspections[idx] = inspection
        save()
    }

    func delete(_ inspection: Inspection) {
        inspections.removeAll { $0.id == inspection.id }
        save()
    }

    func inspection(with reportId: String) -> Inspection? {
        inspections.first { $0.job.reportId == reportId }
    }

    // MARK: Slope helpers

    /// Append (or replace) a slope on the inspection identified by `reportId`.
    /// Replaces an existing slope when its `orientation` matches.
    func upsertSlope(_ slope: Slope, on reportId: String) {
        guard let idx = inspections.firstIndex(where: { $0.job.reportId == reportId }) else { return }
        var insp = inspections[idx]
        if let existing = insp.slopes.firstIndex(where: { $0.orientation == slope.orientation }) {
            insp.slopes[existing] = slope
        } else {
            insp.slopes.append(slope)
        }
        recomputeSummary(&insp)
        inspections[idx] = insp
        save()
    }

    func removeSlope(orientation: String, on reportId: String) {
        guard let idx = inspections.firstIndex(where: { $0.job.reportId == reportId }) else { return }
        var insp = inspections[idx]
        insp.slopes.removeAll { $0.orientation == orientation }
        recomputeSummary(&insp)
        inspections[idx] = insp
        sessionPhotos[Self.photoKey(reportId, orientation)] = nil
        save()
    }

    /// Re-runs the DecisionEngine across the inspection so per-slope verdicts
    /// and the roof-level summary stay in lock-step with the latest data.
    private func recomputeSummary(_ insp: inout Inspection) {
        insp = DecisionEngine.decide(insp)
    }

    // MARK: Session photos (in-memory, not persisted to JSON)

    /// Reference photos captured per slope. Cleared on app relaunch — schema
    /// keeps the structured Slope record; raw images live alongside the
    /// session for review only.
    private(set) var sessionPhotos: [String: [UIImage]] = [:]

    func setPhotos(_ photos: [UIImage], for reportId: String, orientation: String) {
        sessionPhotos[Self.photoKey(reportId, orientation)] = photos
    }

    func photos(for reportId: String, orientation: String) -> [UIImage] {
        sessionPhotos[Self.photoKey(reportId, orientation)] ?? []
    }

    private static func photoKey(_ reportId: String, _ orientation: String) -> String {
        "\(reportId)::\(orientation)"
    }

    // MARK: Persistence

    private var fileURL: URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        return docs.appendingPathComponent(filename)
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? makeDecoder().decode([Inspection].self, from: data) {
            inspections = decoded
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        do {
            let data = try makeEncoder().encode(inspections)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Persist failures are non-fatal in dev; state still lives in memory.
            #if DEBUG
            print("InspectionStore save failed: \(error)")
            #endif
        }
    }
}
