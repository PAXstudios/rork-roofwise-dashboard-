import Foundation
import UIKit
import SwiftUI

/// Multimodal roof-damage analysis via the Rork toolkit proxy.
/// Requests are sent to the OpenAI-compatible chat completions endpoint and
/// authenticated with `EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY`.
struct GeminiAnalysisService {
    private let toolkitURL: String
    private let secret: String
    private let geminiAPIKey: String
    private static let model = "google/gemini-2.5-flash"
    private static let directGeminiModel = "gemini-2.5-flash"
    private static let fallbackModels: [String] = [
        "anthropic/claude-haiku-4.5",
        "alibaba/qwen3-vl-instruct"
    ]

    init() {
        self.toolkitURL = Config.EXPO_PUBLIC_TOOLKIT_URL
        self.secret = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY
        self.geminiAPIKey = Config.EXPO_PUBLIC_GEMINI_API_KEY
    }

    private var chatCompletionsURL: URL? {
        URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions")
    }

    private var directGeminiURL: URL? {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.directGeminiModel):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: geminiAPIKey)]
        return components?.url
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
        /// Structured Phase 8 category confidence snapshot from Gemini.
        var confidenceSnapshot: AIDamageConfidenceSnapshot = .empty
        var confidenceAvg: Double { confidenceSnapshot.confidenceAvg }
        /// Literal error message surfaced from the upstream Gemini / toolkit
        /// response (e.g. the `error.message` field) when `failed == true`.
        /// Callers (QuickInspectionView, SlopeCaptureView) present this as an
        /// alert so the inspector sees the actual reason instead of a generic
        /// 'something went wrong'. nil on success.
        var errorMessage: String? = nil
    }

    /// Thrown by callers that want a structured failure carrying the literal
    /// upstream Gemini error message.
    struct AnalysisError: LocalizedError {
        let message: String
        let statusCode: Int?
        var errorDescription: String? { message }
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

        Mark only visible damage locations. A marker is valid only when its center sits on visible pixel evidence: dark circular bruising, exposed mat, displaced granules, a crack, a missing/lifted/torn shingle edge, exposed fiberglass mat, or a wind crease. Shingle seams, tab boundaries, clean granule texture, shadows, and repeating rows are NOT damage. Do NOT generate random, evenly spaced, grid-like, or per-shingle markers. Include shingle damage beyond hail: shingle_bruise, exposed_mat, lifted_shingle, torn_shingle, missing_shingle, crack, wind_crease, granule_loss, and hail_strike. If no damage is clearly visible, return "damage_markers": []. Coordinates are normalized from top-left.
        """

        guard let req = liveVisionRequest(systemPrompt: prompt,
                                          userText: "Analyse this roof photo.",
                                          base64JPEG: base64,
                                          temperature: 0.05,
                                          timeout: 30) else {
            return AnalysisResult(findings: [], markers: [], failed: true)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                Self.logHTTPFailure(prefix: "[Gemini Live]", statusCode: http.statusCode, data: data)
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
        print("[VisionAI] Starting roof damage analysis — image \(Int(image.size.width))x\(Int(image.size.height)) slope=\(slope.rawValue) mode=\(mode.rawValue) provider=\(providerLabel)")

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

        USER-SPECIFIC CALIBRATION:
        \(LocalLearningEngine.shared.promptHints())

        Identify the roof covering and any visible damage. Be conservative — only flag damage you can actually see in the pixels. Empty arrays are correct when nothing is visible.

        CRITICAL LOCALIZATION RULES:
        - Every marker center must land on the actual damaged pixel, not the center of a shingle, not a grid cell, and not an approximate region.
        - Do NOT mark every shingle, every tab, every seam, or every stain. Repeating rows/columns of markers are invalid and must be returned as an empty marker list instead.
        - Hail markers require visible circular/oval impact evidence: bruising, crushed granules, exposed mat, pitting, or dark impact ring.
        - Shingle damage markers must include missing tabs, lifted/torn shingle edges, punctures, cracks, exposed mat, wind creases, shingle bruises, or granule-loss clusters. Do not ignore these.
        - For every marker, the note must name the local pixel evidence directly under the marker center.
        - If the photo is too blurry or low-resolution to localize a spot, skip that marker instead of guessing.

        Return STRICT JSON only (no markdown), with this schema:
        {
          "analyzed": true|false,
          "shingle_type": { "type": "3-tab asphalt|architectural asphalt|luxury asphalt|wood shake|wood shingle|metal standing seam|metal shingle|clay tile|concrete tile|slate|synthetic slate|composite|rolled roofing|TPO|EPDM|unknown", "confidence": 0-100, "note": "<short evidence>" },
          "categories": [
            { "kind": "hail|wind|wear|missing", "count": <int>, "confidence": 0.0-1.0, "severity": "minor|moderate|severe" }
          ],
          "confidence_avg": 0.0-1.0,
          "findings": [
            { "label": "hail_damage|shingle_bruise|exposed_mat|granule_loss|missing_shingles|lifted_shingle|torn_shingle|wind_creasing|blistering|cracking_splitting|flashing_damage|algae_moss|bruising|structural_sagging", "detected": true|false, "severity": "none|minor|moderate|severe", "confidence": 0-100, "count": <int>, "note": "<short evidence>" }
          ],
          "damage_markers": [
            { "type": "hail_strike|shingle_bruise|exposed_mat|crack|granule_loss|missing_shingle|lifted_shingle|torn_shingle|wind_crease|blister|flashing|algae|other", "x": 0.0-1.0, "y": 0.0-1.0, "width": 0.0-1.0, "height": 0.0-1.0, "radius": 0.0-1.0, "severity": "minor|moderate|severe", "confidence": 0-100, "note": "<short pixel evidence visible exactly at x/y>" }
          ]
        }

        Coordinates MUST be normalized fractions of the image: x = (pixel_x / image_width), y = (pixel_y / image_height). 0.0 = left/top, 1.0 = right/bottom, top-left origin. (x,y) is the CENTER of the feature; width/height/radius describe only that damaged feature, not the entire shingle. NEVER return pixel values. NEVER return values outside [0, 1]. Measure coordinates against THIS image as you see it (do not rotate).

        Include all listed damage categories in `findings` (set detected=false for ones not present), including shingle_bruise, exposed_mat, lifted_shingle, and torn_shingle. Always include exactly four rollup `categories` entries: hail, wind, wear, missing. `confidence` and `confidence_avg` MUST be normalized floats from 0.0 to 1.0, not percentages. Mark each visible hail strike and each visible shingle defect individually only when exact pixel evidence is present. If the image is NOT a roof (grass, sky, indoors, person, vehicle), set analyzed=false, return empty `damage_markers`, and add a finding with label="no_roof_detected".
        """

        guard let req = liveVisionRequest(systemPrompt: prompt,
                                          userText: "Analyse this high-resolution, contrast-enhanced roof photo. Return only strict JSON and only evidence-backed markers.",
                                          base64JPEG: base64,
                                          temperature: 0.05,
                                          timeout: 60) else {
            return AnalysisResult(findings: Self.failureFinding(reason: "AI service is not configured. Add the Rork toolkit credentials or Gemini key, then tap retry. Mock damage markers are disabled."),
                                  markers: [],
                                  failed: true)
        }

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            print("[Gemini] \u{23F1}\u{FE0F} round-trip \(String(format: "%.2f", Date().timeIntervalSince(started)))s, \(data.count) bytes")
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let upstream = Self.logHTTPFailure(prefix: "[GeminiAnalysisService]", statusCode: http.statusCode, data: data)
                let message = upstream ?? "AI service returned HTTP \(http.statusCode)."
                return AnalysisResult(
                    findings: Self.failureFinding(reason: message),
                    markers: [],
                    failed: true,
                    errorMessage: message
                )
            }
            // Log raw response (truncated) so we can debug what Gemini actually returned.
            if let raw = String(data: data, encoding: .utf8) {
                print("[Gemini] \u{1F4E5} raw response (\(data.count) bytes): \(raw.prefix(1200))")
            }
            if let parsed = Self.parseResponse(data) {
                let refined = parsed.refiningMarkers(in: image).applyingLocalCalibration()
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
            let msg = "Network error during AI analysis: \(error.localizedDescription)"
            print("[GeminiAnalysisService] \u{274C} Request failed: \(error.localizedDescription)")
            return AnalysisResult(
                findings: Self.failureFinding(reason: msg),
                markers: [],
                failed: true,
                errorMessage: msg
            )
        }
    }

    // MARK: - Request body

    private var hasLiveVisionCredentials: Bool {
        (!secret.isEmpty && chatCompletionsURL != nil) || (!geminiAPIKey.isEmpty && directGeminiURL != nil)
    }

    private var providerLabel: String {
        if !secret.isEmpty, chatCompletionsURL != nil { return "Rork toolkit \(Self.model)" }
        if !geminiAPIKey.isEmpty, directGeminiURL != nil { return "Google Gemini \(Self.directGeminiModel)" }
        return "not configured"
    }

    private func liveVisionRequest(systemPrompt: String,
                                   userText: String,
                                   base64JPEG: String,
                                   temperature: Double,
                                   timeout: TimeInterval) -> URLRequest? {
        if !secret.isEmpty, let url = chatCompletionsURL {
            let body = Self.chatCompletionBody(systemPrompt: systemPrompt,
                                               userText: userText,
                                               base64JPEG: base64JPEG,
                                               temperature: temperature)
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = timeout
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return req
        }

        if !geminiAPIKey.isEmpty, let url = directGeminiURL {
            let body = Self.directGeminiBody(systemPrompt: systemPrompt,
                                             userText: userText,
                                             base64JPEG: base64JPEG,
                                             temperature: temperature)
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = timeout
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return req
        }

        return nil
    }

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
                ],
                "google": [
                    "thinkingLevel": "low"
                ]
            ],
            "response_format": ["type": "json_object"],
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

    private static func directGeminiBody(systemPrompt: String,
                                         userText: String,
                                         base64JPEG: String,
                                         temperature: Double) -> [String: Any] {
        return [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": userText],
                    ["inline_data": [
                        "mime_type": "image/jpeg",
                        "data": base64JPEG
                    ]]
                ]
            ]],
            "generationConfig": [
                "temperature": temperature,
                "responseMimeType": "application/json"
            ]
        ]
    }

    // MARK: - Parsing

    /// Unconditionally prints the FULL response body (status + body) on a
    /// single tagged print line so it shows up in Rork's log panel, and
    /// returns the parsed upstream `error.message` string (Gemini /
    /// toolkit / OpenAI-style) when present, else the raw body.
    @discardableResult
    private static func logHTTPFailure(prefix: String, statusCode: Int, data: Data) -> String? {
        let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body, \(data.count) bytes>"
        print("[GeminiAnalysisService] \u{274C} HTTP \(statusCode) FULL RESPONSE BODY: \(body)")
        // Try to parse a literal upstream error.message string.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = json["error"] as? [String: Any], let m = err["message"] as? String, !m.isEmpty {
                return m
            }
            if let m = json["message"] as? String, !m.isEmpty { return m }
        }
        return body.isEmpty ? nil : body
    }

    private static func parseResponse(_ data: Data) -> AnalysisResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let payload: [String: Any]
        if looksLikeAnalysisPayload(root) {
            payload = root
        } else {
            guard let text = responseText(from: root),
                  let parsedPayload = payloadFromText(text) else {
                return nil
            }
            payload = parsedPayload
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
        let confidenceSnapshot = confidenceSnapshot(from: payload)
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
        let rawMarkers = (payload["damage_markers"] as? [[String: Any]])
            ?? (payload["markers"] as? [[String: Any]])
            ?? (payload["detections"] as? [[String: Any]])
        if !noRoofFlag, let rawMarkers {
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
                              shingleTypeNote: shingleTypeNote,
                              confidenceSnapshot: confidenceSnapshot,
                              errorMessage: nil)
    }

    private static func confidenceSnapshot(from payload: [String: Any]) -> AIDamageConfidenceSnapshot {
        let rawCategories = payload["categories"] as? [[String: Any]] ?? []
        let categories: [AIDamageCategoryConfidence] = AIDamageCategoryKind.allCases.map { kind in
            if let dict = rawCategories.first(where: { ($0["kind"] as? String) == kind.rawValue }) {
                return categoryConfidence(kind: kind, dict: dict)
            }
            return AIDamageCategoryConfidence(kind: kind, count: 0, confidence: 0, severity: .minor)
        }
        let avg = normalizedConfidence(payload["confidence_avg"]) ?? (categories.isEmpty ? 0 : categories.reduce(0) { $0 + $1.confidence } / Double(categories.count))
        return AIDamageConfidenceSnapshot(categories: categories, confidenceAvg: avg)
    }

    private static func categoryConfidence(kind: AIDamageCategoryKind,
                                           dict: [String: Any]) -> AIDamageCategoryConfidence {
        let count = (dict["count"] as? Int) ?? (dict["count"] as? NSNumber)?.intValue ?? 0
        let confidence = normalizedConfidence(dict["confidence"]) ?? 0
        let severityRaw = (dict["severity"] as? String) ?? "minor"
        let severity = AIDamageCategorySeverity(rawValue: severityRaw) ?? .minor
        return AIDamageCategoryConfidence(kind: kind,
                                          count: max(0, count),
                                          confidence: confidence,
                                          severity: severity)
    }

    private static func normalizedConfidence(_ raw: Any?) -> Double? {
        let value = (raw as? Double) ?? (raw as? NSNumber)?.doubleValue
        guard let value else { return nil }
        return max(0, min(1, value > 1 ? value / 100 : value))
    }

    private static func mockAnalysisResult() -> AnalysisResult {
        let markers = InspectionMock.damageMarkers
        let hailCount = markers.filter { $0.type.isHailImpact }.count
        let windCount = markers.filter { $0.type.isShingleDamage }.count
        let wearCount = markers.filter { $0.type == .granuleLoss || $0.type == .blister || $0.type == .algae }.count
        let missingCount = markers.filter { $0.type == .missingShingle }.count
        let categories = [
            AIDamageCategoryConfidence(kind: .hail, count: hailCount, confidence: 0.82, severity: .moderate),
            AIDamageCategoryConfidence(kind: .wind, count: windCount, confidence: 0.74, severity: .minor),
            AIDamageCategoryConfidence(kind: .wear, count: wearCount, confidence: 0.68, severity: .minor),
            AIDamageCategoryConfidence(kind: .missing, count: missingCount, confidence: 0.91, severity: .minor)
        ]
        let snapshot = AIDamageConfidenceSnapshot(categories: categories)
        let findings: [InspectionFinding] = [
            InspectionFinding(label: "shingle_type",
                              display: "Shingle Type",
                              value: "Architectural Asphalt - mock training roof surface",
                              confidence: 86,
                              icon: "square.stack.3d.down.right.fill",
                              tint: Theme.sky,
                              detected: true,
                              severity: .none),
            InspectionFinding(label: "bruising",
                              display: "Bruising",
                              value: "Mock hail bruising confidence sample",
                              confidence: 82,
                              icon: "circle.hexagongrid.fill",
                              tint: Theme.ember,
                              detected: true,
                              severity: .moderate),
            InspectionFinding(label: "wind_creasing",
                              display: "Wind Creasing",
                              value: "Mock edge lift confidence sample",
                              confidence: 74,
                              icon: "wind",
                              tint: Theme.amber,
                              detected: true,
                              severity: .minor)
        ]
        return AnalysisResult(findings: findings,
                              markers: markers,
                              failed: false,
                              usedMock: true,
                              confidenceSnapshot: snapshot)
    }

    private static func looksLikeAnalysisPayload(_ root: [String: Any]) -> Bool {
        root["damage_markers"] != nil || root["markers"] != nil || root["detections"] != nil || root["findings"] != nil || root["categories"] != nil
    }

    private static func responseText(from root: [String: Any]) -> String? {
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any] {
            if let s = message["content"] as? String { return s }
            if let parts = message["content"] as? [[String: Any]] {
                return parts.compactMap { ($0["text"] as? String) ?? ($0["content"] as? String) }.joined()
            }
        }
        if let candidates = root["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }

    private static func payloadFromText(_ text: String) -> [String: Any]? {
        let cleaned = jsonObjectSubstring(from: stripCodeFences(text))
        guard let jsonData = cleaned.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    }

    /// Strip ```json ... ``` or ``` ... ``` fences if Gemini wraps despite responseMimeType.
    private static func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
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

    private static func jsonObjectSubstring(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else {
            return trimmed
        }
        return String(trimmed[start...end])
    }

    private static func markerFromDict(_ dict: [String: Any]) -> DamageMarker? {
        let typeRaw = string(dict["type"])
            ?? string(dict["kind"])
            ?? string(dict["category"])
            ?? string(dict["damage_type"])
            ?? "other"
        let type = DamageMarkerType(rawValue: typeRaw) ?? DamageMarkerType.alias(for: typeRaw)

        let bbox = bboxValues(from: dict)
        let xVal = number(dict["x"])
            ?? number(dict["center_x"])
            ?? number(dict["cx"])
            ?? bbox?.centerX
        let yVal = number(dict["y"])
            ?? number(dict["center_y"])
            ?? number(dict["cy"])
            ?? bbox?.centerY
        guard let xVal, let yVal else { return nil }

        let explicitRadius = number(dict["radius"])
        let bboxW = number(dict["width"]) ?? number(dict["w"]) ?? bbox?.width
        let bboxH = number(dict["height"]) ?? number(dict["h"]) ?? bbox?.height
        let radius: Double = {
            if let r = explicitRadius { return r }
            if let w = bboxW, let h = bboxH { return max(w, h) / 2 }
            return 0.026
        }()
        let severityRaw = (string(dict["severity"]) ?? "moderate").capitalized
        let severity = FindingSeverity(rawValue: severityRaw) ?? .moderate
        let note = string(dict["note"]) ?? string(dict["evidence"]) ?? type.display
        let confidence: Int = {
            if let d = number(dict["confidence"]) ?? number(dict["score"]) {
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

    private static func bboxValues(from dict: [String: Any]) -> (centerX: Double, centerY: Double, width: Double, height: Double)? {
        if let values = dict["bbox"] as? [Any], values.count >= 4,
           let x = number(values[0]),
           let y = number(values[1]),
           let w = number(values[2]),
           let h = number(values[3]) {
            return (x + w / 2, y + h / 2, w, h)
        }
        let rawBox = (dict["bbox"] as? [String: Any])
            ?? (dict["bounding_box"] as? [String: Any])
            ?? (dict["box"] as? [String: Any])
        guard let rawBox else { return nil }
        let x = number(rawBox["x"]) ?? number(rawBox["left"]) ?? number(rawBox["x_min"])
        let y = number(rawBox["y"]) ?? number(rawBox["top"]) ?? number(rawBox["y_min"])
        let w = number(rawBox["width"]) ?? number(rawBox["w"])
        let h = number(rawBox["height"]) ?? number(rawBox["h"])
        if let x, let y, let w, let h {
            return (x + w / 2, y + h / 2, w, h)
        }
        if let xMin = number(rawBox["x_min"]),
           let yMin = number(rawBox["y_min"]),
           let xMax = number(rawBox["x_max"]),
           let yMax = number(rawBox["y_max"]) {
            let w = max(0, xMax - xMin)
            let h = max(0, yMax - yMin)
            return (xMin + w / 2, yMin + h / 2, w, h)
        }
        return nil
    }

    private static func number(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? CGFloat { return Double(value) }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func string(_ raw: Any?) -> String? {
        (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        case "shingle_bruise":
            return ("Shingle Bruise", "circle.lefthalf.filled", "Localized bruise in shingle mat")
        case "exposed_mat":
            return ("Exposed Mat", "viewfinder.circle.fill", "Fiberglass mat exposed")
        case "granule_loss":
            return ("Granule Loss", "circle.dotted", "Granule displacement")
        case "missing_shingles":
            return ("Missing Shingles", "square.dashed", "Tabs missing")
        case "lifted_shingle":
            return ("Lifted Shingle", "square.stack.3d.up.fill", "Lifted or unsealed tab edge")
        case "torn_shingle":
            return ("Torn Shingle", "rectangle.split.3x1.fill", "Torn shingle tab")
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
                                                    shingleTypeNote: shingleTypeNote,
                                                    confidenceSnapshot: confidenceSnapshot,
                                                    errorMessage: errorMessage)
    }

    func applyingLocalCalibration() -> GeminiAnalysisService.AnalysisResult {
        GeminiAnalysisService.AnalysisResult(findings: findings,
                                             markers: markers,
                                             failed: failed,
                                             usedMock: usedMock,
                                             noRoofDetected: noRoofDetected,
                                             shingleType: shingleType,
                                             shingleTypeConfidence: shingleTypeConfidence,
                                             shingleTypeNote: shingleTypeNote,
                                             confidenceSnapshot: LocalLearningEngine.shared.adjustedSnapshot(confidenceSnapshot),
                                             errorMessage: errorMessage)
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
