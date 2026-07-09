// ── Core domain types for cre8tor ──────────────────────────────

export type Platform = "linkedin" | "instagram" | "x" | "tiktok" | "youtube";

export type ChatMode = "voice" | "analyze" | "interview" | "chat";

export interface User {
  id: string;
  name: string;
  email: string;
  avatarColor: string;
  plan: "trial" | "creator" | "pro";
  createdAt: number;
  onboarded: boolean;
}

export interface VoiceProfile {
  // Free-form description of who the creator is
  bio: string;
  niche: string;
  audience: string;
  // Tone sliders 0-100
  tone: {
    formal: number; // 0 casual → 100 formal
    playful: number; // 0 serious → 100 playful
    bold: number; // 0 measured → 100 bold
    technical: number; // 0 simple → 100 technical
  };
  // Words / phrases the creator uses and avoids
  favoriteWords: string[];
  avoidWords: string[];
  emojiUsage: "none" | "light" | "heavy";
  // Sample posts pasted during training — the source of "voice"
  samples: string[];
  goals: string[];
  trained: boolean;
}

export interface Connection {
  platform: Platform;
  connected: boolean;
  handle?: string;
  followers?: number;
  connectedAt?: number;
  // simulated recent stats used by Analyze mode
  recentPosts?: SocialPost[];
  // token presence for real publishing (never the token value in client state)
  canPublish?: boolean;
}

export interface SocialPost {
  id: string;
  platform: Platform;
  text: string;
  impressions: number;
  likes: number;
  comments: number;
  shares: number;
  postedAt: number;
}

export type DraftStatus = "idea" | "draft" | "scheduled" | "published";

export interface Draft {
  id: string;
  title: string;
  body: string;
  platform: Platform;
  status: DraftStatus;
  createdAt: number;
  updatedAt: number;
  scheduledAt?: number;
  tags: string[];
  // performance once published (simulated)
  metrics?: { impressions: number; likes: number; comments: number };
  // publishing
  publishedAt?: number;
  publishedUrl?: string;
  publishEngine?: "live" | "demo";
}

export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  createdAt: number;
  // optional structured action attached to an assistant message
  draftSuggestion?: { platform: Platform; body: string };
}

export interface Conversation {
  id: string;
  title: string;
  mode: ChatMode;
  messages: ChatMessage[];
  createdAt: number;
  updatedAt: number;
}

// ── Video / UGC ────────────────────────────────────────────────

export type VideoKind = "video" | "ugc";
export type VideoAspect = "9:16" | "1:1" | "16:9";
export type VideoStatus = "draft" | "rendering" | "ready" | "failed";

// A single storyboard beat. The in-browser player animates these; a real
// provider (when configured) renders them to an MP4.
export interface VideoScene {
  id: string;
  durationSec: number;
  voiceover: string; // spoken narration / TTS line
  caption: string; // short on-screen text overlay
  visual: string; // description of the b-roll / shot
  // one of a fixed palette of gradient keys used by the demo player
  bg: string;
}

export interface VideoProject {
  id: string;
  kind: VideoKind;
  title: string;
  prompt: string;
  platform: Platform;
  aspect: VideoAspect;
  // UGC-specific
  persona?: string; // avatar / creator persona
  hookStyle?: string;
  voiceStyle: string; // e.g. "energetic", "calm"
  scenes: VideoScene[];
  status: VideoStatus;
  renderUrl?: string; // single stitched MP4 when available
  sceneClips?: { sceneId: string; url: string }[]; // per-scene rendered clips
  engine?: "provider" | "demo";
  provider?: string; // e.g. "higgsfield"
  createdAt: number;
  updatedAt: number;
}
