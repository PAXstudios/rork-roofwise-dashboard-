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
