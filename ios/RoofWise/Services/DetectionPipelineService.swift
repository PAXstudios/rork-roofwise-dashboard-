import Foundation
import UIKit

// MARK: - Detection Pipeline (Stages 0-3)
//
// Produces accurate, verified per-photo damage detections that feed the
// per-slope aggregation (Stage 4) and the Decision Engine (Stage 6).
// Step 1.5a — per-photo pipeline foundation.
//
//   Stage 0  Image quality gate    — on-device (ImageQualityGate)
//   Stage 1  Material classify     — Gemini
//   Stage 2  Forensic detection    — Gemini (material-specific prompt)
//   Stage 3  Verification pass     — Gemini self-critique (drop false positives)
//
// This is an additive sibling to GeminiAnalysisService; it does not replace
// the existing single-call analyzer. It reuses the same Rork toolkit proxy,
// auth, and image-encoding ladder.

nonisolated enum PipelineError: Error {
    case notConfigured
    case badStatus(Int)
    case unparseable
}

struct DetectionPipelineService {
    private let toolkitURL: String
    private let secret: String
    private static let model = "google/gemini-2.5-flash"

    init() {
        self.toolkitURL = Config.EXPO_PUBLIC_TOOLKIT_URL
        self.secret = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY
    }

    static let shared = DetectionPipelineService()

    private var chatCompletionsURL: URL? {
        URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions")
    }

    // MARK: - Public entry point

    /// Runs the full per-photo pipeline (Stages 0-3) and returns verified
    /// detections with no count limit.
    func analyze(image: UIImage) async -> PhotoDetectionResult {
        // Stage 0 — on-device quality gate.
        let quality = ImageQualityGate.evaluate(image)
        guard quality.passed else {
            return PhotoDetectionResult(
                quality: quality,
                classification: nil,
                detections: [],
                failed: true,
                failureReason: quality.reasons.first ?? "Photo quality too low to analyze."
            )
        }

        guard !secret.isEmpty, chatCompletionsURL != nil else {
            return PhotoDetectionResult(
                quality: quality,
                classification: nil,
                detections: [],
                failed: true,
                failureReason: "Rork toolkit not configured."
            )
        }

        guard let base64 = ImageResize.encodedJPEGBase64(from: image, profile: .full) else {
            return PhotoDetectionResult(
                quality: quality,
                classification: nil,
                detections: [],
                failed: true,
                failureReason: "Could not encode photo for analysis."
            )
        }

        // Stage 1 — material classification.
        let classification: MaterialClassification
        do {
            classification = try await classifyMaterial(base64: base64)
        } catch {
            print("[Pipeline] ❌ Stage 1 (classify) failed: \(error)")
            return PhotoDetectionResult(
                quality: quality,
                classification: nil,
                detections: [],
                failed: true,
                failureReason: "Material classification failed. Tap retry."
            )
        }

        // No-roof short-circuit.
        if classification.material == .unknown && classification.confidence == 0 {
            return PhotoDetectionResult(
                quality: quality,
                classification: classification,
                detections: [],
                failed: false,
                noRoofDetected: true
            )
        }

        // Stage 2 — forensic detection (material-specific).
        let raw: [ForensicDetection]
        do {
            raw = try await detectDamage(base64: base64, material: classification.material)
        } catch {
            print("[Pipeline] ❌ Stage 2 (detect) failed: \(error)")
            return PhotoDetectionResult(
                quality: quality,
                classification: classification,
                detections: [],
                failed: true,
                failureReason: "Damage detection failed. Tap retry."
            )
        }

        // Stage 3 — verification self-critique. On failure we degrade gracefully
        // to the Stage-2 detections rather than failing the whole photo.
        let verified: [ForensicDetection]
        if raw.isEmpty {
            verified = []
        } else {
            do {
                verified = try await verifyDetections(base64: base64, material: classification.material, candidates: raw)
            } catch {
                print("[Pipeline] ⚠️ Stage 3 (verify) failed — using unverified detections: \(error)")
                verified = raw
            }
        }

        print("[Pipeline] ✅ material=\(classification.material.rawValue) raw=\(raw.count) verified=\(verified.count)")
        return PhotoDetectionResult(
            quality: quality,
            classification: classification,
            detections: verified
        )
    }

    // MARK: - Stage 1: material classification

    private func classifyMaterial(base64: String) async throws -> MaterialClassification {
        let materials = HaagRoofMaterial.allCases.map(\.rawValue).joined(separator: "|")
        let prompt = """
        You are a forensic roof inspector. Classify the roof covering material in this photo.

        Return STRICT JSON only (no markdown):
        {
          "is_roof": true|false,
          "material": "\(materials)",
          "confidence": 0-100,
          "evidence": "<1-2 sentence visible evidence>"
        }

        If the image is NOT a roof (grass, sky, indoors, person, vehicle), set is_roof=false, material="unknown", confidence=0.
        Pick the single best material token. Use "unknown" only when genuinely unidentifiable.
        """
        let data = try await postVision(systemPrompt: prompt,
                                        userText: "Classify this roof material.",
                                        base64JPEG: base64,
                                        temperature: 0.0,
                                        timeout: 40)
        guard let payload = Self.extractJSONObject(data) else { throw PipelineError.unparseable }

        let isRoof = (payload["is_roof"] as? Bool) ?? true
        let confidence = Self.intValue(payload["confidence"]) ?? 0
        let evidence = (payload["evidence"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !isRoof {
            return MaterialClassification(material: .unknown, confidence: 0, evidence: evidence.isEmpty ? "No roof visible." : evidence)
        }
        let token = (payload["material"] as? String) ?? "unknown"
        let material = HaagRoofMaterial(rawValue: token) ?? HaagRoofMaterial.from(label: token)
        return MaterialClassification(material: material, confidence: max(0, min(100, confidence)), evidence: evidence)
    }

    // MARK: - Stage 2: forensic damage detection

    private func detectDamage(base64: String, material: HaagRoofMaterial) async throws -> [ForensicDetection] {
        let allowed = ForensicDamageType.types(for: material.category)
        let typeEnum = allowed.map(\.rawValue).joined(separator: "|")
        let guide = Self.taxonomyGuide(for: allowed)

        let prompt = """
        You are a forensic roof inspector following HAAG standards. The roof material is \(material.displayName).
        Detect EVERY distinct, visible damage instance. There is NO count limit — report each individual instance you can see, even if there are 30 or more.

        Return STRICT JSON only (no markdown):
        {
          "detections": [
            {
              "damage_type": "\(typeEnum)",
              "box_2d": [ymin, xmin, ymax, xmax],
              "evidence": "<required 1-2 sentence visible evidence>",
              "severity": "minor|moderate|severe",
              "is_storm_attributable": true|false,
              "is_functional_damage": true|false,
              "confidence": 0-100
            }
          ]
        }

        \(guide)

        Rules:
        - box_2d is your native 2D detection format: [ymin, xmin, ymax, xmax] as INTEGERS normalized to 0-1000 (top-left origin, Y first). Place each box exactly on the real feature — real damage is irregularly scattered, never a uniform row or grid.
        - Use a small tight box for point damage (hail hits, dents, punctures) and box the whole region for area damage (missing shingles, displacement, algae).
        - "evidence" is REQUIRED for every detection — describe what you actually see in the pixels.
        - "is_storm_attributable": false for wear, aging, manufacturing defects, foot traffic, blistering, and algae/moss. Do NOT attribute these to a storm.
        - "is_functional_damage": true only if it qualifies under HAAG functional thresholds; cosmetic-only marks are false.
        - Be conservative — never fabricate damage. An empty detections array is correct when nothing is visible.
        """

        let data = try await postVision(systemPrompt: prompt,
                                        userText: "Detect all visible roof damage.",
                                        base64JPEG: base64,
                                        temperature: 0.05,
                                        timeout: 60)
        guard let payload = Self.extractJSONObject(data) else { throw PipelineError.unparseable }
        let rawArr = (payload["detections"] as? [[String: Any]]) ?? []
        return rawArr.compactMap { Self.detectionFromDict($0, allowed: Set(allowed)) }
    }

    // MARK: - Stage 3: verification self-critique

    private func verifyDetections(base64: String,
                                  material: HaagRoofMaterial,
                                  candidates: [ForensicDetection]) async throws -> [ForensicDetection] {
        // Send the candidate list back with stable indices so the model can
        // confirm/reject each one against the pixels.
        var lines: [String] = []
        for (i, d) in candidates.enumerated() {
            let box: String
            if let b = d.box2d {
                let parts: [String] = b.map { "\($0)" }
                box = "[" + parts.joined(separator: ",") + "]"
            } else {
                box = "null"
            }
            let type = d.damageType.rawValue
            let sev = d.severity.rawValue
            let ev = Self.escape(d.evidence)
            let line = "{\"index\":\(i),\"damage_type\":\"\(type)\",\"box_2d\":\(box),\"severity\":\"\(sev)\",\"evidence\":\"\(ev)\"}"
            lines.append(line)
        }
        let candidateJSON = "[" + lines.joined(separator: ",") + "]"

        let prompt = """
        You are a senior QA reviewer auditing another inspector's roof-damage detections on a \(material.displayName) roof.
        For each candidate below, look at the actual pixels and decide whether it is a REAL, correctly-classified damage instance.
        Drop false positives (shadows, normal granule texture, lens artifacts, correct-but-duplicate boxes, or misclassified features). Keep only confirmed detections, and correct the severity / storm-attributable / functional flags if the original was wrong.

        Candidates:
        \(candidateJSON)

        Return STRICT JSON only (no markdown):
        {
          "verified": [
            {
              "index": <int matching a candidate>,
              "keep": true|false,
              "damage_type": "<corrected or same token>",
              "box_2d": [ymin, xmin, ymax, xmax],
              "evidence": "<short confirming evidence>",
              "severity": "minor|moderate|severe",
              "is_storm_attributable": true|false,
              "is_functional_damage": true|false,
              "confidence": 0-100
            }
          ]
        }

        Only include entries you are keeping (keep=true). Be strict but fair — do not invent new detections that were not in the candidate list.
        """

        let data = try await postVision(systemPrompt: prompt,
                                        userText: "Verify these detections against the image.",
                                        base64JPEG: base64,
                                        temperature: 0.0,
                                        timeout: 60)
        guard let payload = Self.extractJSONObject(data) else { throw PipelineError.unparseable }
        let arr = (payload["verified"] as? [[String: Any]]) ?? []

        var out: [ForensicDetection] = []
        for dict in arr {
            let keep = (dict["keep"] as? Bool) ?? true
            guard keep else { continue }
            let allowed = Set(ForensicDamageType.types(for: material.category))
            // Fall back to the original candidate's type/box if the verifier omitted them.
            if let d = Self.detectionFromDict(dict, allowed: allowed) {
                out.append(d)
            } else if let idx = Self.intValue(dict["index"]), idx >= 0, idx < candidates.count {
                out.append(candidates[idx])
            }
        }
        return out
    }

    // MARK: - Networking

    private func postVision(systemPrompt: String,
                            userText: String,
                            base64JPEG: String,
                            temperature: Double,
                            timeout: TimeInterval) async throws -> Data {
        guard let url = chatCompletionsURL else { throw PipelineError.notConfigured }
        let body: [String: Any] = [
            "model": Self.model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64JPEG)"]]
                ]]
            ]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PipelineError.badStatus(http.statusCode)
        }
        return data
    }

    // MARK: - Parsing helpers

    /// Pulls the assistant message text out of the OpenAI-compatible envelope,
    /// strips code fences, and decodes the inner JSON object.
    private static func extractJSONObject(_ data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let text: String? = {
            if let choices = root["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any] {
                if let s = message["content"] as? String { return s }
                if let parts = message["content"] as? [[String: Any]] {
                    return parts.compactMap { $0["text"] as? String }.joined()
                }
            }
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
        return payload
    }

    private static func detectionFromDict(_ dict: [String: Any], allowed: Set<ForensicDamageType>) -> ForensicDetection? {
        guard let typeRaw = (dict["damage_type"] as? String) ?? (dict["type"] as? String),
              let type = ForensicDamageType(rawValue: typeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
              allowed.contains(type) else {
            return nil
        }
        let box = intArray(dict["box_2d"])
        let evidence = (dict["evidence"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? type.displayName
        let severityRaw = (dict["severity"] as? String ?? "moderate").lowercased()
        let severity = ForensicSeverity(rawValue: severityRaw) ?? .moderate
        // Default storm-attributable from the taxonomy when the model omits it.
        let storm = (dict["is_storm_attributable"] as? Bool) ?? !type.isNonStormByDefinition
        let functional = (dict["is_functional_damage"] as? Bool) ?? (severity != .minor)
        let confidence = intValue(dict["confidence"]) ?? 0
        return ForensicDetection(
            damageType: type,
            box2d: (box?.count == 4) ? box : nil,
            evidence: evidence,
            severity: severity,
            isStormAttributable: storm,
            isFunctionalDamage: functional,
            confidence: max(0, min(100, confidence))
        )
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d.rounded()) }
        if let s = any as? String, let i = Int(s) { return i }
        return nil
    }

    private static func intArray(_ any: Any?) -> [Int]? {
        guard let arr = any as? [Any] else { return nil }
        var out: [Int] = []
        for v in arr {
            if let i = intValue(v) { out.append(i) } else { return nil }
        }
        return out
    }

    private static func stripCodeFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Compact per-type definition list embedded in the Stage-2 prompt so the
    /// model distinguishes close pairs (cosmetic vs functional metal dent, etc.).
    private static func taxonomyGuide(for types: [ForensicDamageType]) -> String {
        let lines = types.map { "- \($0.rawValue) = \(definition(for: $0))" }
        return "Damage type definitions (use the exact token):\n" + lines.joined(separator: "\n")
    }

    private static func definition(for type: ForensicDamageType) -> String {
        switch type {
        case .hailHit: return "circular impact with granule displacement and exposed mat"
        case .bruising: return "round depression with mat fracture underneath"
        case .granuleLoss: return "patches of exposed mat (functional) vs uniform thinning (cosmetic/aging)"
        case .matTransfer: return "granules deposited in unusual locations indicating recent impact"
        case .windCreasing: return "shingle bent backward with a visible crease line"
        case .missingTab: return "single tab missing from a 3-tab shingle (gap in tab pattern)"
        case .missingShingle: return "an entire shingle missing exposing underlayment"
        case .lifted: return "sealant strip broken, tab raised but still attached"
        case .cracking: return "surface fissures"
        case .splitting: return "full-thickness fracture"
        case .blistering: return "convex bump from heat — NOT storm"
        case .flashingDamage: return "bent/lifted metal flashing at chimneys/valleys/sidewalls"
        case .algaeMoss: return "dark streaks or green growth — NOT storm"
        case .footfallDamage: return "scuff marks in walking lines — NOT storm"
        case .metalDentCosmetic: return "shallow dent, no paint damage, no functional impact"
        case .metalDentFunctional: return "deep dent with paint cracking or seam compromise"
        case .seamDisengagement: return "visible gap or separation at a panel seam"
        case .fastenerPullout: return "raised fastener or compromised attachment"
        case .tileCracked: return "visible crack on a single tile"
        case .tileBroken: return "tile fractured into pieces"
        case .tileDisplaced: return "tile out of position relative to course"
        case .underlaymentExposure: return "gap where a tile is missing exposing underlayment"
        case .slateCracked: return "cracked slate"
        case .slateDisplaced: return "slate out of position"
        case .slateCornerBroken: return "broken corner on a slate"
        case .woodSplitWithGrain: return "split running along the grain (aging if uniform)"
        case .woodFracture: return "fracture with displaced fibers (storm-attributable)"
        case .woodGranularCrushing: return "crushing of the wood surface from impact"
        case .membranePuncture: return "hole or tear through the membrane"
        case .membraneDisplacement: return "membrane lifted or pulled from substrate"
        case .adhesionFailure: return "blistering or bubbling indicating loss of bond"
        case .surfaceAbrasion: return "scuffing without puncture"
        case .seamSplit: return "separation at a welded or adhered seam"
        case .structuralSagging: return "roof-line deviation — escalate to engineer"
        }
    }
}
