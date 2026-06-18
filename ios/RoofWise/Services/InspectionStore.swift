import Foundation
import CoreLocation
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
        scheduleGeocode(for: inspection.job.reportId)
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

    // MARK: Geocoded location

    /// Persist a resolved coordinate onto the inspection's job (used on creation
    /// and by the one-time backfill migration).
    func setCoordinate(_ coord: CLLocationCoordinate2D, for reportId: String) {
        guard let idx = inspections.firstIndex(where: { $0.job.reportId == reportId }) else { return }
        inspections[idx].job.latitude = coord.latitude
        inspections[idx].job.longitude = coord.longitude
        save()
    }

    /// Geocode a newly-created inspection's address in the background
    /// (cache-first) and persist the coordinate.
    private func scheduleGeocode(for reportId: String) {
        Task { [weak self] in
            guard let self,
                  let insp = self.inspection(with: reportId),
                  insp.job.coordinate == nil else { return }
            if let coord = await CoordinateBackfillService.shared.resolve(address: insp.job.propertyAddress) {
                self.setCoordinate(coord, for: reportId)
            }
        }
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

    /// Phase 9: write transient AI findings onto the matching slope. Findings
    /// are not persisted (Slope.aiFindings is excluded from Codable) so this
    /// is in-memory only. Safe to call from any analyze completion path.
    func setAIFindings(_ findings: [InspectionFinding],
                       for reportId: String,
                       orientation: String) {
        guard let idx = inspections.firstIndex(where: { $0.job.reportId == reportId }) else { return }
        var insp = inspections[idx]
        guard let sIdx = insp.slopes.firstIndex(where: { $0.orientation == orientation }) else { return }
        insp.slopes[sIdx].aiFindings = findings
        inspections[idx] = insp
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
        let s = insp.summary
        let verdict: String
        if s.roofFullReplacementRecommended { verdict = "Full replacement recommended" }
        else if s.roofPartialReplacementRecommended { verdict = "Partial replacement recommended" }
        else if s.roofRepairsRecommended { verdict = "Repairs recommended" }
        else { verdict = "No storm-related damage" }
        ActivityStore.shared.log(.decisionComputed,
                                 summary: verdict,
                                 detail: s.replacementSlopesList.isEmpty ? nil
                                     : "Replace: \(s.replacementSlopesList)",
                                 on: insp)
    }

    // MARK: RoofWise Decision Engine (Stages 4-6) — flag-gated

    /// Runs the multi-stage RoofWise Decision Engine for an inspection using the
    /// per-photo detection results captured by `DetectionPipelineService`.
    ///
    /// This is the ON-path for `APIKeys.useRoofWiseDecisionEngine`. The
    /// deterministic `DecisionEngine` (invoked by `recomputeSummary`) remains
    /// the source of truth for the editable Slope/Summary contract and the PDF
    /// report; the RoofWise engine layers HAAG-grade narratives on top. When
    /// the flag is OFF this method short-circuits to `nil` and nothing changes.
    ///
    /// Stage 6 needs per-photo detections that only exist in the capture flow,
    /// so this is intentionally separate from the synchronous `recomputeSummary`
    /// (which has no detection data) — keeping that path byte-identical to today.
    func evaluateWithRoofWiseEngine(
        reportId: String,
        photoResultsBySlope: [UUID: [(photoId: UUID, result: PhotoDetectionResult)]],
        slopeMetadata: [UUID: (orientation: String, areaSquares: Double, material: HaagRoofMaterial)],
        inspectionMetadata: InspectionMetadata
    ) async -> InspectionDecisionResult? {
        guard APIKeys.useRoofWiseDecisionEngine else { return nil }
        guard inspection(with: reportId) != nil else { return nil }
        do {
            return try await DetectionPipelineService.shared.aggregateAndDecide(
                inspectionId: UUID(),
                photoResultsBySlope: photoResultsBySlope,
                slopeMetadata: slopeMetadata,
                inspectionMetadata: inspectionMetadata
            )
        } catch {
            print("[RoofWiseEngine] \u{274C} evaluation failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Storm event auto-population

    /// Fills `event` on the inspection identified by `reportId` from the
    /// supplied storm match. Skips fields that are already populated unless
    /// `overwrite` is true. Always dedupes `weather_sources`.
    @discardableResult
    func applyStormMatch(_ storm: NoaaStormEvent,
                         to reportId: String,
                         overwrite: Bool = false) -> Bool {
        guard let idx = inspections.firstIndex(where: { $0.job.reportId == reportId }) else {
            return false
        }
        var insp = inspections[idx]
        var event = insp.event
        let alreadyHasData = event.hasHail || event.hasWind
            || event.hailMaxSizeIn != nil || event.windMaxGustMph != nil
            || event.eventDate != nil
        if alreadyHasData && !overwrite { return false }

        if event.eventDate == nil || overwrite {
            event.eventDate = storm.eventDate
        }
        switch storm.eventType {
        case .hail:
            event.hasHail = true
            if let mag = storm.magnitudeIn,
               overwrite || (event.hailMaxSizeIn ?? 0) < mag {
                event.hailMaxSizeIn = mag
            }
        case .wind, .tornado:
            event.hasWind = true
            if let mph = storm.windMph.map(Double.init),
               overwrite || (event.windMaxGustMph ?? 0) < mph {
                event.windMaxGustMph = mph
            }
        }
        if !event.weatherSources.contains(storm.source) {
            event.weatherSources.append(storm.source)
        }
        insp.event = event
        recomputeSummary(&insp)
        inspections[idx] = insp
        save()
        let mag: String
        if let h = storm.magnitudeIn { mag = String(format: "%.2f\" hail", h) }
        else if let w = storm.windMph { mag = "\(w) mph wind" }
        else { mag = storm.eventType.rawValue }
        ActivityStore.shared.log(.stormMatched,
                                 summary: "Storm match: \(mag)",
                                 detail: storm.eventDate.formatted(date: .abbreviated, time: .omitted)
                                     + " \u{00B7} " + storm.source,
                                 on: insp)
        return true
    }

    /// Geocodes the inspection's property address and pulls NOAA storm events
    /// near it, auto-populating `event` if a hail or wind match falls within
    /// 30 days of the inspection_date. No-op if `event` is already populated.
    func autoPopulateEvent(for reportId: String,
                           geocoder: GeocodingService = GeocodingServiceFactory.shared,
                           stormService: StormEventsServicing = StormEventsServiceFactory.shared) async {
        guard let insp = inspection(with: reportId) else { return }
        let event = insp.event
        let alreadyHasData = event.hasHail || event.hasWind
            || event.hailMaxSizeIn != nil || event.windMaxGustMph != nil
            || event.eventDate != nil
        if alreadyHasData { return }

        let address = insp.job.propertyAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }

        let coord: CLLocationCoordinate2D? = (try? await geocoder.geocode(address)) ?? nil
        guard let coord else { return }

        let events: [NoaaStormEvent]
        do {
            events = try await stormService.events(near: coord, radiusMi: 5, sinceMonthsBack: 24)
        } catch {
            return
        }
        guard !events.isEmpty else { return }

        let inspectionDate = insp.job.inspectionDate
        let window: TimeInterval = 30 * 24 * 60 * 60
        let inWindow = events.filter {
            abs($0.eventDate.timeIntervalSince(inspectionDate)) <= window
        }
        guard !inWindow.isEmpty else { return }

        let bestHail = inWindow
            .filter { $0.eventType == .hail }
            .min(by: {
                abs($0.eventDate.timeIntervalSince(inspectionDate)) <
                    abs($1.eventDate.timeIntervalSince(inspectionDate))
            })
        let bestWind = inWindow
            .filter { $0.eventType == .wind || $0.eventType == .tornado }
            .min(by: {
                abs($0.eventDate.timeIntervalSince(inspectionDate)) <
                    abs($1.eventDate.timeIntervalSince(inspectionDate))
            })

        await MainActor.run {
            if let h = bestHail { _ = self.applyStormMatch(h, to: reportId) }
            if let w = bestWind { _ = self.applyStormMatch(w, to: reportId) }
        }
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
