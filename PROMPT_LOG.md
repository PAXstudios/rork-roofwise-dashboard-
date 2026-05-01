# RoofWise — Prompt Log

A structured context engineering log for the RoofWise project. Every meaningful prompt, decision, and implementation step is captured here so that future agents (and humans) can quickly reconstruct intent, scope, and history.

---

## How to use this log

- **Append, don't rewrite.** Add a new entry at the bottom for each prompt or change.
- **Be specific.** Capture the *why*, not just the *what*.
- **Link to files.** Reference the screens/components touched so context is easy to recover.
- **Keep entries short but complete.** One section per prompt.

### Entry template

```md
## [YYYY-MM-DD] #NN — Short title

**Prompt (verbatim or summarized):**
> ...

**Intent / Goal:**
- ...

**Decisions made:**
- ...

**Files touched:**
- `path/to/file.tsx` — what changed

**Open questions / Follow-ups:**
- ...
```

---

## Project Overview

**Name:** RoofWise
**Type:** Mobile-first SaaS CRM + AI assistant for roofing companies
**Persona:** Elite Forensic Roofing Consultant
**Platform:** React Native (Expo) — iOS + Android, mobile-first design
**Primary user:** Roofing contractors, adjusters, inspectors

### Core value proposition
A field-ready CRM and AI inspection tool that helps roofing pros:
1. Triage leads, jobs, and storm-impacted properties from one dashboard.
2. Run **AI + LiDAR-powered Quick Inspections** to detect hail, wind, and shingle damage.
3. Generate **HAAG-standard claim packets** ready for adjusters and insurers.

### Brand & UX direction
- Clean, minimal, card-based layout
- Lots of white space, rounded corners, subtle shadows
- Accent color suitable for a roofing/tech brand
- Mobile: scrollable card stack, bottom nav, central `+` quick action button

---

## Information Architecture

**Primary navigation (bottom tab bar on mobile):**
- Dashboard
- Leads
- Map
- Inspections
- Jobs
- Storm Intel
- Reports
- Settings

**Central `+` button:** quick actions (Quick Inspection, New Job, New Lead).

---

## Feature Backlog & Status

| # | Feature | Status |
|---|---|---|
| 1 | Dashboard layout (KPIs, schedule, pipeline, map, AI queue, tasks, activity) | Implemented |
| 2 | Top bar (search, filters, profile) + left/bottom nav | Implemented |
| 3 | Recent Jobs strip (photos + address overlay + status badge) | Implemented |
| 4 | Storm Map with 4-year hail/wind history, year + type filters | Implemented |
| 5 | Storm event detail sheet (date, hail size, wind speed, properties) | Implemented |
| 6 | Quick Inspection — camera flow | Implemented |
| 7 | Slope selector dropdown (Left/Right/Front/Back/Ridge/Valley/etc.) | Implemented |
| 8 | Shingle Grid + LiDAR Mesh overlays toggle | Implemented |
| 9 | Pitch & Elevation HUD (CoreMotion + CoreLocation) | Implemented |
| 10 | Multi-photo capture strip with slope labels | Implemented |
| 11 | Gemini 1.5 Flash Vision analysis of captured photos | Implemented |
| 12 | Expanded AI damage taxonomy (10+ categories, severity, confidence) | Implemented |
| 13 | Damage Score (0–100) + Claim Worthiness badge | Implemented |
| 14 | HAAG-standards grading + Claim Packet sheet | Implemented |
| 15 | Quick Inspection / New Job dashboard buttons (replaced KPI cards) | Implemented |
| 16 | Subscriptions / paywall (RevenueCat) | Not started |
| 17 | Auth & multi-user team accounts | Not started |
| 18 | Backend persistence (Supabase) for jobs, inspections, claim packets | Not started |
| 19 | Push notifications for storm alerts | Not started |
| 20 | Adjuster-facing PDF export of claim packet | Not started |

---

## Key Technical Decisions

- **Framework:** Expo + React Native, TypeScript.
- **AI Vision:** Google Gemini 1.5 Flash via `generativelanguage.googleapis.com` REST endpoint. API key held in a constant placeholder `GEMINI_API_KEY` until env wiring is done.
- **Sensors:**
  - Pitch via `expo-sensors` accelerometer (mock values in simulator: 5:12, 22.6°).
  - Elevation via `expo-location` altitude (mock: 589 ft in simulator).
- **Camera:** `expo-camera` with custom HUD overlays (grid / LiDAR mesh / scanning passes).
- **HAAG grading:** client-side rules engine over the Gemini-derived damage findings.
- **Storm data:** mocked 4-year dataset (2022–2025) with hail size + wind speed per event.

---

## Prompt History

> Earlier prompts have been compacted; this section starts the durable log going forward.

### [2026-05-01] #01 — Establish prompt log

**Prompt (summarized):**
> Create `PROMPT_LOG.md` in the project root as a structured context engineering log for RoofWise.

**Intent / Goal:**
- Give every future agent a single source of truth for intent, scope, and history.
- Provide a consistent template so future entries stay structured.

**Decisions made:**
- Log lives at repo root as `PROMPT_LOG.md`.
- Each new prompt gets a numbered, dated entry using the template above.
- High-level project overview, IA, feature status, and key technical decisions live near the top and are updated in place; per-prompt entries are append-only below.

**Files touched:**
- `PROMPT_LOG.md` — created.

**Open questions / Follow-ups:**
- Wire `GEMINI_API_KEY` to a real env var (`EXPO_PUBLIC_GEMINI_API_KEY`).
- Decide on backend (Supabase) schema for inspections, photos, and claim packets.
- Plan RevenueCat paywall placement (likely gated: unlimited Quick Inspections + Claim Packet export).
