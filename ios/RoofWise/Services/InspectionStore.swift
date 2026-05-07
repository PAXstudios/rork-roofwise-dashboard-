import Foundation
import Observation

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
