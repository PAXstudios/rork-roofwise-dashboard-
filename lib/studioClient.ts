"use client";

import type { VideoScene, VideoScore, TranscriptSegment } from "./types";

export async function createCharacter(name: string, images: string[]): Promise<{
  ok: boolean;
  soulId?: string;
  talkingPhotoId?: string;
  engine: "higgsfield" | "heygen" | "demo";
  error?: string;
}> {
  const res = await fetch("/api/character/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, images }),
  });
  return res.json();
}

// ── HeyGen ─────────────────────────────────────────────────────

export interface HeyGenAvatarItem {
  id: string;
  name: string;
  gender: string | null;
  preview: string;
  previewVideo: string;
  premium: boolean;
}

export async function listHeyGenAvatars(): Promise<{
  ok: boolean;
  configured: boolean;
  avatars: HeyGenAvatarItem[];
  error?: string;
}> {
  const res = await fetch("/api/heygen/avatars");
  return res.json();
}

export async function renderHeyGen(input: {
  scenes?: VideoScene[];
  script?: string;
  aspect: string;
  avatarId?: string;
  talkingPhotoId?: string;
  voiceId?: string;
  gender?: string | null;
}): Promise<{ ok: boolean; videoId?: string; configured?: boolean; error?: string }> {
  const res = await fetch("/api/heygen/render", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  return res.json();
}

export async function pollHeyGen(
  videoId: string,
  onTick?: (status: string) => void,
  timeoutMs = 8 * 60_000
): Promise<{ ok: boolean; videoUrl?: string; error?: string }> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const res = await fetch(`/api/heygen/status?video_id=${encodeURIComponent(videoId)}`);
    const data = await res.json();
    if (!data.ok) return { ok: false, error: data.error || "Status check failed" };
    onTick?.(data.status);
    if (data.status === "completed" && data.videoUrl) {
      return { ok: true, videoUrl: data.videoUrl };
    }
    if (data.status === "failed") {
      return { ok: false, error: data.error || "HeyGen render failed" };
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
  return { ok: false, error: "Timed out waiting for the render" };
}

export async function generatePortraitClient(input: {
  name: string;
  vibe: string;
  soulId?: string;
}): Promise<{ ok: boolean; url: string | null; engine: "higgsfield" | "demo"; error?: string }> {
  const res = await fetch("/api/character/portrait", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  return res.json();
}

export async function scoreVideoClient(input: {
  scenes?: VideoScene[];
  videoUrl?: string;
}): Promise<{ ok: boolean; score?: VideoScore; error?: string }> {
  const res = await fetch("/api/video/score", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  return res.json();
}

export async function transcribeClient(input: {
  durationSec: number;
  fileUrl?: string;
}): Promise<{ ok: boolean; engine: "whisper" | "demo"; segments: TranscriptSegment[] }> {
  const res = await fetch("/api/transcribe", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  return res.json();
}

export async function reframeClient(videoUrl: string, aspect: string): Promise<{
  ok: boolean;
  url: string | null;
  engine: string;
  error?: string;
}> {
  const res = await fetch("/api/video/reframe", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ videoUrl, aspect }),
  });
  return res.json();
}
