import Foundation
import UIKit
import SwiftUI

/// Gemini 2.5 Flash Vision integration.
/// API key is read from `Config.EXPO_PUBLIC_GEMINI_API_KEY` (env var).
enum GeminiAnalysisService {
    /// Reads the key from the auto-generated Config (env var EXPO_PUBLIC_GEMINI_API_KEY).
    static var apiKey: String { Config.allValues["EXPO_PUBLIC_GEMINI_API_KEY"] ?? "" }

    /// gemini-2.5-flash is significantly better at fine-detail vision (hail strikes,
    /// granule displacement, soft-metal dings) than 1.5-flash.
    static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    /// Result returned from `analyzeFull`.
    /// `failed == true` means the API call could not be completed successfully —
    /// callers should NOT treat the photo as analyzed and should NOT render the
    /// (empty) markers as if they were real AI detections.
    struct AnalysisResult {
        let findings: [InspectionFinding]
        let markers: [DamageMarker]
        var failed: Bool = false
        var usedMock: Bool = false
    }

    /// Convenience for legacy callers that only need findings.
    static func analyze(image: UIImage,
                        slope: SlopeType,
                        mode: CaptureMode = .square,
                        squaresCovered: Int = 0) async -> [InspectionFinding] {
        await analyzeFull(image: image, slope: slope, mode: mode, squaresCovered: squaresCovered).findings
    }

    /// Analyze a captured roof photo and return findings + per-pixel damage markers.
    /// On API failure returns `failed: true` with EMPTY markers (no fake mock data
    /// gets painted onto real photos).
    static func analyzeFull(image: UIImage,
                            slope: SlopeType,
                            mode: CaptureMode = .square,
                            squaresCovered: Int = 0) async -> AnalysisResult {
        let key = apiKey
        guard !key.isEmpty,
              key != "GEMINI_API_KEY",
              let url = URL(string: "\(endpoint)?key=\(key)") else {
            // No key configured -> dev mode: surface mock so the demo flow still works,
            // but flag it as mock so the UI can label it.
            try? await Task.sleep(for: .milliseconds(600))
            return AnalysisResult(findings: mockFindings(for: slope),
                                  markers: InspectionMock.damageMarkers,
                                  failed: false,
                                  usedMock: true)
        }

        // Resize for upload: cap at 2048px on the long edge. Gemini downsamples
        // server-side anyway; sending massive JPEGs only slows the request.
        let prepared = resizeForUpload(image, maxEdge: 2048)
        guard let jpeg = prepared.jpegData(compressionQuality: 0.85) else {
            return AnalysisResult(findings: failureFinding(reason: "Could not encode photo for analysis."),
                                  markers: [],
                                  failed: true)
        }

        let coverageNote: String = {
            switch squaresCovered {
            case 0: return " Note: less than 1 full 10x10 roofing square was documented in this capture; report findings only for the visible area."
            case 1: return " Note: approximately 1 roofing square (100 sq ft) of coverage was documented."
            default: return " Note: approximately \(squaresCovered) roofing squares (~\(squaresCovered * 100) sq ft) of coverage were documented."
            }
        }()

        let intro: String = {
            switch mode {
            case .singleShingle:
                return "Analyze this shingle on \(slope.rawValue). Focus on the single shingle in frame and report damage to that specific shingle." + coverageNote
            case .square:
                return "Analyze this photo of \(slope.rawValue) (a ~10x10 ft / 100 sq ft roofing square) and identify roof damage across the area." + coverageNote
            }
        }()

        let prompt = """
        You are a certified forensic roof inspector applying HAAG Engineering standards.
        \(intro)

        CRITICAL ACCURACY RULES:
          1. Look at the ACTUAL pixels in this image. Do NOT invent or hallucinate damage.
          2. If a region is undamaged, do NOT place a marker there.
          3. Every marker you return MUST correspond to a visible pixel feature you can describe.
          4. Hail strikes look like circular dark spots / mat fractures with displaced granules,
             often with a slight shine or color contrast. They are usually 1/4" to 2" across.
          5. If you are not confident a feature is damage, OMIT it. Empty arrays are correct
             when the shingle is undamaged.

        Analyze this image for ALL of the following:
          • Hail damage — count INDIVIDUAL strikes separately on (a) shingles/roof field and
            (b) metal components (vents, pipe jacks, flashing, drip edge, gutters, downspouts,
            turbines, exhaust caps, satellite mounts). Hail on soft metal is one of the strongest
            HAAG indicators of a hail event.
          • Bruising — soft spots / mat fractures under the granules (press-test signature).
          • Spatter marks — oxidation/dirt-line spatter on metal that confirms hail directionality.
          • Granule loss — note distinct granule-loss AREAS (each erosion patch is a marker).
          • Wind damage — creasing at the nail line, lifted/folded tabs, missing tabs.
          • Cracking / splitting, blistering, flashing damage, algae/moss, structural sagging.

        First, identify the roof covering / shingle type. Choose the closest match from:
        "3-tab asphalt", "architectural asphalt" (a.k.a. dimensional/laminated), "luxury asphalt",
        "wood shake", "wood shingle", "metal standing seam", "metal shingle", "clay tile",
        "concrete tile", "slate", "synthetic slate", "composite", "rolled roofing", "TPO", "EPDM", "unknown".

        Return STRICT JSON only, no markdown, with this schema:
        {
          "shingle_type": {
            "type": "<one of the values above>",
            "confidence": 0-100,
            "note": "<short visual evidence: tab shape, exposure, profile, material cues>"
          },
          "hail_summary": {
            "strikes_on_shingles": <int>,
            "strikes_on_metal": <int>,
            "affected_metal_components": ["vent"|"flashing"|"drip_edge"|"gutter"|"downspout"|"pipe_boot"|"ridge_cap"|"valley_metal"|"skylight"|"other"],
            "directionality": "<e.g. 'predominantly south-facing' or 'random'>",
            "spatter_observed": true|false
          },
          "findings": [
            {
              "label": "hail_damage|granule_loss|missing_shingles|wind_creasing|blistering|cracking_splitting|flashing_damage|algae_moss|bruising|structural_sagging",
              "detected": true|false,
              "severity": "none|minor|moderate|severe",
              "confidence": 0-100,
              "affected_components": ["shingle"|"flashing"|"drip_edge"|"gutter"|"downspout"|"vent"|"pipe_boot"|"ridge_cap"|"valley_metal"|"skylight"],
              "count": <int, 0 if not applicable>,
              "note": "<short evidence sentence citing HAAG indicators>"
            }
          ],
          "damage_markers": [
            {
              "type": "hail_strike|crack|granule_loss|missing_shingle|wind_crease|blister|flashing|algae|other",
              "surface": "shingle|metal|other",
              "x": 0.0-1.0,
              "y": 0.0-1.0,
              "radius": 0.0-1.0,
              "severity": "minor|moderate|severe",
              "note": "<short evidence describing the actual pixel feature you see>"
            }
          ]
        }
        Include ALL 10 damage categories in `findings`. Be conservative — only mark `detected: true`
        when clearly visible. Set `severity: "severe"` only when the evidence is unambiguous.

        Coordinates MUST be normalized 0-1 (x from left, y from top) relative to the image.
        Radius is normalized 0-1 (relative to min image dimension).

        Mark EVERY visible hail strike INDIVIDUALLY — do not group them.
        If the image shows NO damage, return "damage_markers": [] (empty). Do NOT fabricate markers.
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg",
                                     "data": jpeg.base64EncodedString()]]
                ]
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.1,
                "topP": 0.95
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let bodyStr = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
                print("[Gemini] HTTP \(http.statusCode): \(bodyStr)")
                return AnalysisResult(
                    findings: failureFinding(reason: "AI service returned HTTP \(http.statusCode). Tap retry."),
                    markers: [],
                    failed: true
                )
            }
            if let parsed = parseResponse(data) {
                return parsed
            }
            let raw = String(data: data, encoding: .utf8)?.prefix(800) ?? ""
            print("[Gemini] Could not parse response JSON. Raw: \(raw)")
            return AnalysisResult(
                findings: failureFinding(reason: "AI returned an unreadable response. Tap retry."),
                markers: [],
                failed: true
            )
        } catch {
            print("[Gemini] Request failed: \(error.localizedDescription)")
            return AnalysisResult(
                findings: failureFinding(reason: "Network error during AI analysis. Tap retry."),
                markers: [],
                failed: true
            )
        }
    }

    // MARK: - Image preparation

    private static func resizeForUpload(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Parsing

    private static func parseResponse(_ data: Data) -> AnalysisResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            return nil
        }

        let cleaned = stripCodeFences(text)
        guard let jsonData = cleaned.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        var results: [InspectionFinding] = []
        if let typeDict = payload["shingle_type"] as? [String: Any],
           let typeFinding = shingleTypeFinding(from: typeDict) {
            results.append(typeFinding)
        }
        if let raw = payload["findings"] as? [[String: Any]] {
            for dict in raw {
                if let finding = findingFromDict(dict) { results.append(finding) }
            }
        }

        var markers: [DamageMarker] = []
        if let rawMarkers = payload["damage_markers"] as? [[String: Any]] {
            for dict in rawMarkers {
                if let m = markerFromDict(dict) { markers.append(m) }
            }
        }
        return AnalysisResult(findings: results, markers: markers, failed: false)
    }

    /// Strip ```json ... ``` or ``` ... ``` fences if Gemini wraps despite responseMimeType.
    private static func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // remove first fence line (``` or ```json)
            if let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            }
            if s.hasSuffix("```") {
                s = String(s.dropLast(3))
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    private static func markerFromDict(_ dict: [String: Any]) -> DamageMarker? {
        let typeRaw = (dict["type"] as? String) ?? "other"
        let type = DamageMarkerType(rawValue: typeRaw) ?? .other
        guard let xVal = (dict["x"] as? Double) ?? (dict["x"] as? NSNumber)?.doubleValue,
              let yVal = (dict["y"] as? Double) ?? (dict["y"] as? NSNumber)?.doubleValue else {
            return nil
        }
        let radius = ((dict["radius"] as? Double) ?? (dict["radius"] as? NSNumber)?.doubleValue) ?? 0.04
        let severityRaw = (dict["severity"] as? String ?? "moderate").capitalized
        let severity = FindingSeverity(rawValue: severityRaw) ?? .moderate
        let note = dict["note"] as? String ?? type.display
        let clamp: (Double) -> CGFloat = { CGFloat(max(0, min(1, $0))) }
        return DamageMarker(x: clamp(xVal),
                            y: clamp(yVal),
                            radius: clamp(radius),
                            type: type,
                            severity: severity,
                            note: note)
    }

    private static func shingleTypeFinding(from dict: [String: Any]) -> InspectionFinding? {
        let type = (dict["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !type.isEmpty else { return nil }
        let confidence = max(0, min(100, dict["confidence"] as? Int ?? 0))
        let note = dict["note"] as? String ?? ""
        let pretty = type.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return InspectionFinding(
            label: "shingle_type",
            display: "Shingle Type",
            value: note.isEmpty ? pretty : "\(pretty) — \(note)",
            confidence: confidence,
            icon: "square.stack.3d.down.right.fill",
            tint: Theme.sky,
            detected: true,
            severity: .none
        )
    }

    private static func findingFromDict(_ dict: [String: Any]) -> InspectionFinding? {
        guard let label = dict["label"] as? String else { return nil }
        let detected = dict["detected"] as? Bool ?? false
        let confidence = dict["confidence"] as? Int ?? 0
        let severityRaw = (dict["severity"] as? String ?? "none").capitalized
        let severity = FindingSeverity(rawValue: severityRaw) ?? .none
        let note = dict["note"] as? String ?? ""
        let meta = displayMeta(for: label)
        return InspectionFinding(
            label: label,
            display: meta.display,
            value: note.isEmpty ? meta.fallback : note,
            confidence: max(0, min(100, confidence)),
            icon: meta.icon,
            tint: severity == .none ? Theme.mint : severity.color,
            detected: detected,
            severity: severity
        )
    }

    private static func displayMeta(for label: String) -> (display: String, icon: String, fallback: String) {
        switch label {
        case "hail_damage", "bruising":
            return ("Bruising", "circle.hexagongrid.fill", "Hail bruising on mat")
        case "granule_loss":
            return ("Granule Loss", "circle.dotted", "Granule displacement")
        case "missing_shingles":
            return ("Missing Shingles", "square.dashed", "Tabs missing")
        case "wind_creasing":
            return ("Wind Creasing", "wind", "Creases at nail line")
        case "blistering":
            return ("Blistering", "circle.grid.cross.fill", "Raised pockets in mat")
        case "cracking_splitting":
            return ("Cracking / Splitting", "bolt.horizontal.fill", "Hairline splits")
        case "flashing_damage":
            return ("Flashing Damage", "square.stack.3d.up.slash.fill", "Lifted step flashing")
        case "algae_moss":
            return ("Algae / Moss", "leaf.fill", "Biological staining")
        case "structural_sagging":
            return ("Structural Sagging", "arrow.down.right.and.arrow.up.left", "Decking deflection")
        default:
            return (label.replacingOccurrences(of: "_", with: " ").capitalized,
                    "questionmark.circle", "")
        }
    }

    /// Surfaced to the user when the AI call fails. We deliberately do NOT return
    /// fake mock damage markers here — that was masking real failures and painting
    /// fake circles on real photos.
    private static func failureFinding(reason: String) -> [InspectionFinding] {
        [InspectionFinding(
            label: "ai_unavailable",
            display: "Analysis Unavailable",
            value: reason,
            confidence: 0,
            icon: "exclamationmark.triangle.fill",
            tint: Theme.amber,
            detected: false,
            severity: .none
        )]
    }

    /// Mock findings used ONLY when no API key is set (dev / demo mode).
    private static func mockFindings(for slope: SlopeType) -> [InspectionFinding] {
        let mockType = InspectionFinding(
            label: "shingle_type",
            display: "Shingle Type",
            value: "Architectural Asphalt — laminated dimensional tabs, ~5\" exposure",
            confidence: 92,
            icon: "square.stack.3d.down.right.fill",
            tint: Theme.sky,
            detected: true,
            severity: .none
        )
        let base = InspectionMock.findings
        return [mockType] + base.map { f in
            let bumped = (slope == .ridgeLine && f.label == "wind_creasing")
            return InspectionFinding(
                label: f.label,
                display: f.display,
                value: f.value,
                confidence: min(99, f.confidence + (bumped ? 4 : Int.random(in: -3...3))),
                icon: f.icon,
                tint: f.tint,
                detected: f.detected,
                severity: f.severity
            )
        }
    }
}
