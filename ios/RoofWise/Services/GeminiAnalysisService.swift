import Foundation
import UIKit
import SwiftUI

/// Gemini 2.5 Flash Vision integration via the Rork toolkit proxy.
/// Requests are sent to the OpenAI-compatible chat completions endpoint and
/// authenticated with `EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY`.
struct GeminiAnalysisService {
    private let toolkitURL: String
    private let secret: String
    private static let model = "google/gemini-2.5-flash"
    /// Markers below this normalized confidence (0.0-1.0) are dropped after parsing.
    /// Default-safe: markers with missing/zero confidence are KEPT (treated as 1.0).
    static let MIN_CONFIDENCE_THRESHOLD: Double = 0.40

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
              "type": "hail_strike|crack|missing_shingle|wind_crease|granule_loss|other",
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

        Mark only visible damage locations. Do NOT generate random or evenly spaced markers. If no damage is clearly visible, return "damage_markers": []. Coordinates are normalized from top-left.
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
            return Self.parseResponse(data) ?? AnalysisResult(findings: [], markers: [], failed: true)
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
        print("[Gemini] \u{2705} Using Rork toolkit proxy (\(Self.model)) — image \(Int(image.size.width))x\(Int(image.size.height)) slope=\(slope.rawValue) mode=\(mode.rawValue)")

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

        Return STRICT JSON only (no markdown), with this schema:
        {
          "analyzed": true|false,
          "shingle_type": { "type": "3-tab asphalt|architectural asphalt|luxury asphalt|wood shake|wood shingle|metal standing seam|metal shingle|clay tile|concrete tile|slate|synthetic slate|composite|rolled roofing|TPO|EPDM|unknown", "confidence": 0-100, "note": "<short evidence>" },
          "findings": [
            { "label": "hail_damage|granule_loss|missing_shingles|wind_creasing|blistering|cracking_splitting|flashing_damage|algae_moss|bruising|structural_sagging", "detected": true|false, "severity": "none|minor|moderate|severe", "confidence": 0-100, "count": <int>, "note": "<short evidence>" }
          ],
          "damage_markers": [
            { "type": "hail_strike|crack|granule_loss|missing_shingle|wind_crease|blister|flashing|algae|other", "x": 0.0-1.0, "y": 0.0-1.0, "radius": 0.0-1.0, "severity": "minor|moderate|severe", "confidence": 0-100, "note": "<short pixel evidence>" }
          ]
        }

        Coordinates MUST be normalized fractions of the image: x = (pixel_x / image_width), y = (pixel_y / image_height). 0.0 = left/top, 1.0 = right/bottom, top-left origin. (x,y) is the CENTER of the feature; radius is roughly half the feature size relative to the shorter image edge. NEVER return pixel values. NEVER return values outside [0, 1]. Measure coordinates against THIS image as you see it (do not rotate).

        Include all 10 damage categories in `findings` (set detected=false for ones not present). Mark each visible hail strike individually. If the image is NOT a roof (grass, sky, indoors, person, vehicle), set analyzed=false, return empty `damage_markers`, and add a finding with label="no_roof_detected".

        HALLUCINATION GUARDRAIL (apply after detection, before finalizing response): Sanity-check your hail markers specifically. Wind, wear, missing, granule, bruise, fracture, exposed mat, and lichen detection rules above are unchanged. For hail damage only: Real hail damage is random and clustered. Some areas of a roof get hit, others don't. The spatial distribution is uneven by nature. If your hail markers form an evenly-spaced grid, a repeating pattern, or cover every visible shingle uniformly, you are pattern-matching the shingle texture rather than seeing real impacts. In that case, return an empty hail array for this photo. Better to under-detect hail than to hallucinate a grid. Hail impacts typically appear as: round 1/4 to 2 inch spots with granule loss exposing the dark mat; visible bruises that deform the shingle surface; fracture lines radiating from an impact point; sharply circular discolorations distinct from normal granule variation. If you can't identify those specific characteristics, mark zero hail. For each hail marker you DO return, include in the existing evidence/description field a 1-sentence specific observation (e.g. "exposed mat 3/4 inch with granule scatter at 10 o'clock corner"). Generic "hail impact" descriptions indicate uncertainty - when your evidence is generic, lower the confidence value.
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
                print("[Gemini] \u{2705} parsed: \(parsed.findings.count) findings, \(parsed.markers.count) markers")
                return parsed
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
        // --- Anti-hallucination filters (additive, default-safe) ---
        let rawCounts = countsByType(markers)
        let originalCount = markers.count
        let confidenceFiltered: [DamageMarker] = markers.filter { m in
            // Default-safe: missing/zero confidence is treated as 1.0 (kept).
            if m.confidence == 0 { return true }
            return (Double(m.confidence) / 100.0) >= MIN_CONFIDENCE_THRESHOLD
        }
        let keptCount = confidenceFiltered.count
        print("[GeminiAnalysisService] Confidence filter: kept \(keptCount) of \(originalCount) markers (threshold \(MIN_CONFIDENCE_THRESHOLD))")
        let filteredCounts = countsByType(confidenceFiltered)
        // Hail-only grid check
        var finalMarkers = confidenceFiltered
        var hailGridDiscarded = false
        let hailMarkers = confidenceFiltered.filter { $0.type == .hailStrike }
        if hailMarkers.count > 6 {
            var distances: [Double] = []
            distances.reserveCapacity(hailMarkers.count * (hailMarkers.count - 1) / 2)
            for i in 0..<hailMarkers.count {
                for j in (i + 1)..<hailMarkers.count {
                    let dx = Double(hailMarkers[i].x - hailMarkers[j].x)
                    let dy = Double(hailMarkers[i].y - hailMarkers[j].y)
                    distances.append((dx * dx + dy * dy).squareRoot())
                }
            }
            let mean = distances.reduce(0, +) / Double(distances.count)
            let variance = distances.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(distances.count)
            let stddev = variance.squareRoot()
            let evenness = mean > 0 ? stddev / mean : 1.0
            if evenness < 0.20 {
                print("[GeminiAnalysisService] Hail grid detected (n=\(hailMarkers.count), evenness=\(evenness)) - discarding hail markers only")
                finalMarkers = confidenceFiltered.filter { $0.type != .hailStrike }
                hailGridDiscarded = true
            }
        }
        markers = finalMarkers
        print("[GeminiAnalysisService] Raw: \(rawCounts) After confidence filter (>=0.4): \(filteredCounts) Hail grid discarded: \(hailGridDiscarded)")
        // --- end anti-hallucination filters ---
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

    private static func countsByType(_ markers: [DamageMarker]) -> [String: Int] {
        var dict: [String: Int] = [:]
        for m in markers { dict[m.type.rawValue, default: 0] += 1 }
        return dict
    }

    private static func markerFromDict(_ dict: [String: Any]) -> DamageMarker? {
        let typeRaw = (dict["type"] as? String) ?? "other"
        let type = DamageMarkerType(rawValue: typeRaw) ?? .other
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
