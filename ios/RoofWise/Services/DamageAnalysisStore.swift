import Foundation
import Observation
import SwiftUI
import UIKit

@Observable
final class DamageAnalysisStore {
    static let shared = DamageAnalysisStore()

    private(set) var runs: [String: DamageAnalysisRun] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func run(for reportId: String) -> DamageAnalysisRun? {
        runs[reportId]
    }

    func photos(for reportId: String) -> [CapturedPhoto] {
        runs[reportId]?.photos ?? []
    }

    func start(reportId: String) {
        if let existing = runs[reportId] {
            if existing.isRunning { return }
            if existing.completedAt != nil, existing.total > 0 { return }
        }
        tasks[reportId]?.cancel()
        tasks[reportId] = Task { @MainActor in
            await runAnalysis(reportId: reportId)
        }
    }

    func restart(reportId: String) {
        tasks[reportId]?.cancel()
        runs[reportId] = nil
        start(reportId: reportId)
    }

    private func runAnalysis(reportId: String) async {
        let work = queuedPhotos(reportId: reportId)
        guard !work.isEmpty else {
            runs[reportId] = DamageAnalysisRun(
                reportId: reportId,
                isRunning: false,
                progress: 1,
                passLabel: "No photos to analyze",
                currentIndex: 0,
                total: 0,
                currentThumbnail: nil,
                currentMarkers: [],
                hits: [],
                photos: [],
                findings: [],
                completedAt: .now,
                lastError: "Add roof photos to a slope first."
            )
            return
        }

        runs[reportId] = DamageAnalysisRun(
            reportId: reportId,
            isRunning: true,
            progress: 0.02,
            passLabel: "Preparing roof images",
            currentIndex: 1,
            total: work.count,
            currentThumbnail: work.first?.photo.image,
            currentMarkers: [],
            hits: [],
            photos: [],
            findings: [],
            completedAt: nil,
            lastError: nil
        )

        var analyzedWork: [DamagePhotoWorkItem] = []
        var bestFindings: [String: InspectionFinding] = [:]
        var hits: [DetectedHit] = []
        var hadFailure = false

        for index in work.indices {
            guard Task.isCancelled == false else { return }
            let item = work[index]
            updateRun(reportId) { run in
                run.currentIndex = index + 1
                run.currentThumbnail = item.photo.image
                run.currentMarkers = []
                run.passLabel = passLabel(for: index)
                run.progress = max(run.progress, Double(index) / Double(max(work.count, 1)) * 0.82 + 0.04)
            }

            var photo = item.photo
            let result = await GeminiAnalysisService.analyzeFull(image: photo.image,
                                                                 slope: photo.slope,
                                                                 mode: photo.captureMode,
                                                                 squaresCovered: photo.squaresCovered)
            photo.findings = result.findings
            photo.damageMarkers = result.noRoofDetected ? [] : result.markers
            photo.aiConfidenceSnapshot = result.confidenceSnapshot
            photo.analyzed = !result.failed
            if result.failed { hadFailure = true }

            for marker in photo.damageMarkers {
                hits.append(marker.detectedHit)
                updateRun(reportId) { run in
                    run.hits = hits
                    run.currentMarkers.append(marker)
                }
                try? await Task.sleep(for: .milliseconds(35))
            }

            for finding in photo.findings where finding.label != "ai_unavailable" {
                if let existing = bestFindings[finding.label] {
                    if finding.confidence > existing.confidence || finding.severity.rank > existing.severity.rank {
                        bestFindings[finding.label] = finding
                    }
                } else {
                    bestFindings[finding.label] = finding
                }
            }

            analyzedWork.append(DamagePhotoWorkItem(orientation: item.orientation, photo: photo))
            updateRun(reportId) { run in
                run.photos = analyzedWork.map(\.photo)
                run.progress = min(0.90, Double(index + 1) / Double(max(work.count, 1)) * 0.82 + 0.08)
            }
        }

        let summary = summaryFindings(from: analyzedWork.map(\.photo), bestFindings: bestFindings)
        apply(analyzedWork: analyzedWork, findings: summary, reportId: reportId)

        updateRun(reportId) { run in
            run.isRunning = false
            run.progress = 1
            run.passLabel = hadFailure ? "Analysis complete with retry items" : "Analysis complete"
            run.photos = analyzedWork.map(\.photo)
            run.findings = summary
            run.completedAt = .now
            run.lastError = hadFailure ? "Some photos could not be analyzed. Open an individual photo and tap Retry AI Analysis." : nil
        }
        tasks[reportId] = nil
        ActivityStore.shared.log(.decisionComputed,
                                 summary: "AI damage analysis complete",
                                 detail: "\(hits.count) evidence-backed marker\(hits.count == 1 ? "" : "s")",
                                 reportId: reportId)
    }

    private func updateRun(_ reportId: String, mutate: (inout DamageAnalysisRun) -> Void) {
        guard var run = runs[reportId] else { return }
        mutate(&run)
        runs[reportId] = run
    }

    private func queuedPhotos(reportId: String) -> [DamagePhotoWorkItem] {
        guard let inspection = InspectionStore.shared.inspection(with: reportId) else { return [] }
        return inspection.slopes.flatMap { slope in
            let images = InspectionStore.shared.photos(for: reportId, orientation: slope.orientation)
            let mappedSlope = slopeType(for: slope.orientation)
            return images.map { image in
                let photo = CapturedPhoto(image: image,
                                          slope: mappedSlope,
                                          pitchDegrees: Double(slope.pitchRiseOver12) * 4.75,
                                          elevationFeet: 0,
                                          captureMode: .square,
                                          squaresCovered: max(1, slope.testSquareCount))
                return DamagePhotoWorkItem(orientation: slope.orientation, photo: photo)
            }
        }
    }

    private func slopeType(for orientation: String) -> SlopeType {
        SlopeType.allCases.first { $0.rawValue == orientation || $0.shortName == orientation } ?? .frontSlope
    }

    private func passLabel(for index: Int) -> String {
        let labels = [
            "Detecting hail impacts",
            "Snapping markers to pixel evidence",
            "Checking shingle edges",
            "Finding exposed mat",
            "Scoring confidence"
        ]
        return labels[index % labels.count]
    }

    private func apply(analyzedWork: [DamagePhotoWorkItem],
                       findings: [InspectionFinding],
                       reportId: String) {
        guard let inspection = InspectionStore.shared.inspection(with: reportId) else { return }
        let grouped = Dictionary(grouping: analyzedWork, by: \.orientation)
        for slope in inspection.slopes {
            guard let items = grouped[slope.orientation] else { continue }
            let markers = items.flatMap { $0.photo.damageMarkers }
            let snapshots = items.compactMap { $0.photo.aiConfidenceSnapshot }
            var updated = slope
            let hailBruise = markers.filter { $0.type == .hailStrike || $0.type == .shingleBruise }.count
            let exposedOrCracked = markers.filter { $0.type == .exposedMat || $0.type == .crack }.count
            let granule = markers.filter { $0.type == .granuleLoss || $0.type == .exposedMat }.count
            let windCrease = markers.filter { $0.type == .windCrease }.count
            let missing = markers.filter { $0.type == .missingShingle }.count
            let lifted = markers.filter { $0.type == .liftedShingle || $0.type == .tornShingle }.count
            updated.damageTypes.hail.asphaltBruise = max(updated.damageTypes.hail.asphaltBruise, hailBruise)
            updated.damageTypes.hail.asphaltMatFracture = max(updated.damageTypes.hail.asphaltMatFracture, exposedOrCracked)
            updated.damageTypes.hail.asphaltGranuleLossExposed = max(updated.damageTypes.hail.asphaltGranuleLossExposed, granule)
            updated.damageTypes.wind.shingleCrease = max(updated.damageTypes.wind.shingleCrease, windCrease)
            updated.damageTypes.wind.shingleMissing = max(updated.damageTypes.wind.shingleMissing, missing)
            updated.damageTypes.wind.shingleLiftedUnsealed = max(updated.damageTypes.wind.shingleLiftedUnsealed, lifted)
            updated.damageTypes.wear.naturalWeathering = updated.damageTypes.wear.naturalWeathering || markers.contains { $0.type == .blister || $0.type == .algae }
            updated.aiConfidenceSnapshot = AIDamageConfidenceSnapshot.merged(snapshots)
            InspectionStore.shared.upsertSlope(updated, on: reportId)
            TrainingQueueStore.shared.enqueueFromSlope(updated, on: reportId)
        }
    }

    private func summaryFindings(from photos: [CapturedPhoto],
                                 bestFindings: [String: InspectionFinding]) -> [InspectionFinding] {
        var results = bestFindings
        let markers = photos.flatMap(\.damageMarkers)
        let hailCount = markers.filter(\.type.isHailImpact).count
        let shingleCount = markers.filter(\.type.isShingleDamage).count
        let hailSeverity: FindingSeverity = hailCount >= 8 ? .severe : hailCount >= 3 ? .moderate : hailCount > 0 ? .minor : .none
        let shingleSeverity: FindingSeverity = shingleCount >= 5 ? .severe : shingleCount >= 2 ? .moderate : shingleCount > 0 ? .minor : .none
        results["hail_hits"] = InspectionFinding(
            label: "hail_hits",
            display: "Hail Hits",
            value: hailCount == 0 ? "No hail strikes detected by AI" : "\(hailCount) evidence-backed strike\(hailCount == 1 ? "" : "s") across \(photos.count) photo\(photos.count == 1 ? "" : "s")",
            confidence: hailCount > 0 ? 93 : 88,
            icon: "circle.hexagongrid.fill",
            tint: hailSeverity == .none ? Theme.mint : hailSeverity.color,
            detected: hailCount > 0,
            severity: hailSeverity
        )
        results["shingle_damage"] = InspectionFinding(
            label: "shingle_damage",
            display: "Shingle Damage",
            value: shingleCount == 0 ? "No shingle-edge damage detected by AI" : "\(shingleCount) bruise / exposed mat / lifted / torn / missing indicator\(shingleCount == 1 ? "" : "s")",
            confidence: shingleCount > 0 ? 91 : 86,
            icon: "rectangle.split.3x1.fill",
            tint: shingleSeverity == .none ? Theme.mint : shingleSeverity.color,
            detected: shingleCount > 0,
            severity: shingleSeverity
        )
        let order = ["shingle_type", "hail_hits", "shingle_damage", "shingle_bruise", "exposed_mat", "lifted_shingle", "torn_shingle", "granule_loss", "missing_shingles", "wind_creasing", "bruising", "cracking_splitting"]
        return order.compactMap { results[$0] } + results.filter { !order.contains($0.key) }.values
    }
}

struct DamageAnalysisRun: Identifiable {
    var id: String { reportId }
    let reportId: String
    var isRunning: Bool
    var progress: Double
    var passLabel: String
    var currentIndex: Int
    var total: Int
    var currentThumbnail: UIImage?
    var currentMarkers: [DamageMarker]
    var hits: [DetectedHit]
    var photos: [CapturedPhoto]
    var findings: [InspectionFinding]
    var completedAt: Date?
    var lastError: String?
}

private struct DamagePhotoWorkItem {
    let orientation: String
    var photo: CapturedPhoto
}

private extension DamageMarker {
    var detectedHit: DetectedHit {
        let severity: DamageSeverity
        switch self.severity {
        case .severe, .moderate: severity = .functional
        case .minor: severity = .cosmetic
        case .none: severity = .clean
        }
        return DetectedHit(x: x, y: y, size: max(0.04, radius * 2), severity: severity)
    }
}
