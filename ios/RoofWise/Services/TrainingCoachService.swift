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

/// Gemini text-only coaching via the same Rork Toolkit proxy as roof detection.
///  - Role-Play Coach: scores a rep's pitch and rewrites it
///  - Damage Explainer: turns inspector findings into homeowner-friendly language
enum TrainingCoachService {
    private static let model = GeminiAnalysisService.modelVersion

    // MARK: - Role-Play Coach

    static func coachPitch(_ pitch: String,
                           scenario: String,
                           customerBrief: String? = nil) async -> CoachFeedback {
        let trimmed = pitch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return unavailableCoach(reason: "Type a pitch first.")
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

        guard let data = await postJSON(systemPrompt: prompt, userText: "Score this pitch.") else {
            return unavailableCoach(reason: "RoofWise Vision isn't available. Try again when you're online.")
        }
        if let parsed = parseCoachResponse(data) { return parsed }
        return unavailableCoach(reason: "Couldn't score this pitch. Try again.")
    }

    // MARK: - Damage Explainer

    static func explainDamage(findings: [InspectionFinding],
                              homeownerName: String?) async -> DamageExplanation {
        let findingLines = findings
            .filter { $0.detected }
            .map { "- \($0.display) (\($0.severity.rawValue)): \($0.value)" }
            .joined(separator: "\n")

        guard !findingLines.isEmpty else {
            return DamageExplanation(
                headline: "No inspection findings yet",
                plainSummary: "Inspect a roof first. This script is built from real AI findings, not sample damage.",
                bullets: [],
                homeownerQuestion: ""
            )
        }

        let nameLine = (homeownerName?.isEmpty == false) ? "The homeowner's name is \(homeownerName!)." : ""

        let prompt = """
        You are a friendly, trusted roofing rep explaining inspection findings to a homeowner standing at their front door. \(nameLine)
        Use simple, non-technical language. No insurance jargon. Use everyday analogies.
        Be warm, confident, and brief. Connect each finding to a real consequence (leaks, premature failure).
        Do not invent storms, streets, dates, or coverage. Only explain the findings listed below.

        FINDINGS FROM THE INSPECTION:
        \(findingLines)

        Return STRICT JSON only, no markdown:
        {
          "headline": "<one short sentence — the big-picture takeaway>",
          "plain_summary": "<2-3 sentence paragraph the rep can read out loud>",
          "bullets": ["<finding explained in plain English with analogy>", "<another>", "<another>", "<another>"],
          "homeowner_question": "<a single soft-close question to ask after explaining>"
        }
        """

        guard let data = await postJSON(systemPrompt: prompt, userText: "Translate these findings.") else {
            return DamageExplanation(
                headline: "Couldn't generate an explanation",
                plainSummary: "RoofWise Vision is unavailable. Try again when you're online.",
                bullets: [],
                homeownerQuestion: ""
            )
        }
        if let parsed = parseExplainerResponse(data) { return parsed }
        return DamageExplanation(
            headline: "Couldn't generate an explanation",
            plainSummary: "RoofWise Vision returned an unreadable response. Try again.",
            bullets: [],
            homeownerQuestion: ""
        )
    }

    // MARK: - Toolkit request

    private static func postJSON(systemPrompt: String, userText: String) async -> Data? {
        let secret = Config.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY
        let toolkitURL = Config.EXPO_PUBLIC_TOOLKIT_URL
        guard !secret.isEmpty, !toolkitURL.isEmpty,
              let url = URL(string: "\(toolkitURL)/v2/vercel/v1/chat/completions") else {
            return nil
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
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
        guard var s = text?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let jsonData = s.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private static func unavailableCoach(reason: String) -> CoachFeedback {
        CoachFeedback(
            overallScore: 0,
            tone: "Unavailable",
            strengths: [],
            improvements: [reason],
            rewrittenPitch: ""
        )
    }
}
