import Foundation
import Observation
import SwiftData

@Observable
final class CorrectionsStore {
    static let shared = CorrectionsStore()

    private init() {}

    func all(in context: ModelContext) -> [Correction] {
        let descriptor = FetchDescriptor<Correction>(
            sortBy: [SortDescriptor(\.correctedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func pending(in context: ModelContext) -> [Correction] {
        all(in: context).filter { $0.syncStatus == .pending }
    }

    @discardableResult
    func add(_ correction: Correction, in context: ModelContext) -> Correction {
        context.insert(correction)
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("CorrectionsStore save failed: \(error)")
            #endif
        }
        let export = correction.export
        LocalLearningEngine.shared.record(export)
        CorrectionsSyncService.shared.enqueue(export)
        ActivityStore.shared.log(
            .aiCalibrationUpdated,
            summary: "AI calibration updated",
            detail: LocalLearningEngine.shared.deltaSummary,
            reportId: correction.inspectionId
        )
        return correction
    }
}
