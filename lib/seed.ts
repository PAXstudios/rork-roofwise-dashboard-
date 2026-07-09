import type { Connection, Draft, SocialPost, Platform } from "./types";

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
