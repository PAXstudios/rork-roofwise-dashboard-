# Contributing to RoofWise

> **This file is the contract for any AI agent (or human) making changes to this project.** Read it in full before touching code.

RoofWise is a context-engineered project. The single source of truth for *intent, scope, and history* is [`PROMPT_LOG.md`](./PROMPT_LOG.md). Code is downstream of that log — if the log and the code disagree, the log wins until a new prompt resolves it.

---

## The 3 Rules for AI Agents

If you are an AI agent (Rork, Claude, GPT, Cursor, etc.) opening this project, you **must** follow these three rules on every change. No exceptions.

### Rule 1 — Read `PROMPT_LOG.md` *first*

Before making **any** change to this codebase:

1. Open `PROMPT_LOG.md` and read, at minimum:
   - The **Context Summary** section.
   - The **Drift Warning** section (the 10 hardened constraints).
   - The **Constraint Verification Protocol** (the 7-step checklist).
   - The **last 3 prompt entries** in Prompt History.
2. If the user's request appears to contradict any item in the Drift Warning, **call it out explicitly in your response** and confirm before changing it.
3. Ground all decisions in what the log already says. Do not re-derive intent from the codebase alone — the log captures *why* things are the way they are.

### Rule 2 — Append a new entry to `PROMPT_LOG.md` *after every change*

Every change ships with a log entry. After implementing the user's request, append a new entry at the bottom of the **Prompt History** section using the template below.

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

Required fields in every entry:

- **Today's date** in `YYYY-MM-DD` format.
- **Sequential number** (`#NN`) — increment from the last entry.
- **What was changed** — the decisions and behavior, not just the diff.
- **Files modified** — every file you touched, with a one-line "what changed" note.

The Prompt History is **append-only**. Never edit or delete an existing entry; if a decision is reversed, write a new entry that says so.

### Rule 3 — Refresh the Context Summary every 5+ new entries

The **Context Summary** at the top of `PROMPT_LOG.md` is the fast-path onboarding for the next agent. Keep it accurate.

- Check the `Last refreshed` date at the top of the Context Summary.
- Count how many new entries have been appended to Prompt History since that date.
- If that count is **5 or more**, refresh the Context Summary in the same change you're making:
  - Update the "Where we are today" bullets.
  - Update "What's mocked / placeholder."
  - Update "What's not started."
  - Update the `Last refreshed` date and the entry number it was refreshed after.
- If the count is fewer than 5, leave the Context Summary alone.

The Drift Warning, Constraint Verification Protocol, Project Overview, IA, Feature Backlog, and Key Technical Decisions sections may also be updated in place when relevant — but the Prompt History is always append-only.

---

## Constraint Verification Checklist

Before you finish a change, run through this checklist (also documented inside `PROMPT_LOG.md`):

1. ☐ Re-read the Context Summary, Drift Warning, and the last 3 prompt entries in `PROMPT_LOG.md`.
2. ☐ State which Drift Warning items the request touches (if any) and confirm they're being changed intentionally.
3. ☐ Verify the Damage Taxonomy, HAAG grades, and Claim Worthiness badges are still intact.
4. ☐ Verify the Dashboard CTAs are still **Quick Inspection** and **New Job**.
5. ☐ Verify the Quick Inspection flow still: camera → slope dropdown → multi-photo capture → Gemini analysis → damage score + claim worthiness → HAAG Claim Packet sheet.
6. ☐ Append a new entry to `PROMPT_LOG.md` Prompt History.
7. ☐ If this is the 5th+ entry since the last Context Summary refresh, refresh the Context Summary in the same change.

---

## Coding Conventions

- **Stack:** Expo + React Native + TypeScript. Mobile-first.
- **Style:** Card-based, generous whitespace, rounded corners, subtle shadows. No web-style dense tables.
- **State of features:** see the Feature Backlog in `PROMPT_LOG.md` — don't re-implement what's already shipped, and don't silently demote shipped features.
- **AI vision:** Gemini 1.5 Flash via REST. Don't switch providers without an explicit prompt.
- **Secrets:** Use `EXPO_PUBLIC_*` env vars for client-side keys. Placeholder constants are acceptable only when a follow-up is logged.

---

## For Human Contributors

The same rules apply. Read `PROMPT_LOG.md` first, append an entry after your change, refresh the Context Summary every 5 entries. The discipline is what keeps the project coherent across many sessions and many agents.
