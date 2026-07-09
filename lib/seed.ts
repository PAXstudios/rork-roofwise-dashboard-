import type { Connection, Draft, SocialPost, Platform, VideoProject, Character } from "./types";

// Deterministic pseudo-random so SSR and client agree (no Date.now/Math.random
// in initial render paths). Seeded generator.
function mulberry32(seed: number) {
  return function () {
    let t = (seed += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rand = mulberry32(42);
const pick = <T,>(arr: T[]) => arr[Math.floor(rand() * arr.length)];
const between = (a: number, b: number) => Math.floor(a + rand() * (b - a));

const DAY = 86_400_000;
// Fixed epoch reference so seed data is stable across renders.
const NOW = 1_752_000_000_000; // ~ mid 2025

const samplePostTexts = [
  "The best content strategy isn't posting more. It's posting what only you can say.",
  "I spent 3 years building in silence. Here's what I'd tell my younger self about audience.",
  "Nobody tells you this about going full-time creator: the hardest part is consistency, not ideas.",
  "Your first 1,000 followers care about your story. Your next 100,000 care about their outcome.",
  "Hot take: engagement bait is a tax on your credibility. Play the long game.",
  "5 lessons from hitting 100k followers (the 3rd one cost me a month of growth).",
  "Stop optimizing your hook and start optimizing your promise.",
  "The algorithm rewards what your audience rewards. Serve them first.",
];

function seedPosts(platform: Platform, n: number): SocialPost[] {
  return Array.from({ length: n }).map((_, i) => {
    const impressions = between(2_000, 90_000);
    return {
      id: `${platform}-post-${i}`,
      platform,
      text: pick(samplePostTexts),
      impressions,
      likes: Math.floor(impressions * (0.02 + rand() * 0.05)),
      comments: Math.floor(impressions * (0.002 + rand() * 0.01)),
      shares: Math.floor(impressions * (0.001 + rand() * 0.006)),
      postedAt: NOW - (i + 1) * between(1, 4) * DAY,
    };
  });
}

export const seedConnections: Connection[] = [
  {
    platform: "linkedin",
    connected: true,
    handle: "in/aria-creates",
    followers: 24_800,
    connectedAt: NOW - 60 * DAY,
    recentPosts: seedPosts("linkedin", 8),
  },
  {
    platform: "instagram",
    connected: false,
  },
  {
    platform: "x",
    connected: true,
    handle: "@aria_creates",
    followers: 41_200,
    connectedAt: NOW - 90 * DAY,
    recentPosts: seedPosts("x", 8),
  },
  { platform: "tiktok", connected: false },
  { platform: "youtube", connected: false },
];

export const seedDrafts: Draft[] = [
  {
    id: "draft-1",
    title: "Why consistency beats virality",
    body:
      "Everyone chases the viral post. But the creators who win are the ones who show up on the boring Tuesday when nobody's watching.\n\nHere's the framework I use to stay consistent for 200+ days straight 👇",
    platform: "linkedin",
    status: "scheduled",
    createdAt: NOW - 2 * DAY,
    updatedAt: NOW - 1 * DAY,
    scheduledAt: NOW + 1 * DAY,
    tags: ["growth", "mindset"],
  },
  {
    id: "draft-2",
    title: "3 hooks that doubled my reach",
    body:
      "I A/B tested 40 hooks last month. Three of them consistently beat everything else. Steal them:",
    platform: "x",
    status: "draft",
    createdAt: NOW - 3 * DAY,
    updatedAt: NOW - 3 * DAY,
    tags: ["hooks", "copywriting"],
  },
  {
    id: "draft-3",
    title: "Behind the scenes: my content system",
    body: "A peek at the exact Notion + cre8tor workflow I use to ship 5 posts a week without burning out.",
    platform: "instagram",
    status: "idea",
    createdAt: NOW - 5 * DAY,
    updatedAt: NOW - 5 * DAY,
    tags: ["systems", "bts"],
  },
  {
    id: "draft-4",
    title: "The $0 growth playbook",
    body:
      "You don't need ads. You need a repeatable promise and the patience to keep it.\n\nThis post broke 500k impressions with zero spend. Here's the breakdown.",
    platform: "linkedin",
    status: "published",
    createdAt: NOW - 12 * DAY,
    updatedAt: NOW - 12 * DAY,
    tags: ["growth"],
    metrics: { impressions: 512_400, likes: 8_900, comments: 640 },
  },
];

export const DEMO_ACCENTS = [
  "#6366f1",
  "#a855f7",
  "#ec4899",
  "#f97316",
  "#14b8a6",
  "#3b82f6",
];

// Gradient backgrounds used by the in-browser video player scenes.
export const VIDEO_BG: Record<string, string> = {
  indigo: "linear-gradient(135deg,#4f46e5,#a855f7)",
  sunset: "linear-gradient(135deg,#f97316,#ec4899)",
  ocean: "linear-gradient(135deg,#0ea5e9,#14b8a6)",
  violet: "linear-gradient(135deg,#7c3aed,#db2777)",
  lime: "linear-gradient(135deg,#65a30d,#0d9488)",
  night: "linear-gradient(135deg,#1e1b4b,#4c1d95)",
  ember: "linear-gradient(135deg,#dc2626,#f59e0b)",
  slate: "linear-gradient(135deg,#334155,#0f172a)",
};
export const VIDEO_BG_KEYS = Object.keys(VIDEO_BG);

export const seedCharacters: Character[] = [
  { id: "char-maya", name: "Maya", kind: "preset", vibe: "energetic Gen-Z creator, warm and fast-talking", gender: "female", swatch: "sunset", status: "ready", engine: "demo", createdAt: NOW - 30 * DAY },
  { id: "char-jordan", name: "Jordan", kind: "preset", vibe: "calm expert, measured and trustworthy", gender: "male", swatch: "ocean", status: "ready", engine: "demo", createdAt: NOW - 30 * DAY },
  { id: "char-alex", name: "Alex", kind: "preset", vibe: "hype street-style creator, bold and punchy", gender: "neutral", swatch: "ember", status: "ready", engine: "demo", createdAt: NOW - 30 * DAY },
  { id: "char-sam", name: "Sam", kind: "preset", vibe: "friendly girl-next-door, relatable and bubbly", gender: "female", swatch: "violet", status: "ready", engine: "demo", createdAt: NOW - 30 * DAY },
  { id: "char-chris", name: "Chris", kind: "preset", vibe: "authoritative founder, sharp and confident", gender: "male", swatch: "night", status: "ready", engine: "demo", createdAt: NOW - 30 * DAY },
  { id: "char-nina", name: "Nina", kind: "preset", vibe: "aesthetic lifestyle creator, soft and aspirational", gender: "female", swatch: "lime", status: "ready", engine: "demo", createdAt: NOW - 30 * DAY },
];

export const seedVideos: VideoProject[] = [
  {
    id: "vid-seed-1",
    kind: "ugc",
    title: "3 mistakes killing your reach",
    prompt: "A punchy UGC hook about the 3 mistakes creators make that kill their reach",
    platform: "instagram",
    aspect: "9:16",
    persona: "Maya — energetic creator",
    hookStyle: "Contrarian",
    voiceStyle: "energetic",
    status: "ready",
    engine: "demo",
    createdAt: NOW - 4 * DAY,
    updatedAt: NOW - 4 * DAY,
    scenes: [
      {
        id: "s1",
        durationSec: 3,
        voiceover: "Stop making these 3 mistakes that are quietly killing your reach.",
        caption: "3 mistakes killing your reach",
        visual: "Creator talking to camera, close up, quick zoom",
        bg: "sunset",
      },
      {
        id: "s2",
        durationSec: 4,
        voiceover: "One: you're posting for the algorithm instead of your audience.",
        caption: "#1 Posting for the algorithm",
        visual: "Text overlay, phone scrolling b-roll",
        bg: "violet",
      },
      {
        id: "s3",
        durationSec: 4,
        voiceover: "Two: your hook takes too long. You have one second, not ten.",
        caption: "#2 Slow hooks",
        visual: "Stopwatch graphic, fast cut",
        bg: "ocean",
      },
      {
        id: "s4",
        durationSec: 4,
        voiceover: "Three: no clear next step. Tell them exactly what to do.",
        caption: "#3 No call to action",
        visual: "Creator pointing, arrow graphic",
        bg: "ember",
      },
      {
        id: "s5",
        durationSec: 3,
        voiceover: "Fix these and watch your reach climb. Follow for more.",
        caption: "Follow for more →",
        visual: "Smiling creator, subscribe animation",
        bg: "indigo",
      },
    ],
  },
];
