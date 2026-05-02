import SwiftUI

// MARK: - Lesson Domain

enum LessonCategory: String, CaseIterable, Identifiable {
    case hailDamage = "Hail Damage"
    case windDamage = "Wind Damage"
    case adjusters = "Adjusters"
    case homeowner = "Homeowner Comms"
    case objections = "Objection Handling"
    case claims = "Claims Process"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hailDamage: return "circle.hexagongrid.fill"
        case .windDamage: return "wind"
        case .adjusters: return "person.2.wave.2.fill"
        case .homeowner: return "house.fill"
        case .objections: return "bubble.left.and.exclamationmark.bubble.right.fill"
        case .claims: return "doc.text.magnifyingglass"
        }
    }

    var tint: Color {
        switch self {
        case .hailDamage: return Theme.crimson
        case .windDamage: return Theme.ember
        case .adjusters: return Theme.sky
        case .homeowner: return Theme.mint
        case .objections: return Theme.amber
        case .claims: return Color(red: 0.45, green: 0.30, blue: 0.78)
        }
    }
}

struct LessonSection: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
    let bullets: [String]
}

struct Lesson: Identifiable {
    let id: String
    let category: LessonCategory
    let title: String
    let summary: String
    let durationMinutes: Int
    let difficulty: String   // "Beginner", "Intermediate", "Pro"
    let sections: [LessonSection]
    let keyTakeaways: [String]
}

// MARK: - Mock Curriculum

enum TrainingCurriculum {
    static let lessons: [Lesson] = [
        Lesson(
            id: "hail-101",
            category: .hailDamage,
            title: "Identifying Hail Damage Like a HAAG Inspector",
            summary: "Spot bruising, fractures, and spatter — and tell hail apart from blistering or mechanical damage.",
            durationMinutes: 6,
            difficulty: "Beginner",
            sections: [
                LessonSection(
                    heading: "What hail actually does",
                    body: "Hail strikes asphalt shingles with enough force to fracture the fiberglass mat beneath the granules. The granules displace, exposing the black mat underneath. The hit is round, has a soft center, and granules collect downhill in the gutter.",
                    bullets: [
                        "Round, randomly distributed strikes (3/8\" to 2\" diameter)",
                        "Mat is bruised — soft to the touch, like a pencil eraser",
                        "Granules pool in gutters and downspouts",
                        "Spatter marks on metal vents, flashing, A/C fins"
                    ]
                ),
                LessonSection(
                    heading: "The 10x10 test square",
                    body: "Adjusters mark a 10ft x 10ft test square on each slope. They count individual hail hits inside that square. Most carriers require 8+ functional hits to approve a slope.",
                    bullets: [
                        "Mark the square with chalk on the slope",
                        "Count only functional hits (mat fracture)",
                        "Document with chalk-circled close-up photos",
                        "Always test all slopes — directionality matters"
                    ]
                ),
                LessonSection(
                    heading: "Hail vs. mechanical damage",
                    body: "Mechanical damage from foot traffic or installation is linear, has no spatter, and is concentrated in walk paths. Hail is random and accompanied by collateral damage on metal.",
                    bullets: [
                        "Hail = random pattern + spatter on soft metal",
                        "Mechanical = linear scuffs along ridges/valleys",
                        "Blistering = raised pockets, no granule loss"
                    ]
                )
            ],
            keyTakeaways: [
                "Look for round bruises with displaced granules",
                "Always check soft metal (vents, A/C, gutters) for spatter",
                "Document with chalk circles + close-ups + slope context"
            ]
        ),
        Lesson(
            id: "wind-101",
            category: .windDamage,
            title: "Wind Damage: Creasing, Lifting & Missing Tabs",
            summary: "Identify wind events that compromise the seal strip and qualify for full slope replacement.",
            durationMinutes: 5,
            difficulty: "Beginner",
            sections: [
                LessonSection(
                    heading: "The seal strip is everything",
                    body: "Asphalt shingles rely on a thermally-activated seal strip to lock tabs together. Once wind breaks that seal, the shingle is functionally compromised — even if it's still in place.",
                    bullets: [
                        "Creases at the nail line = broken seal",
                        "Lifted/folded tabs that don't reseal",
                        "Missing tabs (high-wind event indicator)",
                        "Adjacent shingles compromised even if intact"
                    ]
                ),
                LessonSection(
                    heading: "Test for compromised seals",
                    body: "Lift adjacent tabs gently — if the seal pops without resistance, the seal is broken. Document with side-by-side photos of intact vs. compromised tabs.",
                    bullets: [
                        "Use a putty knife to lift tab corners",
                        "Photograph creases at nail line",
                        "Check ridge cap shingles separately",
                        "Note prevailing wind direction from storm report"
                    ]
                )
            ],
            keyTakeaways: [
                "Creasing at the nail line = full slope replacement",
                "Pull NOAA storm reports for wind speed verification",
                "Don't forget ridge caps — they fail first"
            ]
        ),
        Lesson(
            id: "adjuster-101",
            category: .adjusters,
            title: "What Insurance Adjusters Look For",
            summary: "Walk into the adjuster meeting prepared. Know their checklist before they show up.",
            durationMinutes: 7,
            difficulty: "Intermediate",
            sections: [
                LessonSection(
                    heading: "The adjuster's checklist",
                    body: "Adjusters work fast. They look for date of loss confirmation, slope-by-slope hit counts, collateral on soft metal, and matching color/type for repairs.",
                    bullets: [
                        "Date of loss matches NOAA storm record",
                        "Test square hit counts per slope",
                        "Soft metal damage (the smoking gun)",
                        "Code/match issues (discontinued shingle = full replacement)"
                    ]
                ),
                LessonSection(
                    heading: "Be the adjuster's helper, not adversary",
                    body: "Walk the roof together. Carry a chalk bucket, magnetic measuring wheel, and your inspection report on iPad. Point out damage — don't argue.",
                    bullets: [
                        "Have your photo report ready before they arrive",
                        "Walk the roof with them, not behind them",
                        "Use HAAG language: 'mat fracture,' 'displaced granules'",
                        "Ask: 'Do you see this differently?' — never argue"
                    ]
                ),
                LessonSection(
                    heading: "Supplements & re-inspections",
                    body: "If the adjuster denies, request a re-inspection in writing within 30 days. Document new damage you missed first time. Bring an engineer if needed.",
                    bullets: [
                        "Get denial in writing with specifics",
                        "Re-inspect within 30 days",
                        "Bring HAAG-certified engineer for borderline claims",
                        "File supplement for code upgrades (drip edge, ice & water)"
                    ]
                )
            ],
            keyTakeaways: [
                "Be a partner, not a problem",
                "Speak HAAG language fluently",
                "Always have a paper trail for denials"
            ]
        ),
        Lesson(
            id: "homeowner-101",
            category: .homeowner,
            title: "Explaining Roof Damage to Homeowners",
            summary: "Translate inspector-speak into plain English so homeowners trust you and sign.",
            durationMinutes: 4,
            difficulty: "Beginner",
            sections: [
                LessonSection(
                    heading: "Avoid jargon. Use analogies.",
                    body: "Homeowners don't know what a 'mat fracture' is. They know bruises, broken seals, and missing pieces. Use what they know.",
                    bullets: [
                        "'Hail bruise' = like a bruise on an apple — soft underneath",
                        "'Broken seal' = like a Ziploc that won't close anymore",
                        "'Granule loss' = sandpaper losing its grit",
                        "'Wind crease' = the shingle has been bent open"
                    ]
                ),
                LessonSection(
                    heading: "Show, don't tell",
                    body: "Pull up the photo on your phone. Zoom in. Trace the damage with your finger. Then connect it to consequence: 'This is where water gets in next storm.'",
                    bullets: [
                        "Photo first, words second",
                        "Trace damage with your finger",
                        "Connect to consequence (leak, mold, structure)",
                        "Pause and let them ask questions"
                    ]
                )
            ],
            keyTakeaways: [
                "Speak homeowner, not inspector",
                "Always show photos at the door",
                "Connect every finding to a real consequence"
            ]
        ),
        Lesson(
            id: "objections-101",
            category: .objections,
            title: "Top 7 Objections & Field-Tested Responses",
            summary: "From 'I already have a roofer' to 'I don't want my premium going up' — answers that work.",
            durationMinutes: 8,
            difficulty: "Intermediate",
            sections: [
                LessonSection(
                    heading: "\"I already have a roofer.\"",
                    body: "Acknowledge, then differentiate. 'That's great — having a backup quote is smart. Most homeowners get 2-3 inspections to make sure nothing is missed. Mind if I take 15 minutes to give you a second set of eyes? It's free.'",
                    bullets: [
                        "Acknowledge their choice (don't bash competitor)",
                        "Reframe as 'second opinion'",
                        "Time-box the ask (15 min)",
                        "Reinforce free / no-obligation"
                    ]
                ),
                LessonSection(
                    heading: "\"My premium will go up.\"",
                    body: "'Storm claims are no-fault — they don't raise individual rates. What raises rates is everyone in your zip code filing late. Filing now actually helps the neighborhood.'",
                    bullets: [
                        "No-fault claims don't affect individual rates",
                        "Rate increases are zip-code wide",
                        "Filing within 1 year is a state-protected right"
                    ]
                ),
                LessonSection(
                    heading: "\"I don't see any damage.\"",
                    body: "'That's normal — most hail damage isn't visible from the ground. It's microscopic granule displacement. Mind if I do a quick test square on the back slope and show you what I find?'",
                    bullets: [
                        "Validate — most damage IS invisible from ground",
                        "Offer a free demo on one slope",
                        "Bring photos back to show — let evidence sell"
                    ]
                ),
                LessonSection(
                    heading: "\"I need to talk to my spouse.\"",
                    body: "'Totally understand — this is a household decision. What's the best time tonight or tomorrow when you're both home? I'd love to walk through the findings with both of you.'",
                    bullets: [
                        "Don't push past it — set the next appointment",
                        "Ask for a specific time, both present",
                        "Re-confirm 1 hour before"
                    ]
                )
            ],
            keyTakeaways: [
                "Always acknowledge before answering",
                "Reframe objections as opportunities",
                "Set the next step before you leave"
            ]
        ),
        Lesson(
            id: "claims-101",
            category: .claims,
            title: "The Insurance Claims Process — Start to Finish",
            summary: "Understand every step so you can guide the homeowner with confidence.",
            durationMinutes: 6,
            difficulty: "Beginner",
            sections: [
                LessonSection(
                    heading: "The 8-step flow",
                    body: "Inspection → Claim filed → Adjuster assigned → Adjuster meeting → Approval/denial → Supplement (if needed) → Material order → Build day.",
                    bullets: [
                        "Inspection — you find the damage",
                        "Claim filed — homeowner calls insurer with date of loss",
                        "Adjuster assigned within 5-7 days",
                        "Adjuster meeting — you walk roof together",
                        "Carrier issues ACV check (Actual Cash Value)",
                        "Build → file depreciation release → final check"
                    ]
                ),
                LessonSection(
                    heading: "ACV vs. RCV",
                    body: "Carriers pay ACV upfront (depreciated value). After build, you submit final invoice to release the recoverable depreciation (RCV - ACV).",
                    bullets: [
                        "ACV check arrives first (minus deductible)",
                        "Build the roof to RCV spec",
                        "Submit final invoice + photos for depreciation release",
                        "Final check covers RCV minus ACV"
                    ]
                ),
                LessonSection(
                    heading: "Code upgrades & supplements",
                    body: "Drip edge, ice & water shield, and ridge ventilation are often code-required but missed in initial scope. File a supplement with code citations.",
                    bullets: [
                        "Cite local code (IRC 2018 R905.1.1, etc.)",
                        "Photo-document missing items",
                        "Submit Xactimate-formatted supplement",
                        "Average supplement adds $1,500-$4,000"
                    ]
                )
            ],
            keyTakeaways: [
                "Two checks: ACV upfront, RCV after build",
                "Always file code upgrades as supplements",
                "Homeowner deductible is non-negotiable by law"
            ]
        )
    ]

    static func lessons(for category: LessonCategory) -> [Lesson] {
        lessons.filter { $0.category == category }
    }
}

// MARK: - Progress Store

@Observable
final class TrainingProgressStore {
    var completedLessonIDs: Set<String> = []
    var completedAt: [String: Date] = [:]
    var lastCoachScore: Int? = nil
    var coachSessionsCompleted: Int = 0
    var explainerGenerationsCount: Int = 0

    /// Rolling average score per category (0-100). Used to surface the rep's
    /// weakest skill area for Today's Lesson recommendations.
    var categoryScores: [LessonCategory: Int] = [:]
    /// Per-customer coaching activity for inline Customer Profile reps.
    var customerCoachSessions: [UUID: Int] = [:]
    var customerCoachLastScore: [UUID: Int] = [:]

    func markComplete(_ id: String) {
        completedLessonIDs.insert(id)
        completedAt[id] = Date()
    }

    func toggle(_ id: String) {
        if completedLessonIDs.contains(id) {
            completedLessonIDs.remove(id)
            completedAt[id] = nil
        } else {
            completedLessonIDs.insert(id)
            completedAt[id] = Date()
        }
    }

    func isComplete(_ id: String) -> Bool {
        completedLessonIDs.contains(id)
    }

    /// True if completed within the last 7 days.
    func recentlyCompleted(_ id: String, withinDays days: Int = 7) -> Bool {
        guard let date = completedAt[id] else { return false }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return date >= cutoff
    }

    var totalLessons: Int { TrainingCurriculum.lessons.count }
    var completedCount: Int { completedLessonIDs.count }
    var progressFraction: Double {
        guard totalLessons > 0 else { return 0 }
        return Double(completedCount) / Double(totalLessons)
    }

    // MARK: Coach session tracking

    /// Records a coach session globally. Optionally tags it to a category
    /// (so we can surface the weakest area) and a customer (for the inline
    /// Practice flow on the Customer Profile).
    func recordCoachSession(score: Int,
                            category: LessonCategory? = nil,
                            customerID: UUID? = nil) {
        lastCoachScore = score
        coachSessionsCompleted += 1
        if let category {
            // Exponential moving average — fresh scores weigh slightly more.
            if let existing = categoryScores[category] {
                categoryScores[category] = Int(Double(existing) * 0.6 + Double(score) * 0.4)
            } else {
                categoryScores[category] = score
            }
        }
        if let customerID {
            customerCoachSessions[customerID, default: 0] += 1
            customerCoachLastScore[customerID] = score
        }
    }

    /// Lowest-scored category (or `.objections` as the default starting point
    /// when the rep hasn't logged any sessions yet).
    var weakestCategory: LessonCategory {
        if let weakest = categoryScores.min(by: { $0.value < $1.value })?.key {
            return weakest
        }
        return .objections
    }

    /// Picks today's recommended lesson — biased toward the weakest category,
    /// skipping any lesson completed within the last 7 days. Rotates daily.
    func recommendedDailyLesson(on date: Date = Date()) -> Lesson? {
        let pool = TrainingCurriculum.lessons.filter { !recentlyCompleted($0.id) }
        guard !pool.isEmpty else { return nil }

        let weak = weakestCategory
        let weakPool = pool.filter { $0.category == weak }
        let candidates = weakPool.isEmpty ? pool : weakPool

        // Stable per-day rotation
        let dayKey = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let idx = abs(dayKey) % candidates.count
        return candidates[idx]
    }
}

// MARK: - Stage → Coaching Hint

extension JobPipelineStage {
    /// The most relevant lesson to surface as an inline Coach Tip on the
    /// Customer Profile based on where the customer sits in the pipeline.
    var coachLessonID: String {
        switch self {
        case .knocked: return "objections-101"
        case .interested: return "homeowner-101"
        case .inspectionScheduled: return "hail-101"
        case .inspectionComplete: return "homeowner-101"
        case .claimFiled: return "claims-101"
        case .adjusterMeeting: return "adjuster-101"
        case .approved: return "claims-101"
        case .materialOrdered: return "claims-101"
        case .jobComplete: return "homeowner-101"
        case .paid: return "objections-101"
        }
    }

    /// One-line tactical tip framed for this stage.
    var coachTip: String {
        switch self {
        case .knocked:
            return "Lead with a pattern interrupt — comment on something specific to the home, not the storm."
        case .interested:
            return "Translate findings into homeowner-speak. Use analogies (bruise on an apple, broken Ziploc seal)."
        case .inspectionScheduled:
            return "Walk in with a checklist. Front, back, sides, ridge, valleys, soft metal — miss nothing."
        case .inspectionComplete:
            return "Show photos, trace damage with your finger, connect each finding to a real consequence."
        case .claimFiled:
            return "Confirm date of loss matches NOAA storm reports before the adjuster shows up."
        case .adjusterMeeting:
            return "Be the adjuster's helper, not adversary. Speak HAAG language: 'mat fracture,' 'displaced granules.'"
        case .approved:
            return "Two checks coming: ACV upfront, RCV after build. File supplements for code upgrades early."
        case .materialOrdered:
            return "Reconfirm color/profile match. Discontinued shingles unlock full slope replacement supplements."
        case .jobComplete:
            return "Submit final invoice + photos to release recoverable depreciation. Don't leave money on the roof."
        case .paid:
            return "Ask for the referral now — happiest moment in the cycle. Two neighbors is the standard ask."
        }
    }
}

// MARK: - Customer Coaching Context

/// Snapshot of a customer's situation, passed to the Role-Play Coach so the
/// rep can practice the exact pitch they'll deliver.
struct CustomerCoachContext: Equatable {
    let customerID: UUID
    let ownerName: String
    let address: String
    let stage: JobPipelineStage
    let insuranceCompany: String
    let recentObjections: [String]
    let lastInteraction: String?

    var scenarioTitle: String {
        "\(ownerName) · \(stage.shortLabel)"
    }

    /// A scenario brief written for the AI coach — captures the real context
    /// so feedback aligns with the rep's actual next conversation.
    var promptBrief: String {
        var parts: [String] = []
        parts.append("Customer: \(ownerName) at \(address).")
        parts.append("Pipeline stage: \(stage.rawValue).")
        if !insuranceCompany.isEmpty {
            parts.append("Insurance carrier: \(insuranceCompany).")
        }
        if !recentObjections.isEmpty {
            parts.append("Known objections / notes: " + recentObjections.joined(separator: " | "))
        }
        if let last = lastInteraction, !last.isEmpty {
            parts.append("Last interaction: \(last)")
        }
        return parts.joined(separator: " ")
    }
}
