"use client";

import type { VideoScene, VideoScore, TranscriptSegment } from "./types";

export async function createCharacter(name: string, images: string[]): Promise<{
  ok: boolean;
  soulId?: string;
  engine: "higgsfield" | "demo";
  error?: string;
}> {
  const res = await fetch("/api/character/create", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, images }),
  });
  return res.json();
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
