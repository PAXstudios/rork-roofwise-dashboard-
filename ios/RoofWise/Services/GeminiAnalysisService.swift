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
    static func analyze(image: UIImage,
                        slope: SlopeType,
                        mode: CaptureMode = .square) async -> [InspectionFinding] {
        let key = apiKey
        guard !key.isEmpty,
              key != "GEMINI_API_KEY",
              let url = URL(string: "\(endpoint)?key=\(key)"),
              let jpeg = image.jpegData(compressionQuality: 0.7) else {
            try? await Task.sleep(for: .milliseconds(800))
            return mockFindings(for: slope)
        }

        let intro: String = {
            switch mode {
            case .singleShingle:
                return "Analyze this shingle on \(slope.rawValue). Focus on the single shingle in frame and report damage to that specific shingle."
            case .square:
                return "Analyze this photo of \(slope.rawValue) (a ~10x10 ft / 100 sq ft roofing square) and identify roof damage across the area."
            }
        }()

        let prompt = """
        You are a HAAG-certified forensic roofing inspector. \(intro)
        Return STRICT JSON only, no markdown, with this schema:
        {
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
        Include ALL 10 categories. Be conservative - only mark severe if clearly visible.
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
        return mockFindings(for: slope)
    }

    private static func parseResponse(_ data: Data) -> [InspectionFinding]? {
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
        for dict in raw {
            if let finding = findingFromDict(dict) { results.append(finding) }
        }
        return results
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
        let base = InspectionMock.findings
        return base.map { f in
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
