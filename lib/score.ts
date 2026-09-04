import type { VideoScore, VideoScene } from "./types";
import { cliRenderEnabled } from "./video";

// Virality Predictor. With the authenticated CLI, routes to Higgsfield's
// `brain_activity` (video-in → score/report). Otherwise computes a transparent
// heuristic from the storyboard so the feature is always usable.

export async function scoreVideo(input: {
  scenes?: VideoScene[];
  videoUrl?: string;
}): Promise<VideoScore> {
  if (cliRenderEnabled() && input.videoUrl) {
    try {
      const { execFile } = await import("node:child_process");
      const { promisify } = await import("node:util");
      const run = promisify(execFile);
      const { stdout } = await run(
        "higgsfield",
        ["generate", "create", "brain_activity", "--video", input.videoUrl, "--wait", "--json"],
        { maxBuffer: 1024 * 1024 * 8 }
      );
      const parsed = parseScore(stdout);
      if (parsed) return { ...parsed, engine: "higgsfield", scoredAt: Date.now() };
    } catch {
      /* fall through to heuristic */
    }
  }
  return { ...heuristic(input.scenes || []), engine: "demo", scoredAt: Date.now() };
}

function parseScore(stdout: string): Omit<VideoScore, "engine" | "scoredAt"> | null {
  try {
    const data = JSON.parse(stdout);
    const num = (v: any) => (typeof v === "number" ? Math.round(v > 1 ? v : v * 100) : undefined);
    const hook = num(data.hook ?? data.hook_score);
    const attention = num(data.attention ?? data.attention_score);
    const retention = num(data.retention ?? data.retention_score);
    const overall = num(data.overall ?? data.score ?? data.virality);
    if (overall == null && hook == null) return null;
    return {
      overall: overall ?? Math.round(((hook ?? 60) + (attention ?? 60) + (retention ?? 60)) / 3),
      hook: hook ?? 60,
      attention: attention ?? 60,
      retention: retention ?? 60,
      notes: Array.isArray(data.notes) ? data.notes : [],
    };
  } catch {
    return null;
  }
}

function heuristic(scenes: VideoScene[]): Omit<VideoScore, "engine" | "scoredAt"> {
  const first = scenes[0];
  const total = scenes.reduce((s, sc) => s + sc.durationSec, 0);
  const notes: string[] = [];

  // Hook: short, punchy first caption + a hook word
  let hook = 55;
  const hookText = (first?.caption + " " + first?.voiceover).toLowerCase();
  if (first && first.durationSec <= 3) hook += 12;
  else notes.push("Tighten the first scene — the hook should land in under 3 seconds.");
  if (/stop|nobody|secret|mistake|why|how|watch|3 |truth|don't/.test(hookText)) hook += 18;
  else notes.push("Open with a stronger hook word (e.g. 'Stop', 'Nobody tells you', a number).");
  if ((first?.caption?.split(" ").length || 9) <= 5) hook += 8;

  // Attention: pace — more, shorter scenes = higher
  let attention = 50 + Math.min(30, scenes.length * 5);
  const avg = total / Math.max(1, scenes.length);
  if (avg > 6) { attention -= 12; notes.push("Cut faster — average scene length is high for short-form."); }

  // Retention: has a payoff + CTA at the end
  let retention = 58;
  const last = scenes[scenes.length - 1];
  const lastText = (last?.caption + " " + last?.voiceover).toLowerCase();
  if (/follow|save|comment|share|link|more|subscribe|dm/.test(lastText)) retention += 20;
  else notes.push("End with a clear call to action to lift retention and shares.");
  if (total >= 15 && total <= 40) retention += 8;
  else notes.push("Aim for a 15–40s runtime for the best completion rate.");

  const clamp = (n: number) => Math.max(20, Math.min(97, Math.round(n)));
  hook = clamp(hook); attention = clamp(attention); retention = clamp(retention);
  const overall = Math.round(hook * 0.45 + attention * 0.25 + retention * 0.3);
  if (!notes.length) notes.push("Strong across the board — ship it and watch the first-hour retention.");
  return { overall, hook, attention, retention, notes: notes.slice(0, 4) };
}
