import Foundation
import SwiftUI

// MARK: - Coach Feedback

struct CoachFeedback {
    let overallScore: Int      // 0-100
    let tone: String           // "Confident", "Hesitant", etc.
    let strengths: [String]
    let improvements: [String]
    let rewrittenPitch: String
}

struct DamageExplanation {
    let headline: String
    let plainSummary: String
    let bullets: [String]
    let homeownerQuestion: String  // suggested closing line
}

/// Gemini text-only integration for the Training tab:
///  - Role-Play Coach: scores a rep's pitch and rewrites it
///  - Damage Explainer: turns inspector findings into homeowner-friendly language
enum TrainingCoachService {
    static var apiKey: String { Config.allValues["EXPO_PUBLIC_GEMINI_API_KEY"] ?? "" }
    static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    // MARK: - Role-Play Coach

    static func coachPitch(_ pitch: String,
                           scenario: String,
                           customerBrief: String? = nil) async -> CoachFeedback {
        let key = apiKey
        let trimmed = pitch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != "GEMINI_API_KEY",
              let url = URL(string: "\(endpoint)?key=\(key)"),
              !trimmed.isEmpty else {
            try? await Task.sleep(for: .milliseconds(700))
            return mockCoachFeedback(for: trimmed)
        }

        let contextBlock = (customerBrief?.isEmpty == false)
            ? "\nREAL CUSTOMER CONTEXT (tailor the rewrite to this homeowner specifically):\n\(customerBrief!)\n"
            : ""

        let prompt = """
        You are an elite door-to-door sales coach for storm-restoration roofing reps.
        The rep is practicing this scenario: "\(scenario)".
        \(contextBlock)
        REP'S PITCH:
        \"\"\"
        \(trimmed)
        \"\"\"

        Score it like a senior sales trainer. Be honest but constructive. Focus on:
        - Opening / pattern interrupt
        - Establishing trust + credibility
        - Pain/value framing
        - Clear ask (next step)
        - Tone & confidence
        - Brevity (under 30 seconds at the door)

        Return STRICT JSON only, no markdown:
        {
          "overall_score": 0-100,
          "tone": "<one or two words like 'Confident', 'Hesitant', 'Pushy'>",
          "strengths": ["<short bullet>", "<short bullet>", "<short bullet>"],
          "improvements": ["<actionable improvement>", "<actionable improvement>", "<actionable improvement>"],
          "rewritten_pitch": "<a tighter, more effective version of their pitch — 2-4 sentences, ready to deliver at the door>"
        }
        """

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.4
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let parsed = parseCoachResponse(data) {
                return parsed
            }
        } catch {
            // fall through to mock
        }
        try? await Task.sleep(for: .milliseconds(400))
        return mockCoachFeedback(for: trimmed)
    }

    // MARK: - Damage Explainer

    static func explainDamage(findings: [InspectionFinding],
                              homeownerName: String?) async -> DamageExplanation {
        let key = apiKey
        let findingLines = findings
            .filter { $0.detected }
            .map { "- \($0.display) (\($0.severity.rawValue)): \($0.value)" }
            .joined(separator: "\n")

        guard !key.isEmpty, key != "GEMINI_API_KEY",
              let url = URL(string: "\(endpoint)?key=\(key)"),
              !findingLines.isEmpty else {
            try? await Task.sleep(for: .milliseconds(700))
            return mockExplanation(for: findings, name: homeownerName)
        }

        let nameLine = (homeownerName?.isEmpty == false) ? "The homeowner's name is \(homeownerName!)." : ""

        let prompt = """
        You are a friendly, trusted roofing rep explaining inspection findings to a homeowner standing at their front door. \(nameLine)
        Use simple, non-technical language. No insurance jargon. Use everyday analogies.
        Be warm, confident, and brief. Connect each finding to a real consequence (leaks, premature failure).

        FINDINGS FROM THE INSPECTION:
        \(findingLines)

        Return STRICT JSON only, no markdown:
        {
          "headline": "<one short sentence — the big-picture takeaway>",
          "plain_summary": "<2-3 sentence paragraph the rep can read out loud>",
          "bullets": ["<finding explained in plain English with analogy>", "<another>", "<another>", "<another>"],
          "homeowner_question": "<a single soft-close question to ask after explaining, e.g. 'Want me to help you file with your carrier this week?'>"
        }
        """

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": 0.5
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let parsed = parseExplainerResponse(data) {
                return parsed
            }
        } catch {
            // fall through
        }
        try? await Task.sleep(for: .milliseconds(400))
        return mockExplanation(for: findings, name: homeownerName)
    }

    // MARK: - Parsing

    private static func parseCoachResponse(_ data: Data) -> CoachFeedback? {
        guard let payload = extractJSONObject(from: data) else { return nil }
        let score = (payload["overall_score"] as? Int) ?? ((payload["overall_score"] as? NSNumber)?.intValue ?? 70)
        let tone = (payload["tone"] as? String) ?? "Confident"
        let strengths = (payload["strengths"] as? [String]) ?? []
        let improvements = (payload["improvements"] as? [String]) ?? []
        let rewrite = (payload["rewritten_pitch"] as? String) ?? ""
        return CoachFeedback(
            overallScore: max(0, min(100, score)),
            tone: tone,
            strengths: strengths,
            improvements: improvements,
            rewrittenPitch: rewrite
        )
    }

    private static func parseExplainerResponse(_ data: Data) -> DamageExplanation? {
        guard let payload = extractJSONObject(from: data) else { return nil }
        let headline = (payload["headline"] as? String) ?? "Here's what we found on your roof."
        let summary = (payload["plain_summary"] as? String) ?? ""
        let bullets = (payload["bullets"] as? [String]) ?? []
        let question = (payload["homeowner_question"] as? String) ?? "Would you like me to walk you through next steps?"
        return DamageExplanation(
            headline: headline,
            plainSummary: summary,
            bullets: bullets,
            homeownerQuestion: question
        )
    }

    private static func extractJSONObject(from data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let jsonData = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return payload
    }

    // MARK: - Mocks (offline / no API key)

    private static func mockCoachFeedback(for pitch: String) -> CoachFeedback {
        let words = pitch.split(separator: " ").count
        let baseScore = words < 8 ? 52 : (words < 25 ? 74 : 81)
        return CoachFeedback(
            overallScore: baseScore,
            tone: words < 12 ? "Hesitant" : "Confident",
            strengths: [
                "You introduced yourself early — homeowners need to know who you are",
                "You mentioned the recent storm, which builds urgency",
                "You kept it short enough to deliver before they close the door"
            ],
            improvements: [
                "Open with a pattern interrupt — comment on something specific to their home",
                "Replace 'free inspection' with 'second set of eyes' — more credible",
                "End with a clear ask: 'Can I take 12 minutes to check the back slope?'"
            ],
            rewrittenPitch: "Hey, I'm Jordan with RoofWise — we've been on three roofs on \(["Cedar", "Maple", "Oak"].randomElement() ?? "Maple") this morning that took serious hail damage from the April 14th storm. Most of it isn't visible from the ground. I'd love to take 12 minutes, do a quick test square on your back slope, and show you exactly what I find. Sound fair?"
        )
    }

    private static func mockExplanation(for findings: [InspectionFinding], name: String?) -> DamageExplanation {
        let detected = findings.filter { $0.detected }
        let bullets = detected.prefix(4).map { f -> String in
            switch f.label {
            case "hail_damage", "bruising":
                return "Hail bruising — like a bruise on an apple, the shingle is soft underneath. Water gets in next storm."
            case "granule_loss":
                return "Granule loss — your shingles are like sandpaper losing their grit. The asphalt under them dries out and cracks."
            case "missing_shingles":
                return "Missing shingles — these are the obvious ones. Open exposure means the wood underneath is getting wet."
            case "wind_creasing":
                return "Wind creasing — your shingles got bent like a folded business card. The seal is broken even if they look flat."
            case "flashing_damage":
                return "Flashing damage — these are the metal pieces around your chimney and vents. They're the #1 spot leaks start."
            default:
                return "\(f.display) — \(f.value)"
            }
        }
        let opener = (name?.isEmpty == false) ? "\(name!), here's the short version:" : "Here's the short version:"
        return DamageExplanation(
            headline: "Your roof took real damage from that storm — but it's all covered if we move now.",
            plainSummary: "\(opener) the storm hit your roof harder than it looks from the ground. There are \(detected.count) different issues we documented, and most of them get worse the longer we wait. The good news is your insurance is built for exactly this — we just need to file before the carrier deadline.",
            bullets: Array(bullets),
            homeownerQuestion: "Want me to walk you through what filing a claim actually looks like — no obligation?"
        )
    }
}
