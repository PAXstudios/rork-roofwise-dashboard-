# RoofWise — Prompt Log

A structured context engineering log for the RoofWise project. Every meaningful prompt, decision, and implementation step is captured here so that future agents (and humans) can quickly reconstruct intent, scope, and history.

---

## How to use this log

- **Append, don't rewrite.** Add a new entry at the bottom for each prompt or change.
- **Be specific.** Capture the *why*, not just the *what*.
- **Link to files.** Reference the screens/components touched so context is easy to recover.
- **Keep entries short but complete.** One section per prompt.
- **Re-summarize.** Every 5 new entries, refresh the **Context Summary** section below so the top of this file stays current.

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

## Context Summary

> Last refreshed: 2026-05-01 (after entry #07). Refresh this section any time the log grows by 5+ entries since this date.

**Product in one line:** RoofWise is a mobile-first CRM + AI inspection tool for roofing contractors that turns a phone into a forensic roof-damage scanner and generates HAAG-standard claim packets for insurance adjusters.

**Where we are today:**
- Dashboard, bottom nav, and primary CRM surfaces (Leads, Jobs, Map, Inspections, Storm Intel, Reports, Settings) are in place.
- Dashboard is **scrollable** and includes: Quick Inspection + New Job CTAs (replacing the old "Active Leads / Inspections Today" KPI cards), Recent Jobs photo strip with status badges, enhanced 4-year Storm Map with year + type filters and event detail sheet.
- **Quick Inspection** is the hero feature: live camera with slope selector dropdown, shingle grid + LiDAR mesh overlay toggle, pitch + elevation HUD (CoreMotion + CoreLocation, mocked in simulator), multi-photo capture strip, Gemini 1.5 Flash Vision analysis of captured photos, expanded damage taxonomy with severity + confidence %, Damage Score (0–100), Claim Worthiness badge, and a HAAG-graded Claim Packet sheet.

**What's mocked / placeholder:**
- `GEMINI_API_KEY` is a constant placeholder; needs to move to `EXPO_PUBLIC_GEMINI_API_KEY`.
- Storm dataset (2022–2025) is mocked client-side.
- Pitch + elevation fall back to fixed mock values in simulator (5:12 / 22.6° / 589 ft).
- Recent Jobs uses 5 hardcoded Plano/Frisco/McKinney TX entries.

**What's not started:**
- RevenueCat paywall, auth/team accounts, Supabase persistence, push storm alerts, PDF export of claim packets.

---

## Drift Warning

Every agent working on this project must read this section before making changes. The following constraints have been established by the founder and **must not silently drift**:

1. **Quick Inspection is the hero feature.** Do not bury it behind extra steps, gate it behind paywalls without explicit instruction, or replace its CTA on the Dashboard.
2. **Dashboard CTAs are "Quick Inspection" and "New Job".** The old "Active Leads" / "Inspections Today" KPI buttons have been intentionally removed — do not reintroduce them.
3. **Dashboard must remain scrollable** so the storm map and Recent Jobs are always reachable.
4. **Slope selector dropdown** replaced the Slope / 3D Scan / Macro buttons in the camera. Do not revert.
5. **Damage taxonomy is fixed:** Hail Hits, Wind Creasing, Missing Shingles, Granule Loss, Blistering, Cracking/Splitting, Flashing Damage, Algae/Moss, Bruising, Structural Sagging, Ponding Water. Each item carries severity (None / Minor / Moderate / Severe) and a confidence %.
6. **HAAG grades are fixed:** "No Functional Damage", "Functional Damage — Hail", "Functional Damage — Wind", "Functional Damage — Combined Peril".
7. **Claim Worthiness badges are fixed:** Not Claimable / Borderline / Claimable / Urgent.
8. **Mobile-first, card-based, lots of whitespace, rounded corners, subtle shadows.** No web-style dense tables.
9. **Gemini 1.5 Flash Vision** is the chosen AI model. Do not swap to a different provider without an explicit prompt.
10. **Append, don't rewrite** the Prompt History section. Existing entries are immutable history.

If a new prompt seems to contradict any of the above, surface it explicitly in your response before changing it.

---

## Constraint Verification Protocol

Before completing any change, the agent must:

1. **Re-read** `PROMPT_LOG.md` (this file) — at minimum the Context Summary, Drift Warning, and the last 3 prompt entries.
2. **Diff intent vs. request.** State, in your response, which Drift Warning items the request touches and confirm the user is intentionally changing them.
3. **Verify the Damage Taxonomy, HAAG grades, and Claim Worthiness badges** are still intact in code after your change. If you removed or renamed one, call it out.
4. **Verify the Dashboard CTAs** are still "Quick Inspection" and "New Job" (unless the prompt explicitly changes them).
5. **Verify the Quick Inspection flow** still: launches camera → slope dropdown → capture (multi-photo) → Gemini analysis → results with damage score + claim worthiness → HAAG Claim Packet sheet.
6. **Append a new prompt entry** to the Prompt History section using the template. Include date, prompt summary, intent, decisions, files touched, and any open follow-ups.
7. **If this is the 5th entry since the last Context Summary refresh**, refresh the Context Summary at the top of this file in the same change.

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

### [2026-05-01] #01 — Dashboard CTAs swapped to Quick Inspection + New Job

**Prompt (summarized):**
> Remove the "Active Leads" and "Inspections Today" buttons from the dashboard and replace them with a "Quick Inspection" button and a "New Job" button.

**Intent / Goal:**
- Push the hero feature (Quick Inspection) to the top of the dashboard.
- Reduce passive KPI noise; emphasize action.

**Decisions made:**
- Two side-by-side primary CTA cards at the top of the dashboard.
- Quick Inspection routes to the camera flow; New Job routes to job creation.

**Files touched:**
- Dashboard screen — removed KPI cards, added two CTA cards.

**Open questions / Follow-ups:**
- Confirm where "Active Leads" count surfaces instead (likely Leads tab badge).

---

### [2026-05-01] #02 — Make dashboard scrollable

**Prompt (verbatim):**
> please make this scrollable. i cannot see the map or the recent inspections

**Intent / Goal:**
- Ensure storm map and Recent Inspections are reachable below the fold on small devices.

**Decisions made:**
- Wrap dashboard content in a `ScrollView` with safe area + bottom-nav padding.

**Files touched:**
- Dashboard screen — wrapped content in ScrollView, fixed bottom inset.

**Open questions / Follow-ups:**
- Consider sticky headers for the section titles on long scroll.

---

### [2026-05-01] #03 — Quick Inspection camera (LiDAR + AI scaffold)

**Prompt (summarized):**
> Quick Inspection should open a camera that uses LiDAR + AI to analyze hail roof shingle damage. Inputs: hail hits, wind-creased shingles, missing shingles, functional damage present, granule loss, number of slopes, age of roof, material type, pitch.

**Intent / Goal:**
- Establish the hero camera flow with a clear set of structural inputs.

**Decisions made:**
- Build an `expo-camera` screen with a HUD that captures all listed structural inputs.
- Treat LiDAR as an overlay/visual concept (mesh) on devices without LiDAR; functional pipeline is photo → AI.
- Damage inputs become the seed for the later damage taxonomy.

**Files touched:**
- Quick Inspection camera screen — initial implementation.
- Inspection results screen — initial structural input fields.

**Open questions / Follow-ups:**
- Decide which AI provider analyzes the photo (resolved in #06).

---

### [2026-05-01] #04 — Three major dashboard enhancements

**Prompt (summarized):**
> Add Recent Jobs strip, enhanced Storm Map (year/type filters, intensity halos, event sheet, stats bar), and expanded AI damage taxonomy with Damage Score + Claim Worthiness; update scanning animation with progressive passes.

**Intent / Goal:**
- Make the dashboard feel like a real field tool with live storm intel.
- Make the inspection results feel forensic, not generic.

**Decisions made:**
- Recent Jobs: 5 mock Plano/Frisco/McKinney TX cards, color-coded badges (Done=green, Active=orange, Awaiting Adjuster=blue, Scheduled=gray).
- Storm Map filters: 2022 / 2023 / 2024 / 2025 / All; Hail / Wind / Both; halos yellow=light, orange=moderate, red=severe.
- Damage taxonomy frozen (see Drift Warning #5).
- Damage Score 0–100; Claim Worthiness badges: Not Claimable / Borderline / Claimable / Urgent.
- Scanning passes: Detecting hail → Analyzing granules → Checking wind damage → Inspecting flashing → Generating report.

**Files touched:**
- Dashboard — Recent Jobs strip, expanded Storm Map card.
- Storm event detail sheet — new component.
- Inspection results — expanded damage list, score, worthiness.
- Scanning animation — multi-pass labels.

**Open questions / Follow-ups:**
- Real storm data source (NOAA / IBHS?) post-MVP.

---

### [2026-05-01] #05 — Quick Inspection major upgrade (Gemini + HUD + HAAG)

**Prompt (summarized):**
> Integrate Gemini 1.5 Flash Vision; replace slope buttons with a slope dropdown; add Shingle Grid / LiDAR Mesh toggle; live Pitch + Elevation HUD; HAAG-grade Claim Packet; multi-photo capture strip.

**Intent / Goal:**
- Transform Quick Inspection from mock to a credible forensic tool with real AI vision and engineering-grade output.

**Decisions made:**
- Gemini 1.5 Flash via REST; API key held as `GEMINI_API_KEY` constant for now.
- Slope dropdown options frozen (Left/Right/Front/Back/Ridge/Valley/Gutters & Fascia/Soffit/Chimney & Flashing/Pipe Boots & Vents/Skylights/Hip Caps/Drip Edge/Siding/Windows & Trim/Garage Door/Downspouts/Foundation/Fence/Gate). Selected slope is overlaid on the photo and included in the Gemini prompt.
- Overlay toggle: OFF / SHINGLE GRID / LIDAR MESH.
- Pitch via accelerometer in degrees and X:12; elevation via GPS altitude in feet. Mock values when sensors unavailable.
- HAAG grades frozen (see Drift Warning #6).
- Claim Packet sheet shows HAAG grade, damage type, affected squares, Replace vs Repair recommendation, per-slope findings.
- Photo strip at bottom of camera with slope labels and count badge.

**Files touched:**
- Quick Inspection camera screen — slope dropdown, overlay toggle, HUD, photo strip.
- Gemini service — new module for vision analysis.
- HAAG grading service — rules engine over damage findings.
- Claim Packet sheet — new full-screen presentation.

**Open questions / Follow-ups:**
- Move `GEMINI_API_KEY` to `EXPO_PUBLIC_GEMINI_API_KEY`.
- PDF export of Claim Packet for adjusters.

---

### [2026-05-01] #06 — Establish Prompt Log

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

---

### [2026-05-01] #07 — Add CONTRIBUTING.md and harden Prompt Log

**Prompt (summarized):**
> Add a `CONTRIBUTING.md` instructing any AI agent to (1) read `PROMPT_LOG.md` first, (2) append a new entry after every change with date + what changed + files modified, (3) re-summarize the Context Summary every 5+ entries. Also expand `PROMPT_LOG.md` to include a full Context Summary, a Drift Warning, a Constraint Verification Protocol, and all 7 prompt log entries.

**Intent / Goal:**
- Lock in context engineering discipline so future agents don't drift on hero features (Quick Inspection, HAAG grades, damage taxonomy, dashboard CTAs).
- Make the project self-onboarding for any new agent.

**Decisions made:**
- `CONTRIBUTING.md` is the AI agent contract; `PROMPT_LOG.md` is the source of truth.
- Context Summary refresh cadence: every 5 new entries (next refresh due at entry #12).
- Drift Warning enumerates the 10 hardened constraints; Constraint Verification Protocol is the 7-step checklist agents must run before finishing a change.

**Files touched:**
- `PROMPT_LOG.md` — added Context Summary, Drift Warning, Constraint Verification Protocol; backfilled entries #01–#05; renumbered prior log entry to #06; added this entry #07.
- `CONTRIBUTING.md` — created.

**Open questions / Follow-ups:**
- After entry #12, refresh the Context Summary section.
- Consider a CI check that fails if a PR doesn't add a new entry to `PROMPT_LOG.md`.
