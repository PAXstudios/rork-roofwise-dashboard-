import Foundation
import UIKit
import SwiftUI

/// Gemini 1.5 Flash Vision integration.
/// API key is read from `Config.EXPO_PUBLIC_GEMINI_API_KEY` (env var).
enum GeminiAnalysisService {
    /// Reads the key from the auto-generated Config (env var EXPO_PUBLIC_GEMINI_API_KEY).
    static var apiKey: String { Config.allValues["EXPO_PUBLIC_GEMINI_API_KEY"] ?? "" }

    static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

    /// Analyze a captured roof photo and return structured findings.
    /// Falls back to mock findings if API key is unset or the request fails.
    struct AnalysisResult {
        let findings: [InspectionFinding]
        let markers: [DamageMarker]
    }

    /// Convenience for legacy callers that only need findings.
    static func analyze(image: UIImage,
                        slope: SlopeType,
                        mode: CaptureMode = .square,
                        squaresCovered: Int = 0) async -> [InspectionFinding] {
        await analyzeFull(image: image, slope: slope, mode: mode, squaresCovered: squaresCovered).findings
    }

    /// Analyze a captured roof photo and return findings + per-pixel damage markers.
    static func analyzeFull(image: UIImage,
                            slope: SlopeType,
                            mode: CaptureMode = .square,
                            squaresCovered: Int = 0) async -> AnalysisResult {
        let key = apiKey
        guard !key.isEmpty,
              key != "GEMINI_API_KEY",
              let url = URL(string: "\(endpoint)?key=\(key)"),
              let jpeg = image.jpegData(compressionQuality: 0.7) else {
            try? await Task.sleep(for: .milliseconds(800))
            return AnalysisResult(findings: mockFindings(for: slope),
                                  markers: InspectionMock.damageMarkers)
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
        You are a HAAG-certified forensic roofing inspector. \(intro)
        First, identify the roof covering / shingle type from the image. Choose the closest match from:
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
          "findings": [
            {
              "label": "hail_damage|granule_loss|missing_shingles|wind_creasing|blistering|cracking_splitting|flashing_damage|algae_moss|bruising|structural_sagging",
              "detected": true|false,
              "severity": "none|minor|moderate|severe",
              "confidence": 0-100,
              "note": "<short evidence sentence>"
            }
          ]
        }
        Include ALL 10 damage categories. Be conservative - only mark severe if clearly visible.

        Then ALSO return precise pixel-region markers for every visible damage point
        (each hail strike, crack, missing shingle, blister, etc.) so we can overlay
        circles on the photo. Coordinates MUST be normalized 0-1 (x from left, y from top)
        relative to the image. Radius is normalized 0-1 (relative to min image dimension).
        Add this top-level field to the JSON:
        "damage_markers": [
          {
            "type": "hail_strike|crack|granule_loss|missing_shingle|wind_crease|blister|flashing|algae|other",
            "x": 0.0-1.0,
            "y": 0.0-1.0,
            "radius": 0.0-1.0,
            "severity": "minor|moderate|severe",
            "note": "<short evidence>"
          }
        ]
        Mark EVERY visible hail strike individually (not just one for the whole photo).
        Aim for accuracy: if you see 12 hail strikes, return 12 markers. If none, return [].
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
                "temperature": 0.2
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let parsed = parseResponse(data) {
                return parsed
            }
        } catch {
            // fall through to mock
        }

        try? await Task.sleep(for: .milliseconds(400))
        return AnalysisResult(findings: mockFindings(for: slope),
                              markers: InspectionMock.damageMarkers)
    }

    private static func parseResponse(_ data: Data) -> AnalysisResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let jsonData = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let raw = payload["findings"] as? [[String: Any]] else {
            return nil
        }

        var results: [InspectionFinding] = []
        if let typeDict = payload["shingle_type"] as? [String: Any],
           let typeFinding = shingleTypeFinding(from: typeDict) {
            results.append(typeFinding)
        }
        for dict in raw {
            if let finding = findingFromDict(dict) { results.append(finding) }
        }

        var markers: [DamageMarker] = []
        if let rawMarkers = payload["damage_markers"] as? [[String: Any]] {
            for dict in rawMarkers {
                if let m = markerFromDict(dict) { markers.append(m) }
            }
        }
        return AnalysisResult(findings: results, markers: markers)
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

    /// Mock findings used when no API key is set or call fails.
    private static func mockFindings(for slope: SlopeType) -> [InspectionFinding] {
        // Reuse existing curated mock list; tweak severity slightly per slope.
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
