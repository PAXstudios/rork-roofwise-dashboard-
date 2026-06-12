import Foundation
import UIKit
import SwiftUI

/// Errors thrown by `GeminiAnalysisService.analyzeLive(imageData:)`.
nonisolated enum LiveAnalyzeError: Error {
    case notConfigured
    case badStatus(Int)
    case unparseable
}

/// Gemini 2.5 Flash Vision integration via the Rork toolkit proxy.
/// Requests are sent to the OpenAI-compatible chat completions endpoint and
/// authenticated with `EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY`.
struct GeminiAnalysisService {
    private let toolkitURL: String
    private let secret: String
    private static let model = "google/gemini-2.5-flash"

    // MARK: - Locked damage taxonomy (13 pitch-deck categories)

    /// The 13 canonical snake_case tokens used in BOTH `findings[].label` and
    /// `damage_markers[].type`. Parity is intentional.
    static let damageCategoryTokens: [String] = [
        "hail_hits", "bruising", "granule_loss", "wind_damage", "wind_creasing",
        "blistering", "cracking", "flashing", "algae_moss", "missing_shingles",
        "splitting", "lifted", "structural_sagging"
    ]

    /// Pipe-joined enum list embedded in prompt schemas.
    private static let categoryEnum = damageCategoryTokens.joined(separator: "|")

    /// One-line distinguishing description per category so the model doesn't
    /// confuse close pairs (shared by every prompt).
    private static let categoryGuide = """
    Category definitions (use the exact snake_case token):
    - hail_hits = round 1/4-2 inch granule-loss spots from ice impact
    - bruising = soft deformed shingle surface with no surface loss
    - granule_loss = generalized loss exposing mat without a distinct impact pattern
    - wind_damage = uplift / tearing / blown-off corners, NOT creasing
    - wind_creasing = a specific crease line across a shingle from being folded back
    - blistering = raised bubble of asphalt
    - cracking = surface crack line in the shingle
    - splitting = full-thickness vertical split through the shingle
    - flashing = damaged metal flashing at penetrations/edges
    - algae_moss = dark streaks or green growth
    - missing_shingles = absent tab(s) exposing felt or deck
    - lifted = shingle tab raised but still attached
    - structural_sagging = deck deformation visible as a wave/dip
    """

    /// Per-category severity calibration so the model assigns minor/moderate/
    /// severe consistently across every prompt.
    private static let severityGuide = """
    Severity scale per category (apply consistently): hail_hits = count of impacts in a 10ft x 10ft square (minor: 1-8, moderate: 9-14, severe: 15+); bruising = % of shingles in view showing soft deformation (minor: <10%, moderate: 10-30%, severe: >30%); granule_loss = % area of exposed dark mat (minor: <10%, moderate: 10-25%, severe: >25%); wind_damage = count of torn/blown-off corners (minor: 1-2, moderate: 3-5, severe: 6+); wind_creasing = count of creased shingles (minor: 1-3, moderate: 4-8, severe: 9+); blistering = count of raised blisters per 10ft x 10ft (minor: <10, moderate: 10-30, severe: >30); cracking = count of surface cracks per 10ft x 10ft (minor: 1-5, moderate: 6-15, severe: 16+); flashing = condition of metal flashing (minor: surface rust/light separation, moderate: visible gap or partial detachment, severe: missing/torn/major separation); algae_moss = % area covered (minor: <15%, moderate: 15-40%, severe: >40%); missing_shingles = count of absent tabs/shingles (minor: 1, moderate: 2-4, severe: 5+); splitting = count of full-thickness vertical splits (minor: 1-2, moderate: 3-5, severe: 6+); lifted = count of raised tabs (minor: 1-3, moderate: 4-8, severe: 9+); structural_sagging = visible deck deformation (minor: slight wave, moderate: clear dip 1-3in, severe: dip >3in or collapse). When evidence is ambiguous or partially visible, downgrade one severity level. When the photo doesn't clearly show enough roof area to apply the count rule (e.g. close-up of a single shingle), use proportional judgment: scale the count down by the visible area.
    """

    /// Gemini-native spatial localization rules. Gemini 2.5 is trained to emit
    /// detections as `box_2d` = [ymin, xmin, ymax, xmax] normalized to 0-1000;
    /// asking for free-form x/y/radius floats is off-distribution and makes the
    /// model fall back to a degenerate evenly-spaced row of markers. Requesting
    /// box_2d gives true per-feature localization and accurate counts.
    private static let spatialGuide = """
    Localize EACH damage feature using your native 2D detection format. For every entry in damage_markers, return "box_2d": [ymin, xmin, ymax, xmax] as INTEGERS normalized to 0-1000 (top-left origin: [0,0] = top-left corner, [1000,1000] = bottom-right; the Y coordinate comes FIRST). The box must tightly enclose ONE distinct damage feature at its true location in the image.
    - Detect EVERY visible hail hit individually — one tight box per impact — and count them all, even if there are 20 or more.
    - Place each box exactly where the feature is. Real damage is irregularly scattered; do NOT output a straight row, a uniform grid, or evenly spaced boxes.
    - Do NOT fabricate boxes for features you cannot clearly see. An empty damage_markers array is correct when nothing is visible.
    - For point-like damage (hail hits, blisters) use a small tight box around the single spot; for area damage (missing shingles, flashing, algae, sagging) box the whole affected region.
    - Return up to 60 boxes. Measure every box against THIS image exactly as you see it (do not rotate).
    """

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

    /// Live AR overlay analysis. Strictly additive sibling to `analyzeFull` — same
    /// model, same auth, no responseSchema. Returns the shared `AnalysisResult`
    /// shape but only `damage_markers` are populated (no full findings list).
    static func analyzeLive(imageData: Data) async throws -> AnalysisResult {
        try await GeminiAnalysisService().analyzeLive(imageData: imageData)
    }

    /// Live mode: downsampled camera frame → conservative damage markers only.
    /// `throws` on any failure so the caller can silently skip the frame.
    func analyzeLive(imageData: Data) async throws -> AnalysisResult {
        guard !secret.isEmpty, let url = chatCompletionsURL else {
            throw LiveAnalyzeError.notConfigured
        }
        let base64 = imageData.base64EncodedString()

        // EXACT live-mode preamble, then the shared damage-detection rules
        // (coordinate normalization + roof gating) mirrored from analyze().
        let prompt = """
        You are running in LIVE mode. Return ONLY the damage_markers array. Be conservative — only mark damage you can clearly see. Empty array is correct when uncertain.

        Return STRICT JSON only (no markdown), with this schema:
        {
          "damage_markers": [
            { "type": "\(Self.categoryEnum)", "box_2d": [ymin, xmin, ymax, xmax], "severity": "minor|moderate|severe", "confidence": 0-100, "note": "<short pixel evidence>" }
          ]
        }

        \(Self.categoryGuide)

        \(Self.severityGuide)

        \(Self.spatialGuide)

        If no damage is clearly visible, return "damage_markers": []. If the image is NOT a roof (grass, sky, indoors, person, vehicle), return an empty damage_markers array.
        """

        let body = Self.chatCompletionBody(systemPrompt: prompt,
                                            userText: "Analyse this roof frame.",
                                            base64JPEG: base64,
                                            temperature: 0.05)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LiveAnalyzeError.badStatus(http.statusCode)
        }
        guard let parsed = Self.parseResponse(data) else {
            throw LiveAnalyzeError.unparseable
        }
        return parsed
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
              "type": "\(Self.categoryEnum)",
              "box_2d": [ymin, xmin, ymax, xmax],
              "severity": "minor|moderate|severe",
              "confidence": 0-100,
              "note": "short visible pixel evidence"
            }
          ]
        }

        CRITICAL: If the image does NOT clearly show a roof surface, asphalt shingles, tile, metal panels, or any roofing material — for example if it shows grass, sky, ground, indoors, a person, a vehicle, or any non-roof scene — you MUST set analyzed=false, return an empty damage_markers array, and add a finding with label="no_roof_detected" and note="No roof or shingles visible in this photo". Do not fabricate damage findings on non-roof images.

        \(Self.categoryGuide)

        \(Self.severityGuide)

        \(Self.spatialGuide)

        If no damage is clearly visible, return "damage_markers": [].
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

        let userStylePrefix = LocalLearningEngine.shared.userStylePromptPrefix()
        let promptHead = userStylePrefix.isEmpty ? "" : (userStylePrefix + "\n")
        let prompt = promptHead + """
        You are a forensic roof inspector (HAAG standards). \(intro)

        Identify the roof covering and any visible damage. Be conservative — only flag damage you can actually see in the pixels. Empty arrays are correct when nothing is visible.

        Return STRICT JSON only (no markdown), with this schema:
        {
          "analyzed": true|false,
          "shingle_type": { "type": "3-tab asphalt|architectural asphalt|luxury asphalt|wood shake|wood shingle|metal standing seam|metal shingle|clay tile|concrete tile|slate|synthetic slate|composite|rolled roofing|TPO|EPDM|unknown", "confidence": 0-100, "note": "<short evidence>" },
          "findings": [
            { "label": "\(Self.categoryEnum)", "detected": true|false, "severity": "none|minor|moderate|severe", "confidence": 0-100, "count": <int>, "note": "<short evidence>" }
          ],
          "damage_markers": [
            { "type": "\(Self.categoryEnum)", "box_2d": [ymin, xmin, ymax, xmax], "severity": "minor|moderate|severe", "confidence": 0-100, "note": "<short pixel evidence>" }
          ]
        }

        \(Self.categoryGuide)

        \(Self.severityGuide)

        \(Self.spatialGuide)

        The `findings[].label` and `damage_markers[].type` MUST both use the exact same 13 tokens above. Include all 13 damage categories in `findings` (set detected=false for ones not present). If the image is NOT a roof (grass, sky, indoors, person, vehicle), set analyzed=false, return empty `damage_markers`, and add a finding with label="no_roof_detected".
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

    /// Normalizes a model-supplied token to one of the 13 canonical categories,
    /// mapping legacy aliases for backward compatibility. Unknown tokens fall
    /// back to `.other`.
    private static func normalizedType(_ raw: String) -> DamageMarkerType {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "hail_strike", "hail_damage", "hail": return .hailHits
        case "cracking_splitting", "crack": return .cracking
        case "missing_shingle": return .missingShingles
        case "wind_crease": return .windCreasing
        case "algae": return .algaeMoss
        case "blister": return .blistering
        case "flashing_damage": return .flashing
        default: return DamageMarkerType(rawValue: token) ?? .other
        }
    }

    private static func markerFromDict(_ dict: [String: Any]) -> DamageMarker? {
        // Accept "type" (our schema) or "label" (Gemini's native detection key).
        let typeRaw = (dict["type"] as? String) ?? (dict["label"] as? String) ?? "other"
        let type = normalizedType(typeRaw)

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

        // Preferred path: Gemini-native 2D detection box [ymin, xmin, ymax, xmax].
        // Values are normalized to 0-1000 (we also tolerate 0-1 just in case).
        if let box = doubleArray(dict["box_2d"]), box.count == 4 {
            let scale: Double = (box.max() ?? 0) > 1.5 ? 1000.0 : 1.0
            let yMin = min(box[0], box[2]) / scale
            let xMin = min(box[1], box[3]) / scale
            let yMax = max(box[0], box[2]) / scale
            let xMax = max(box[1], box[3]) / scale
            let cx = (xMin + xMax) / 2
            let cy = (yMin + yMax) / 2
            // Radius = half the larger box edge; floored so tiny hail boxes stay
            // visible/tappable, capped so a huge box doesn't swallow the photo.
            let r = max(0.012, min(0.5, max(xMax - xMin, yMax - yMin) / 2))
            return DamageMarker(x: clamp(cx), y: clamp(cy), radius: CGFloat(r),
                                type: type, severity: severity,
                                note: note, confidence: confidence)
        }

        // Gemini-native point [y, x] (0-1000) for point-like features.
        if let pt = doubleArray(dict["point"]), pt.count == 2 {
            let scale: Double = (pt.max() ?? 0) > 1.5 ? 1000.0 : 1.0
            return DamageMarker(x: clamp(pt[1] / scale), y: clamp(pt[0] / scale),
                                radius: 0.03, type: type, severity: severity,
                                note: note, confidence: confidence)
        }

        // Legacy fallback: free-form x/y (+ radius or bbox width/height) in 0-1.
        guard let xVal = (dict["x"] as? Double) ?? (dict["x"] as? NSNumber)?.doubleValue,
              let yVal = (dict["y"] as? Double) ?? (dict["y"] as? NSNumber)?.doubleValue else {
            return nil
        }
        let explicitRadius = (dict["radius"] as? Double) ?? (dict["radius"] as? NSNumber)?.doubleValue
        let bboxW = (dict["width"] as? Double) ?? (dict["width"] as? NSNumber)?.doubleValue
        let bboxH = (dict["height"] as? Double) ?? (dict["height"] as? NSNumber)?.doubleValue
        let radius: Double = {
            if let r = explicitRadius { return r }
            if let w = bboxW, let h = bboxH { return max(w, h) / 2 }
            return 0.04
        }()
        return DamageMarker(x: clamp(xVal), y: clamp(yVal), radius: clamp(radius),
                            type: type, severity: severity,
                            note: note, confidence: confidence)
    }

    /// Parses a JSON array of numbers (Gemini returns NSNumber elements) into
    /// `[Double]`. Returns nil if the value isn't an array of numbers.
    private static func doubleArray(_ any: Any?) -> [Double]? {
        guard let arr = any as? [Any] else { return nil }
        var out: [Double] = []
        out.reserveCapacity(arr.count)
        for v in arr {
            if let n = v as? NSNumber { out.append(n.doubleValue) }
            else if let d = v as? Double { out.append(d) }
            else if let i = v as? Int { out.append(Double(i)) }
            else if let s = v as? String, let d = Double(s) { out.append(d) }
            else { return nil }
        }
        return out
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
        case "hail_hits", "hail_damage", "hail_strike":
            return ("Hail Hits", "circle.hexagongrid.fill", "Hail impact marks")
        case "bruising":
            return ("Bruising", "circle.circle.fill", "Soft mat bruising")
        case "granule_loss":
            return ("Granule Loss", "circle.dotted", "Granule displacement")
        case "wind_damage":
            return ("Wind Damage", "tornado", "Uplift / tearing / blow-off")
        case "missing_shingles", "missing_shingle":
            return ("Missing Shingles", "square.dashed", "Tabs missing")
        case "wind_creasing", "wind_crease":
            return ("Wind Creasing", "wind", "Creases at nail line")
        case "blistering":
            return ("Blistering", "circle.grid.cross.fill", "Raised pockets in mat")
        case "cracking", "cracking_splitting":
            return ("Cracking", "bolt.horizontal.fill", "Surface crack lines")
        case "splitting":
            return ("Splitting", "bolt.horizontal", "Full-thickness splits")
        case "lifted":
            return ("Lifted", "arrow.up.square.fill", "Raised but attached tab")
        case "flashing", "flashing_damage":
            return ("Flashing", "square.stack.3d.up.slash.fill", "Lifted step flashing")
        case "algae_moss", "algae":
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
