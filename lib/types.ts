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
  characterId?: string; // linked UGC character (preset or custom Soul)
  hookStyle?: string;
  voiceStyle: string; // e.g. "energetic", "calm"
  music?: boolean;
  scenes: VideoScene[];
  status: VideoStatus;
  renderUrl?: string; // single stitched MP4 when available
  sceneClips?: { sceneId: string; url: string }[]; // per-scene rendered clips
  engine?: "provider" | "demo";
  provider?: string; // e.g. "higgsfield" | "heygen"
  heygenVideoId?: string;
  score?: VideoScore;
  createdAt: number;
  updatedAt: number;
}

// ── UGC Characters (preset library + custom face-trained "Soul") ──

export interface Character {
  id: string;
  name: string;
  kind: "preset" | "custom";
  // Look/feel description used in prompts
  vibe: string;
  gender?: "female" | "male" | "neutral";
  // Visual: a gradient key (preset) or an uploaded data URL (custom face)
  swatch?: string;
  imageUrl?: string;
  // Higgsfield Soul reference id once a custom face is trained
  soulId?: string;
  // HeyGen identifiers — stock avatar or a custom face "talking photo"
  heygenAvatarId?: string;
  heygenTalkingPhotoId?: string;
  heygenPreviewVideo?: string;
  voiceId?: string;
  status: "ready" | "training" | "failed";
  engine?: "higgsfield" | "heygen" | "demo";
  createdAt: number;
}

// ── Virality score (Higgsfield Virality Predictor) ───────────────

export interface VideoScore {
  overall: number; // 0-100
  hook: number;
  attention: number;
  retention: number;
  notes: string[];
  engine: "higgsfield" | "demo";
  scoredAt: number;
}

// ── AI Video Editor (Stanley Studio-style) ───────────────────────

export interface TranscriptWord {
  text: string;
  start: number; // seconds
  end: number;
  // editing flags
  filler?: boolean; // um / uh / like
  removed?: boolean; // cut from the edit
}

export interface TranscriptSegment {
  id: string;
  start: number;
  end: number;
  text: string;
  words: TranscriptWord[];
  removed?: boolean; // whole segment cut (silence / bad take)
  isSilence?: boolean;
  isAltTake?: boolean; // a weaker duplicate take
}

export type CaptionStyle = "clean" | "bold" | "highlight";

export interface EditProject {
  id: string;
  title: string;
  videoUrl: string; // uploaded source (object URL or hosted)
  durationSec: number;
  aspect: VideoAspect;
  segments: TranscriptSegment[];
  captionStyle: CaptionStyle;
  captionsOn: boolean;
  removeSilence: boolean;
  removeFillers: boolean;
  autoZoom: boolean;
  engine: "whisper" | "demo";
  createdAt: number;
  updatedAt: number;
}
