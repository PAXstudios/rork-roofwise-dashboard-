# cre8tor — your AI Head of Content

cre8tor is an AI content partner for creators and founders. It decides **what to
post**, writes it **in your voice**, analyzes **what's working**, and helps you
**grow** across LinkedIn, Instagram & X.

This repo contains the full cre8tor web platform — a Next.js 14 app with a
marketing site, authentication, an onboarding "voice training" flow, an AI chat
studio with three modes, a content library, a scheduling calendar, an analytics
dashboard, platform connections, and settings.

> The `ios/` and `backend/` folders are a separate legacy native project and are
> not part of the web app.

## Features

| Area | What it does |
| --- | --- |
| **Landing + Pricing** | Original marketing front door with hero, features, how-it-works, testimonials and a 3-tier pricing page. |
| **Auth** | Email/password + social (demo) sign-up & sign-in, persisted session. |
| **Onboarding** | 6-step wizard: connect accounts → about you → tone sliders → paste writing samples → goals → **train voice**. |
| **Create (Chat)** | "What are we creating today?" studio with 3 modes: **Write in my voice**, **Analyze my posts**, **Interview me**. Streaming responses, quick-actions, copy & save-to-library. |
| **Voice profile** | Bio, niche, audience, 4 tone axes, emoji usage, favorite/avoid words, writing samples — all fed into the model's system prompt. |
| **Library** | Ideas / drafts / scheduled / published, inline editor, status flow, copy, delete. |
| **Calendar** | Month grid with scheduled posts + drag-to-schedule rail. |
| **Analytics** | KPIs, impressions bar chart, top posts, per-platform breakdown — all derived from your data. |
| **Connections** | LinkedIn, Instagram, X, TikTok, YouTube — real OAuth when keys are set, simulated demo handshake otherwise. |
| **Settings** | Voice, account, billing and notification preferences. |

## Getting started

```bash
npm install
cp .env.example .env.local   # optional — the app runs fully in demo mode without keys
npm run dev                  # http://localhost:3000
```

### AI

Set `ANTHROPIC_API_KEY` in `.env.local` to power the chat with Claude. Without a
key, cre8tor runs in **demo mode** with a capable offline response engine so
every screen is fully explorable. Choose the model with `CRE8TOR_MODEL`.

### Connections

Add the relevant `*_CLIENT_ID` / `*_CLIENT_SECRET` values to enable real OAuth
for a platform; otherwise the connect button uses a simulated handshake.

## Tech

- **Next.js 14** (App Router) + **TypeScript**
- **Tailwind CSS** design system (dark theme)
- **Zustand** (localStorage-persisted) for client state
- **@anthropic-ai/sdk** for streaming AI (server-side API routes)

## Structure

```
app/
  page.tsx              marketing landing
  pricing/              pricing page
  login/ signup/        auth
  onboarding/           voice-training wizard
  dashboard/            app shell + Create/Library/Calendar/Analytics/Connections/Settings
  api/chat/             streaming chat endpoint (Claude or demo)
  api/connect/          connection handshake + OAuth callback
components/             Logo, icons, marketing + dashboard UI
lib/                    store, types, prompts, ai client, seed data, hooks
```

Built with [Claude Code](https://claude.com/claude-code).
