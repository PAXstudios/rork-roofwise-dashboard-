"use client";

import type { VideoKind, VideoScene } from "./types";

export interface GenerateResult {
  ok: boolean;
  title: string;
  scenes: VideoScene[];
  engine: "provider" | "demo";
  canRender: boolean;
  error?: string;
}

export async function generateStoryboard(input: {
  kind: VideoKind;
  prompt: string;
  aspect: string;
  voiceStyle: string;
  persona?: string;
  hookStyle?: string;
  niche?: string;
  audience?: string;
  voiceSamples?: string[];
}): Promise<GenerateResult> {
  const res = await fetch("/api/video/generate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  const data = await res.json();
  if (!res.ok || !data.ok) {
    return {
      ok: false,
      title: "",
      scenes: [],
      engine: "demo",
      canRender: false,
      error: data.error || `Request failed (${res.status})`,
    };
  }
  return data as GenerateResult;
}

export interface RenderResult {
  ok: boolean;
  clips: { sceneId: string; url: string }[];
  engine: string;
  provider?: string;
  error?: string;
}

export async function renderClips(
  kind: VideoKind,
  scenes: VideoScene[],
  aspect: string,
  opts: { maxScenes?: number; soulId?: string; music?: boolean } = {}
): Promise<RenderResult> {
  const res = await fetch("/api/video/render", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ kind, scenes, aspect, ...opts }),
  });
  const data = await res.json();
  return {
    ok: Boolean(data.ok),
    clips: data.clips || [],
    engine: data.engine || "none",
    provider: data.provider,
    error: data.error,
  };
}
