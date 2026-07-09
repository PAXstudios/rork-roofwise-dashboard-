// HeyGen integration — real human UGC avatars with lip-synced speech.
// Configured with HEYGEN_API_KEY. All calls are server-side only.

const API = "https://api.heygen.com";
const UPLOAD = "https://upload.heygen.com";

export function hasHeyGen(): boolean {
  return Boolean(process.env.HEYGEN_API_KEY);
}

function headers(extra: Record<string, string> = {}) {
  return {
    "X-Api-Key": process.env.HEYGEN_API_KEY || "",
    ...extra,
  };
}

export interface HeyGenAvatar {
  avatar_id: string;
  avatar_name: string;
  gender: string | null;
  preview_image_url: string;
  preview_video_url: string;
  premium: boolean;
}

export interface HeyGenVoice {
  voice_id: string;
  name: string;
  language: string;
  gender: string | null;
}

export async function listAvatars(limit = 60): Promise<HeyGenAvatar[]> {
  const res = await fetch(`${API}/v2/avatars`, { headers: headers() });
  if (!res.ok) throw new Error(`HeyGen avatars ${res.status}`);
  const data = await res.json();
  const avatars: HeyGenAvatar[] = data?.data?.avatars || [];
  // Free-tier friendly: surface non-premium first.
  return [...avatars]
    .sort((a, b) => Number(a.premium) - Number(b.premium))
    .slice(0, limit);
}

export interface HeyGenVoiceFull extends HeyGenVoice {
  preview_audio?: string;
  emotion_support?: boolean;
  support_pause?: boolean;
}

let voiceCache: HeyGenVoiceFull[] | null = null;
export async function listVoices(): Promise<HeyGenVoiceFull[]> {
  if (voiceCache) return voiceCache;
  const res = await fetch(`${API}/v2/voices`, { headers: headers() });
  if (!res.ok) throw new Error(`HeyGen voices ${res.status}`);
  const data = await res.json();
  const voices = (data?.data?.voices || []) as HeyGenVoiceFull[];
  // Drop placeholder/empty entries HeyGen returns at the top of the list.
  voiceCache = voices.filter(
    (v) => v.voice_id && v.name && !/voice-name-here/i.test(v.name)
  );
  return voiceCache;
}

// Picks a sensible default English voice matching the character's gender.
export async function defaultVoice(gender?: string | null): Promise<string> {
  const voices = await listVoices();
  const english = voices.filter((v) => (v.language || "").toLowerCase().startsWith("english"));
  const pool = english.length ? english : voices;
  const match = gender
    ? pool.find((v) => (v.gender || "").toLowerCase() === gender.toLowerCase())
    : null;
  return (match || pool[0])?.voice_id || "";
}

function dimensionFor(aspect: string): { width: number; height: number } {
  if (aspect === "1:1") return { width: 720, height: 720 };
  if (aspect === "16:9") return { width: 1280, height: 720 };
  return { width: 720, height: 1280 };
}

export interface GenerateUgcInput {
  script: string;
  aspect: string;
  avatarId?: string; // stock avatar
  talkingPhotoId?: string; // custom face
  voiceId?: string;
  gender?: string | null;
  background?: string;
}

export async function generateUgcVideo(input: GenerateUgcInput): Promise<{ videoId: string }> {
  const voice_id = input.voiceId || (await defaultVoice(input.gender));
  const character = input.talkingPhotoId
    ? { type: "talking_photo", talking_photo_id: input.talkingPhotoId }
    : { type: "avatar", avatar_id: input.avatarId, avatar_style: "normal" };

  const res = await fetch(`${API}/v2/video/generate`, {
    method: "POST",
    headers: headers({ "Content-Type": "application/json" }),
    body: JSON.stringify({
      video_inputs: [
        {
          character,
          voice: { type: "text", input_text: input.script.slice(0, 1400), voice_id },
          background: { type: "color", value: input.background || "#101018" },
        },
      ],
      dimension: dimensionFor(input.aspect),
    }),
  });
  const data = await res.json();
  if (!res.ok || data?.error) {
    throw new Error(data?.error?.message || data?.error || `HeyGen generate ${res.status}`);
  }
  return { videoId: data.data.video_id as string };
}

export interface VideoStatus {
  status: "waiting" | "pending" | "processing" | "completed" | "failed";
  videoUrl?: string;
  thumbnailUrl?: string;
  error?: string;
}

export async function getVideoStatus(videoId: string): Promise<VideoStatus> {
  const res = await fetch(
    `${API}/v1/video_status.get?video_id=${encodeURIComponent(videoId)}`,
    { headers: headers() }
  );
  const data = await res.json();
  const d = data?.data || {};
  return {
    status: d.status || "processing",
    videoUrl: d.video_url || undefined,
    thumbnailUrl: d.thumbnail_url || undefined,
    error: d.error?.message || d.error || undefined,
  };
}

// Turns an uploaded/camera-captured face photo into a HeyGen "talking photo"
// that can present UGC videos.
export async function uploadTalkingPhoto(
  imageDataUrl: string
): Promise<{ talkingPhotoId: string }> {
  const m = imageDataUrl.match(/^data:(image\/\w+);base64,(.+)$/);
  if (!m) throw new Error("Expected an image data URL");
  const contentType = m[1] === "image/png" ? "image/png" : "image/jpeg";
  const buf = Buffer.from(m[2], "base64");

  const res = await fetch(`${UPLOAD}/v1/talking_photo`, {
    method: "POST",
    headers: headers({ "Content-Type": contentType }),
    body: buf,
  });
  const data = await res.json();
  const id = data?.data?.talking_photo_id;
  if (!res.ok || !id) {
    throw new Error(data?.msg || data?.error || `Talking photo upload ${res.status}`);
  }
  return { talkingPhotoId: id as string };
}
