import Foundation
import UIKit
import SwiftUI

/// Multimodal roof-damage analysis via the Rork toolkit proxy.
/// Requests are sent to the OpenAI-compatible chat completions endpoint and
/// authenticated with `EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY`.
struct GeminiAnalysisService {
    private let toolkitURL: String
    private let secret: String
    private static let model = "google/gemini-3-flash"
    private static let fallbackModels: [String] = [
        "anthropic/claude-haiku-4.5",
        "alibaba/qwen3-vl-instruct"
    ]

    init() {
        self.toolkitURL = Config.EXPO_PUBLIC_TOOLKIT_URL
        self.secret = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY
    }

    private var chatCompletionsURL: URL? {
        URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions")
    }

    /// Result returned from `analyzeFull`.
    /// `failed == true` means the API call could not be completed successfully —
    /// callers should NOT treat the photo as analyzed and should NOT render the
    /// (empty) markers as if they were real AI detections.
    struct AnalysisResult {
        let findings: [InspectionFinding]
        let markers: [DamageMarker]
        var failed: Bool = false
        var usedMock: Bool = false
        /// True when Gemini reports the photo does NOT show a roof / shingles /
        /// roofing material at all (e.g. grass, sky, indoors, a person). Callers
        /// should treat this as "nothing to analyze" and avoid surfacing fake
        /// damage findings.
        var noRoofDetected: Bool = false
        /// Roof material / covering classified by Gemini (e.g. "3-tab asphalt",
        /// "architectural asphalt", "metal standing seam"). `nil` when the model
        /// did not classify the surface.
        var shingleType: String? = nil
        /// Confidence (0-100) for `shingleType`.
        var shingleTypeConfidence: Int = 0
        /// AI evidence note for the shingle type classification.
        var shingleTypeNote: String? = nil
    }

    /// Convenience for legacy callers that only need findings.
    static func analyze(image: UIImage,
                        slope: SlopeType,
                        mode: CaptureMode = .square,
                        squaresCovered: Int = 0) async -> [InspectionFinding] {
        await GeminiAnalysisService().analyzeFull(image: image, slope: slope, mode: mode, squaresCovered: squaresCovered).findings
    }

    /// Static convenience wrappers so existing callers keep compiling.
    static func analyzeFull(image: UIImage,
                            slope: SlopeType,
                            mode: CaptureMode = .square,
                            squaresCovered: Int = 0) async -> AnalysisResult {
        await GeminiAnalysisService().analyzeFull(image: image, slope: slope, mode: mode, squaresCovered: squaresCovered)
    }

    static func analyzeLiveDamage(image: UIImage) async -> AnalysisResult {
        await GeminiAnalysisService().analyzeLiveDamage(image: image)
    }

    /// Lightweight live camera damage check. Reuses the same parsing pipeline, but
    /// prompts Gemini to return only roof-gated damage markers for the current frame.
    func analyzeLiveDamage(image: UIImage) async -> AnalysisResult {
        guard !secret.isEmpty, let url = chatCompletionsURL else {
            return AnalysisResult(findings: [], markers: [], failed: true)
        }

        guard let base64 = ImageResize.encodedJPEGBase64(from: image, profile: .live) else {
            return AnalysisResult(findings: [], markers: [], failed: true)
        }

        let prompt = """
        You are inspecting a live camera frame from a roof inspection app.
        Return STRICT JSON only with this schema:
        {
          "analyzed": true|false,
          "shingle_type": {
            "type": "3-tab asphalt|architectural asphalt|luxury asphalt|wood shake|wood shingle|metal standing seam|metal shingle|clay tile|concrete tile|slate|synthetic slate|composite|rolled roofing|TPO|EPDM|unknown",
            "confidence": 0-100,
            "note": "short visual evidence"
          },
          "shingle_type_confidence": 0-100,
          "findings": [
            { "label": "no_roof_detected", "detected": false, "severity": "none", "confidence": 0-100, "note": "No roof or shingles visible in this photo" }
          ],
          "damage_markers": [
            {
              "type": "hail_strike|shingle_bruise|exposed_mat|crack|granule_loss|missing_shingle|lifted_shingle|torn_shingle|wind_crease|other",
              "x": 0.0-1.0,
              "y": 0.0-1.0,
              "width": 0.0-1.0,
              "height": 0.0-1.0,
              "radius": 0.0-1.0,
              "severity": "minor|moderate|severe",
              "confidence": 0-100,
              "note": "short visible pixel evidence"
            }
          ]
        }

        Coordinates x, y, width, height are NORMALIZED FRACTIONS of the image
        (0.0 = left/top edge, 1.0 = right/bottom edge), TOP-LEFT origin. (x, y)
        is the CENTER of the bounding box; width/height are the bbox size as
        fractions of the image. NEVER return pixel values. NEVER return values
        > 1.0. Coordinates must be measured against THIS image as you see it,
        not rotated.

        CRITICAL: If the image does NOT clearly show a roof surface, asphalt shingles, tile, metal panels, or any roofing material — for example if it shows grass, sky, ground, indoors, a person, a vehicle, or any non-roof scene — you MUST set analyzed=false, return an empty damage_markers array, and add a finding with label="no_roof_detected" and note="No roof or shingles visible in this photo". Do not fabricate damage findings on non-roof images.

        Mark only visible damage locations. A marker is valid only when its center sits on visible pixel evidence: dark circular bruising, exposed mat, displaced granules, a crack, missing/lifted/torn shingle edge, or flashing defect. Shingle seams, tab boundaries, clean granule texture, shadows, and repeating rows are NOT damage. Do NOT generate random, evenly spaced, grid-like, or per-shingle markers. Include shingle damage beyond hail: lifted tabs, torn tabs, missing tabs, cracks, exposed mat, and wind creases. If no damage is clearly visible, return "damage_markers": []. Coordinates are normalized from top-left.
        """

        let body = Self.chatCompletionBody(systemPrompt: prompt,
                                            userText: "Analyse this roof photo.",
                                            base64JPEG: base64,
                                            temperature: 0.05)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return AnalysisResult(findings: [], markers: [], failed: true)
            }
            guard let parsed = Self.parseResponse(data) else {
                return AnalysisResult(findings: [], markers: [], failed: true)
            }
            return parsed.refiningMarkers(in: image)
        } catch {
            return AnalysisResult(findings: [], markers: [], failed: true)
        }
    }

    /// Analyze a captured roof photo and return findings + per-pixel damage markers.
    /// On API failure returns `failed: true` with EMPTY markers (no fake mock data
    /// gets painted onto real photos).
    func analyzeFull(image: UIImage,
                     slope: SlopeType,
                     mode: CaptureMode = .square,
                     squaresCovered: Int = 0) async -> AnalysisResult {
        guard !secret.isEmpty, let url = chatCompletionsURL else {
            return AnalysisResult(findings: Self.failureFinding(reason: "Rork toolkit not configured. Tap retry."),
                                  markers: [],
                                  failed: true)
        }
        print("[VisionAI] \u{2705} Using Rork toolkit proxy (\(Self.model), fallbacks: \(Self.fallbackModels.joined(separator: ", "))) — image \(Int(image.size.width))x\(Int(image.size.height)) slope=\(slope.rawValue) mode=\(mode.rawValue)")

        guard let base64 = ImageResize.encodedJPEGBase64(from: image, profile: .full) else {
            return AnalysisResult(findings: Self.failureFinding(reason: "Could not encode photo for analysis."),
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
        You are a forensic roof inspector (HAAG standards). \(intro)

        Identify the roof covering and any visible damage. Be conservative — only flag damage you can actually see in the pixels. Empty arrays are correct when nothing is visible.

        CRITICAL LOCALIZATION RULES:
        - Every marker center must land on the actual damaged pixel, not the center of a shingle, not a grid cell, and not an approximate region.
        - Do NOT mark every shingle, every tab, or every stain. Repeating rows/columns of markers are invalid.
        - Hail markers require visible circular/oval impact evidence: bruising, crushed granules, exposed mat, pitting, or dark impact ring.
        - Shingle damage markers must include missing tabs, lifted/torn shingle edges, punctures, cracks, exposed mat, or wind creases. Do not ignore these.
        - If the photo is too blurry or low-resolution to localize a spot, skip that marker instead of guessing.

        Return STRICT JSON only (no markdown), with this schema:
        {
          "analyzed": true|false,
          "shingle_type": { "type": "3-tab asphalt|architectural asphalt|luxury asphalt|wood shake|wood shingle|metal standing seam|metal shingle|clay tile|concrete tile|slate|synthetic slate|composite|rolled roofing|TPO|EPDM|unknown", "confidence": 0-100, "note": "<short evidence>" },
          "findings": [
            { "label": "hail_damage|granule_loss|missing_shingles|wind_creasing|blistering|cracking_splitting|flashing_damage|algae_moss|bruising|structural_sagging", "detected": true|false, "severity": "none|minor|moderate|severe", "confidence": 0-100, "count": <int>, "note": "<short evidence>" }
          ],
          "damage_markers": [
            { "type": "hail_strike|shingle_bruise|exposed_mat|crack|granule_loss|missing_shingle|lifted_shingle|torn_shingle|wind_crease|blister|flashing|algae|other", "x": 0.0-1.0, "y": 0.0-1.0, "width": 0.0-1.0, "height": 0.0-1.0, "radius": 0.0-1.0, "severity": "minor|moderate|severe", "confidence": 0-100, "note": "<short pixel evidence visible exactly at x/y>" }
          ]
        }

        Coordinates MUST be normalized fractions of the image: x = (pixel_x / image_width), y = (pixel_y / image_height). 0.0 = left/top, 1.0 = right/bottom, top-left origin. (x,y) is the CENTER of the feature; width/height/radius describe only that damaged feature, not the entire shingle. NEVER return pixel values. NEVER return values outside [0, 1]. Measure coordinates against THIS image as you see it (do not rotate).

        Include all 10 damage categories in `findings` (set detected=false for ones not present). Mark each visible hail strike and each visible shingle defect individually only when exact pixel evidence is present. If the image is NOT a roof (grass, sky, indoors, person, vehicle), set analyzed=false, return empty `damage_markers`, and add a finding with label="no_roof_detected".
        """

        let body = Self.chatCompletionBody(systemPrompt: prompt,
                                            userText: "Analyse this roof photo.",
                                            base64JPEG: base64,
                                            temperature: 0.1)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            print("[Gemini] \u{23F1}\u{FE0F} round-trip \(String(format: "%.2f", Date().timeIntervalSince(started)))s, \(data.count) bytes")
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let bodyStr = String(data: data, encoding: .utf8)?.prefix(800) ?? ""
                print("[Gemini] \u{274C} HTTP \(http.statusCode): \(bodyStr)")
                return AnalysisResult(
                    findings: Self.failureFinding(reason: "AI service returned HTTP \(http.statusCode). Tap retry."),
                    markers: [],
                    failed: true
                )
            }
            // Log raw response (truncated) so we can debug what Gemini actually returned.
            if let raw = String(data: data, encoding: .utf8) {
                print("[Gemini] \u{1F4E5} raw response (\(data.count) bytes): \(raw.prefix(1200))")
            }
            if let parsed = Self.parseResponse(data) {
                let refined = parsed.refiningMarkers(in: image)
                print("[VisionAI] \u{2705} parsed: \(parsed.findings.count) findings, \(parsed.markers.count) markers → \(refined.markers.count) pixel-refined markers")
                return refined
            }
            print("[Gemini] \u{274C} Could not parse response JSON.")
            return AnalysisResult(
                findings: Self.failureFinding(reason: "AI returned an unreadable response. Tap retry."),
                markers: [],
                failed: true
            )
        } catch {
            print("[Gemini] \u{274C} Request failed: \(error.localizedDescription)")
            return AnalysisResult(
                findings: Self.failureFinding(reason: "Network error during AI analysis. Tap retry."),
                markers: [],
                failed: true
            )
        }
    }

    // MARK: - Request body

    private static func chatCompletionBody(systemPrompt: String,
                                            userText: String,
                                            base64JPEG: String,
                                            temperature: Double) -> [String: Any] {
        return [
            "model": Self.model,
            "temperature": temperature,
            "providerOptions": [
                "gateway": [
                    "models": Self.fallbackModels
                ]
            ],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url", "image_url": [
                        "url": "data:image/jpeg;base64,\(base64JPEG)"
                    ]]
                ]]
            ]
        ]
    }

    // MARK: - Parsing

    private static func parseResponse(_ data: Data) -> AnalysisResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // OpenAI-compatible response shape:
        // { "choices": [ { "message": { "content": "<json string>" } } ] }
        let text: String? = {
            if let choices = root["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any] {
                if let s = message["content"] as? String { return s }
                if let parts = message["content"] as? [[String: Any]] {
                    return parts.compactMap { $0["text"] as? String }.joined()
                }
            }
            // Fallback: legacy Gemini native shape, just in case.
            if let candidates = root["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let s = parts.first?["text"] as? String {
                return s
            }
            return nil
        }()
        guard let text else { return nil }

        let cleaned = stripCodeFences(text)
        guard let jsonData = cleaned.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        // Calibration log: surface Gemini's pixels-per-inch estimate so we can
        // tune marker size and physical-size reasoning over time. We deliberately
        // do NOT use this value for any sizing decisions yet — just log it.
        if let scale = payload["shingleScaleEstimate"] as? [String: Any] {
            let ppi = (scale["pixelsPerInch"] as? Double)
                ?? (scale["pixelsPerInch"] as? NSNumber)?.doubleValue
                ?? 0
            let confidence = (scale["confidence"] as? Int)
                ?? (scale["confidence"] as? NSNumber)?.intValue
                ?? 0
            let basis = (scale["basis"] as? String) ?? ""
            print("[Gemini] \u{1F4CF} shingleScaleEstimate: \(String(format: "%.1f", ppi)) px/in (confidence \(confidence)%) — \(basis)")
        } else {
            print("[Gemini] \u{1F4CF} shingleScaleEstimate: not provided")
        }

        var results: [InspectionFinding] = []
        var shingleTypeName: String? = nil
        var shingleTypeConfidence: Int = 0
        var shingleTypeNote: String? = nil
        if let typeDict = payload["shingle_type"] as? [String: Any] {
            let rawType = (typeDict["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !rawType.isEmpty {
                shingleTypeName = rawType.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                shingleTypeConfidence = max(0, min(100, (typeDict["confidence"] as? Int)
                    ?? (typeDict["confidence"] as? NSNumber)?.intValue ?? 0))
                let note = (typeDict["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                shingleTypeNote = note.isEmpty ? nil : note
            }
            if let typeFinding = shingleTypeFinding(from: typeDict) {
                results.append(typeFinding)
            }
        }
        // Top-level shingle_type_confidence override, if Gemini provided it.
        if let topConf = (payload["shingle_type_confidence"] as? Int)
            ?? (payload["shingle_type_confidence"] as? NSNumber)?.intValue,
           topConf > shingleTypeConfidence {
            shingleTypeConfidence = max(0, min(100, topConf))
        }
        var noRoofFlag = false
        if let analyzed = payload["analyzed"] as? Bool, analyzed == false {
            noRoofFlag = true
        }
        if let raw = payload["findings"] as? [[String: Any]] {
            for dict in raw {
                if let lbl = dict["label"] as? String, lbl == "no_roof_detected" {
                    noRoofFlag = true
                    let note = (dict["note"] as? String) ?? "No roof or shingles visible in this photo"
                    results.append(InspectionFinding(
                        label: "no_roof_detected",
                        display: "No Roof Detected",
                        value: note,
                        confidence: (dict["confidence"] as? Int) ?? 95,
                        icon: "questionmark.app.dashed",
                        tint: Theme.amber,
                        detected: false,
                        severity: .none
                    ))
                    continue
                }
                if let finding = findingFromDict(dict) { results.append(finding) }
            }
        }

        var markers: [DamageMarker] = []
        if !noRoofFlag, let rawMarkers = payload["damage_markers"] as? [[String: Any]] {
            for dict in rawMarkers {
                if let m = markerFromDict(dict) { markers.append(m) }
            }
        }
        if noRoofFlag {
            print("[Gemini] \u{26A0}\u{FE0F} no_roof_detected — image does not show a roof; suppressing markers.")
        }
        return AnalysisResult(findings: results,
                              markers: markers,
                              failed: false,
                              noRoofDetected: noRoofFlag,
                              shingleType: shingleTypeName,
                              shingleTypeConfidence: shingleTypeConfidence,
                              shingleTypeNote: shingleTypeNote)
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
        let typeRaw = ((dict["type"] as? String) ?? "other").trimmingCharacters(in: .whitespacesAndNewlines)
        let type = DamageMarkerType(rawValue: typeRaw) ?? DamageMarkerType.alias(for: typeRaw)
        guard let xVal = (dict["x"] as? Double) ?? (dict["x"] as? NSNumber)?.doubleValue,
              let yVal = (dict["y"] as? Double) ?? (dict["y"] as? NSNumber)?.doubleValue else {
            return nil
        }
        // Prefer explicit radius. Otherwise derive from bbox width/height if Gemini
        // returned a bounding box (newer schema), so single-strike pins land at the right size.
        let explicitRadius = (dict["radius"] as? Double) ?? (dict["radius"] as? NSNumber)?.doubleValue
        let bboxW = (dict["width"] as? Double) ?? (dict["width"] as? NSNumber)?.doubleValue
        let bboxH = (dict["height"] as? Double) ?? (dict["height"] as? NSNumber)?.doubleValue
        let radius: Double = {
            if let r = explicitRadius { return r }
            if let w = bboxW, let h = bboxH { return max(w, h) / 2 }
            return 0.04
        }()
        let severityRaw = (dict["severity"] as? String ?? "moderate").capitalized
        let severity = FindingSeverity(rawValue: severityRaw) ?? .moderate
        let note = dict["note"] as? String ?? type.display
        let confidence: Int = {
            if let i = dict["confidence"] as? Int { return max(0, min(100, i)) }
            if let d = (dict["confidence"] as? Double) ?? (dict["confidence"] as? NSNumber)?.doubleValue {
                // Accept either 0-1 or 0-100
                let v = d <= 1.0 ? d * 100 : d
                return max(0, min(100, Int(v.rounded())))
            }
            return 0
        }()
        let clamp: (Double) -> CGFloat = { CGFloat(max(0, min(1, $0))) }
        return DamageMarker(x: clamp(xVal),
                            y: clamp(yVal),
                            radius: clamp(radius),
                            type: type,
                            severity: severity,
                            note: note,
                            confidence: confidence)
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

}

private extension GeminiAnalysisService.AnalysisResult {
    /// Moves AI markers onto the nearest visible damage-like pixel cluster and
    /// suppresses grid-style hallucinations that do not have local pixel evidence.
    func refiningMarkers(in image: UIImage) -> GeminiAnalysisService.AnalysisResult {
        guard !markers.isEmpty else { return self }
        guard let refiner = DamageMarkerPixelRefiner(image: image) else { return self }
        let looksLikeGrid = DamageMarkerPixelRefiner.isLikelyUniformGrid(markers)
        let candidates: [DamageMarker] = markers.compactMap { marker in
            refiner.refined(marker: marker, requireStrongEvidence: looksLikeGrid)
        }
        let refinedMarkers = DamageMarkerPixelRefiner.deduplicated(candidates)
        return GeminiAnalysisService.AnalysisResult(findings: findings,
                                                    markers: refinedMarkers,
                                                    failed: failed,
                                                    usedMock: usedMock,
                                                    noRoofDetected: noRoofDetected,
                                                    shingleType: shingleType,
                                                    shingleTypeConfidence: shingleTypeConfidence,
                                                    shingleTypeNote: shingleTypeNote)
    }
}

private struct DamageMarkerPixelRefiner {
    private struct PixelCandidate {
        let x: Int
        let y: Int
        let score: Double
        let radius: CGFloat
    }

    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    private let data: [UInt8]

    init?(image: UIImage) {
        guard let cgImage = image.normalizedOrientation().cgImage else { return nil }
        width = cgImage.width
        height = cgImage.height
        bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &buffer,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }

    func refined(marker: DamageMarker, requireStrongEvidence: Bool) -> DamageMarker? {
        guard width > 0, height > 0 else { return marker }
        guard let candidate = bestCandidate(near: marker) else {
            return requireStrongEvidence ? nil : marker
        }

        let minimumScore = requireStrongEvidence ? 0.145 : evidenceThreshold(for: marker.type)
        guard candidate.score >= minimumScore else {
            return requireStrongEvidence ? nil : marker
        }

        return DamageMarker(x: CGFloat(candidate.x) / CGFloat(max(width - 1, 1)),
                            y: CGFloat(candidate.y) / CGFloat(max(height - 1, 1)),
                            radius: max(0.008, min(0.035, candidate.radius)),
                            type: marker.type,
                            severity: marker.severity,
                            note: marker.note,
                            confidence: marker.confidence)
    }

    private func bestCandidate(near marker: DamageMarker) -> PixelCandidate? {
        let centerX = Int(max(0, min(1, marker.x)) * CGFloat(max(width - 1, 1)))
        let centerY = Int(max(0, min(1, marker.y)) * CGFloat(max(height - 1, 1)))
        let normalizedSearch = max(0.025, min(0.075, marker.radius * 2.25))
        let baseRadius = max(16, min(104, Int(CGFloat(min(width, height)) * normalizedSearch)))
        let step = max(1, baseRadius / 24)
        var best: PixelCandidate?

        for y in stride(from: max(2, centerY - baseRadius), through: min(height - 3, centerY + baseRadius), by: step) {
            for x in stride(from: max(2, centerX - baseRadius), through: min(width - 3, centerX + baseRadius), by: step) {
                let distance = hypot(Double(x - centerX), Double(y - centerY)) / Double(max(baseRadius, 1))
                guard distance <= 1.0 else { continue }
                let score = damageEvidenceScore(x: x, y: y, type: marker.type) - distance * 0.035
                if score > (best?.score ?? -.greatestFiniteMagnitude) {
                    let visualRadius = CGFloat(max(5, min(18, baseRadius / 4))) / CGFloat(min(width, height))
                    best = PixelCandidate(x: x, y: y, score: score, radius: visualRadius)
                }
            }
        }
        return best
    }

    private func damageEvidenceScore(x: Int, y: Int, type: DamageMarkerType) -> Double {
        let inner = meanLuma(centerX: x, centerY: y, radius: 3)
        let outer = meanLuma(centerX: x, centerY: y, radius: 13)
        let edge = localEdgeEnergy(x: x, y: y)
        let darkImpact = max(0, outer - inner)
        let circularDarkImpact = darkCircularEvidence(x: x, y: y, centerLuma: inner)
        let brightExposure = max(0, inner - outer)
        let lumaContrast = abs(outer - inner)

        switch type {
        case .hailStrike, .shingleBruise:
            return circularDarkImpact * 1.85 + darkImpact * 0.45 + edge * 0.28
        case .granuleLoss, .exposedMat:
            return max(darkImpact, brightExposure) * 0.95 + edge * 0.85
        case .crack, .windCrease, .liftedShingle, .tornShingle, .missingShingle:
            return lumaContrast * 0.85 + edge * 1.25
        case .flashing, .blister, .algae, .other:
            return lumaContrast * 0.85 + edge * 0.8
        }
    }

    private func evidenceThreshold(for type: DamageMarkerType) -> Double {
        switch type {
        case .hailStrike, .shingleBruise: return 0.085
        case .missingShingle, .liftedShingle, .tornShingle, .windCrease, .crack: return 0.065
        default: return 0.055
        }
    }

    private func meanLuma(centerX: Int, centerY: Int, radius: Int) -> Double {
        var total: Double = 0
        var count: Double = 0
        let minY = max(0, centerY - radius)
        let maxY = min(height - 1, centerY + radius)
        let minX = max(0, centerX - radius)
        let maxX = min(width - 1, centerX + radius)
        for y in minY...maxY {
            for x in minX...maxX {
                total += luma(x: x, y: y)
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    private func localEdgeEnergy(x: Int, y: Int) -> Double {
        let left = luma(x: max(0, x - 2), y: y)
        let right = luma(x: min(width - 1, x + 2), y: y)
        let top = luma(x: x, y: max(0, y - 2))
        let bottom = luma(x: x, y: min(height - 1, y + 2))
        return (abs(left - right) + abs(top - bottom)) / 2
    }

    private func darkCircularEvidence(x: Int, y: Int, centerLuma: Double) -> Double {
        let r = 9
        let samples = [
            luma(x: max(0, x - r), y: y),
            luma(x: min(width - 1, x + r), y: y),
            luma(x: x, y: max(0, y - r)),
            luma(x: x, y: min(height - 1, y + r))
        ]
        let directionalLift = samples.map { max(0, $0 - centerLuma) }
        let weakestDirection = directionalLift.min() ?? 0
        let averageLift = directionalLift.reduce(0, +) / Double(max(directionalLift.count, 1))
        return weakestDirection * 0.7 + averageLift * 0.3
    }

    private func luma(x: Int, y: Int) -> Double {
        let offset = y * bytesPerRow + x * 4
        guard offset + 2 < data.count else { return 0 }
        let r = Double(data[offset]) / 255
        let g = Double(data[offset + 1]) / 255
        let b = Double(data[offset + 2]) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    static func deduplicated(_ markers: [DamageMarker]) -> [DamageMarker] {
        var accepted: [DamageMarker] = []
        for marker in markers.sorted(by: { $0.confidence > $1.confidence }) {
            let minimumDistance: CGFloat = marker.type == .hailStrike || marker.type == .shingleBruise ? 0.026 : 0.018
            let isDuplicate = accepted.contains { existing in
                existing.type == marker.type && hypot(existing.x - marker.x, existing.y - marker.y) < minimumDistance
            }
            if !isDuplicate { accepted.append(marker) }
        }
        return accepted
    }

    static func isLikelyUniformGrid(_ markers: [DamageMarker]) -> Bool {
        guard markers.count >= 16 else { return false }
        let hailLike = markers.filter { $0.type == .hailStrike || $0.type == .shingleBruise }
        guard hailLike.count >= 12 else { return false }
        let xBuckets = bucketCenters(hailLike.map { Double($0.x) })
        let yBuckets = bucketCenters(hailLike.map { Double($0.y) })
        guard xBuckets.count >= 4, yBuckets.count >= 4 else { return false }
        let xRegularity = regularityScore(xBuckets)
        let yRegularity = regularityScore(yBuckets)
        let latticeCapacity = xBuckets.count * yBuckets.count
        let fill = Double(hailLike.count) / Double(max(latticeCapacity, 1))
        return xRegularity > 0.72 && yRegularity > 0.72 && fill > 0.45
    }

    private static func bucketCenters(_ values: [Double]) -> [Double] {
        let sorted = values.sorted()
        var buckets: [[Double]] = []
        for value in sorted {
            if let last = buckets.indices.last,
               let currentMean = buckets[last].isEmpty ? nil : buckets[last].reduce(0, +) / Double(buckets[last].count),
               abs(value - currentMean) < 0.035 {
                buckets[last].append(value)
            } else {
                buckets.append([value])
            }
        }
        return buckets.map { $0.reduce(0, +) / Double(max($0.count, 1)) }
    }

    private static func regularityScore(_ centers: [Double]) -> Double {
        guard centers.count >= 4 else { return 0 }
        let gaps = zip(centers.dropLast(), centers.dropFirst()).map { $1 - $0 }.filter { $0 > 0.01 }
        guard gaps.count >= 3 else { return 0 }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        guard mean > 0 else { return 0 }
        let variance = gaps.map { pow($0 - mean, 2) }.reduce(0, +) / Double(gaps.count)
        let coefficient = sqrt(variance) / mean
        return max(0, min(1, 1 - coefficient * 3))
    }
}
