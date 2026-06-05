# RoofWise — Spec Compliance Audit

> Audit of the native iOS SwiftUI app (`ios/RoofWise`) against the RoofWise build
> spec. Generated during the Phase-1 foundation reconciliation. Status reflects the
> state **after** the Phase-1 changes in this PR.

## Summary

The app already implements the large majority of the spec (5 tabs, `gemini-2.5-flash`
analysis, HAAG decision engine, PDF reports, proposals, training/learning loop, storm
watch, door-knocking, mileage). It was built against an earlier design system, so the
gaps were concentrated in the design tokens, seeded sample data, committed secrets, and
duplicate/dead Home cards. Phase 1 closes those.

> ⚠️ **Cannot verify build-pass here.** This work was done in a Linux environment with
> no Xcode. The project must be built on a Mac (iOS 17+) before relying on it.

## Divergence table (and Phase-1 resolution)

| Area | Spec | Before | Phase-1 status |
|---|---|---|---|
| Palette | Navy `#0C183C` / Orange `#FC6018` / Cream `#F0F0E4` / Slate `#546078` as `Theme.navy` etc. | `ink #0F1B3B`, `ember #FF6B2E`, `canvas #F8F6F2`; no navy/orange/cream/slate tokens | ✅ Canonical tokens added; `ink/ember/canvas/inkSoft` re-pointed to exact spec hex (whole app shifts palette) |
| Type ramp | `caption` 11pt; spec names titleXl/Lg/Md, bodyLg/Md/Sm + weights | `caption` 12pt; ramp used local names | ✅ `caption`→11; spec-named sizes + weighted `Font` helpers added |
| Seeded data | "No mocks, no seeded sample data — empty state always" | `MockData.swift` (KPIs, pipeline, schedule, jobs, storms) + hardcoded cards | ✅ `MockData.swift` deleted; all consumers now real-store-driven or empty state |
| Committed secrets | Keys via env/Info.plist, no literals | 4 hardcoded Google API keys + Supabase URL/anon literals | ✅ Resolved from env→Info.plist→empty; literals removed |
| Gemini model | `gemini-2.5-flash` everywhere | `TrainingCoachService` used `gemini-1.5-flash` | ✅ Updated to `gemini-2.5-flash` |
| Info.plist | mic + speech usage strings present | both missing | ✅ Added in `project.pbxproj` |
| Duplicate cards | n/a | `PipelineCard`/`RecentJobsRow`/`AIInsightsCard` duplicated newer sections; fake `LeaderboardCard`; fake storm-history map | ✅ Deleted (superseded / team-feature is Phase X / superseded by real MapKit) |

## Already compliant (verified)

- 5 bottom tabs: Home / Leads / Map / Plan / Train (`RootView`).
- `BGTaskSchedulerPermittedIdentifiers` = `app.roofwise.stormwatch`,
  `com.roofwise.calibration_weekly` (match the service identifiers).
- `CFBundleURLTypes` scheme `roofwise`, name `com.paxconsulting.roofwise.deeplink`.
- Camera/Location usage strings; `cardStyle` modifier; main `GeminiAnalysisService`
  on `gemini-2.5-flash`; `requireAuth = false` dev bypass; `useStructuredConfidence`.
- `CustomerStore`, `EstimatesStore`, `StormAlertStore` already boot empty.

## Phase-1 changes in this PR

- `Utilities/Theme.swift` — canonical palette + spec type-ramp/weights.
- `Configuration/APIKeys.swift` — env/Info.plist key resolution, no literals.
- `RoofWise.xcodeproj/project.pbxproj` — mic + speech usage descriptions.
- `Services/TrainingCoachService.swift` — `gemini-2.5-flash`.
- De-mock: `KPIStrip` (Revenue/Leads/Pipeline from `CustomerStore`),
  `TasksAndActivityCard`, `ScheduleCard`, `StormAlertCard`, `TodaysGoalsCard`,
  `RecentWinsCard`, `PropertyStormService` → real stores / empty states.
- New `Views/Components/EmptyHint.swift` shared empty-state.
- Deleted: `Models/MockData.swift`, `PipelineCard.swift`, `RecentJobsRow.swift`,
  `AIInsightsCard.swift`, `StormHistoryMapCard.swift`, `LeaderboardCard`, and the
  dead model types `PipelineColumn`, `PipelineStage`, `MapPin`, `LeadKind`,
  `AIReviewItem`, `ActivityEntry`.

## Known follow-ups

### Security
- The previously committed Google API key (`AIzaSyDmnzp1Q…`) and Supabase anon key
  remain in **git history**. Removing them from source does not purge history —
  **rotate the Google key** in Google Cloud and treat the anon key as exposed.

### Phase 2 — AI shingle-analysis accuracy (in progress, behind flags)
All flags live in `APIKeys` and default ON; each OFF path is byte-identical to before.

Implemented:
- **Photo-quality gate** (`usePhotoQualityGate`) — `PhotoQualityService` (variance-of-
  Laplacian blur + mean luminance) runs at the top of `GeminiAnalysisService.analyzeFull`;
  poor frames return via the existing retry UI with a recapture reason.
- **Prompt hardening** (`useHardenedPrompt`) — explicit false-positive taxonomy appended
  to the analyze prompt.
- **Scale reasoning** (`useScaleAwareSizing`) — prompt asks Gemini to apply 1/4"–2"
  physical hail-size limits using a scale reference and to report `shingleScaleEstimate`.
  (Model-side, not a brittle post-hoc geometric filter — the px/in reference frame of the
  downsampled JPEG is ambiguous, so dropping markers in-app would risk hiding real damage.)
- **Anti-grid hallucination** (`useHaagDensityCheck`) — near-uniform marker grids get
  their confidence down-weighted (never deleted) in `parseResponse`.
- **HAAG density cross-check** (`useHaagDensityCheck`) — `DecisionEngine` flags a slope
  `verifyWithInspector` when hits/test-square is borderline vs the material threshold or
  implausibly saturated.

Pending (ready, needs Mac-verified wiring):
- **Multi-photo consensus** — `MarkerConsensus.merge(_:)` is implemented as a pure utility
  but intentionally NOT yet called from `QuickInspectionView.runScan` (the sacred camera
  flow). Wire it where a slope's per-photo markers are aggregated, behind
  `useMultiPhotoConsensus`, and build on a Mac.

Later (not started): low-confidence focus/zoom pass; optional direct Gemini API +
`gemini-2.5-pro` report-grade pass; deeper `LocalLearningEngine` calibration coupling.
`GeminiAnalysisService` currently routes through a Rork toolkit proxy (OpenAI-compatible),
not Google directly.

### Phase 3 — UI polish + better APIs (later PR)
`MotionToken` spring system + haptics + reduce-motion; glove-target audit (≥56pt,
≥12pt spacing, thumb-zone CTAs); voice input on free-text fields; empty-state design
pass; Google Places (New) autocomplete; Solar `requiredQuality`/coverage + `MKPolygon`
slope outlines; Live-AR test-square capture guidance. Also: remove off-spec semantic
colors (`mint/amber/crimson/sky`) for strict palette purity if desired; replace
`PlanView`'s hardcoded "12 stops this week" header + week strip with real schedule data.
