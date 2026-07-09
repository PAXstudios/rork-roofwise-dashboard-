import { getClient, getModel } from "./ai";
import type { VideoKind, VideoScene } from "./types";
import { VIDEO_BG_KEYS } from "./seed";

export interface StoryboardInput {
  kind: VideoKind;
  prompt: string;
  aspect: string;
  voiceStyle: string;
  persona?: string;
  hookStyle?: string;
  niche?: string;
  audience?: string;
  voiceSamples?: string[];
}

export interface Storyboard {
  title: string;
  scenes: VideoScene[];
  engine: "provider" | "demo";
}

function sceneId(i: number) {
  return `sc-${i}-${Math.random().toString(36).slice(2, 7)}`;
}

function pickBg(i: number) {
  return VIDEO_BG_KEYS[i % VIDEO_BG_KEYS.length];
}

// ── AI storyboard via Claude (JSON) ────────────────────────────

const SYSTEM = `You are a world-class short-form video director and scriptwriter for creators.
You turn a prompt into a tight, scroll-stopping storyboard for vertical social video (Reels / TikTok / Shorts).
Rules:
- 4 to 6 scenes. Total runtime 20-40 seconds.
- Scene 1 is a hard hook in the first 1-2 seconds.
- Each scene: a spoken VOICEOVER line (natural, punchy, conversational), a very short on-screen CAPTION (2-5 words), and a VISUAL description (what's on screen / b-roll / motion).
- End with a clear call to action.
- Write in the creator's voice when samples are provided.
You MUST respond with ONLY valid minified JSON, no markdown, matching:
{"title": string, "scenes": [{"durationSec": number, "voiceover": string, "caption": string, "visual": string}]}`;

function userPrompt(input: StoryboardInput): string {
  const lines = [
    `Kind: ${input.kind === "ugc" ? "UGC talking-head style (a person speaking to camera)" : "cinematic / b-roll short video"}`,
    `Aspect: ${input.aspect}`,
    `Voice/energy: ${input.voiceStyle}`,
    input.persona ? `Creator persona: ${input.persona}` : "",
    input.hookStyle ? `Hook style: ${input.hookStyle}` : "",
    input.niche ? `Niche: ${input.niche}` : "",
    input.audience ? `Audience: ${input.audience}` : "",
    input.voiceSamples?.length
      ? `Creator's writing samples (mirror this voice):\n${input.voiceSamples.slice(0, 3).join("\n---\n")}`
      : "",
    ``,
    `Prompt: ${input.prompt}`,
  ].filter(Boolean);
  return lines.join("\n");
}

export async function generateStoryboard(input: StoryboardInput): Promise<Storyboard> {
  const client = getClient();
  if (!client) return demoStoryboard(input);

  try {
    const msg = await client.messages.create({
      model: getModel(),
      max_tokens: 1200,
      system: SYSTEM,
      messages: [{ role: "user", content: userPrompt(input) }],
    });
    const text = msg.content
      .map((b) => (b.type === "text" ? b.text : ""))
      .join("")
      .trim();
    const json = extractJson(text);
    const parsed = JSON.parse(json) as {
      title: string;
      scenes: { durationSec: number; voiceover: string; caption: string; visual: string }[];
    };
    const scenes: VideoScene[] = parsed.scenes.slice(0, 8).map((s, i) => ({
      id: sceneId(i),
      durationSec: Math.min(8, Math.max(2, Math.round(s.durationSec || 4))),
      voiceover: s.voiceover || "",
      caption: s.caption || "",
      visual: s.visual || "",
      bg: pickBg(i),
    }));
    if (!scenes.length) return demoStoryboard(input);
    return { title: parsed.title || input.prompt.slice(0, 48), scenes, engine: "provider" };
  } catch {
    return demoStoryboard(input);
  }
}

function extractJson(text: string): string {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) return fence[1].trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) return text.slice(start, end + 1);
  return text;
}

// ── Demo storyboard (no API key) ───────────────────────────────

function demoStoryboard(input: StoryboardInput): Storyboard {
  const topic = input.prompt.replace(/^(make|create|write)\s+(a|an)?\s*/i, "").trim() || "your topic";
  const short = topic.length > 42 ? topic.slice(0, 42) + "…" : topic;
  const scenes: Omit<VideoScene, "id" | "bg">[] = [
    {
      durationSec: 3,
      voiceover: `Here's the thing nobody tells you about ${short}.`,
      caption: "Watch this 👀",
      visual: "Creator to camera, quick punch-in on the hook line.",
    },
    {
      durationSec: 4,
      voiceover: `Most people get this completely backwards — and it's costing them.`,
      caption: "The big mistake",
      visual: "Bold text overlay, subtle zoom, b-roll of scrolling.",
    },
    {
      durationSec: 5,
      voiceover: `Instead, do this one thing and everything changes.`,
      caption: "Do this instead",
      visual: "Split screen before/after, arrow motion graphic.",
    },
    {
      durationSec: 4,
      voiceover: `It works because it puts your audience first, not the algorithm.`,
      caption: "Why it works",
      visual: "Creator gesturing, key phrase highlighted.",
    },
    {
      durationSec: 3,
      voiceover: `Try it on your next post — then follow for more like this.`,
      caption: "Follow for more →",
      visual: "Smiling creator, subscribe animation, end card.",
    },
  ];
  return {
    title: short.replace(/\b\w/g, (c) => c.toUpperCase()),
    scenes: scenes.map((s, i) => ({ ...s, id: sceneId(i), bg: pickBg(i) })),
    engine: "demo",
  };
}

// ── Render provider: Higgsfield ────────────────────────────────
// Each storyboard scene is rendered to a real MP4 clip via Higgsfield:
//   text2image/soul  → a still frame for the scene
//   image2video/dop  → animate that still into a short clip
// Configured with HF_CREDENTIALS="KEY_ID:KEY_SECRET" (or HF_API_KEY +
// HF_API_SECRET). Without credentials the app plays the in-browser preview.

export function hfCredentials(): string | null {
  if (process.env.HF_CREDENTIALS) return process.env.HF_CREDENTIALS;
  if (process.env.HF_API_KEY && process.env.HF_API_SECRET) {
    return `${process.env.HF_API_KEY}:${process.env.HF_API_SECRET}`;
  }
  return null;
}

export function hasRenderProvider(_kind?: VideoKind): boolean {
  return Boolean(hfCredentials());
}

function dimsFor(aspect: string): string {
  if (aspect === "1:1") return "1024x1024";
  if (aspect === "16:9") return "1280x720";
  return "720x1280"; // 9:16 default
}

export interface RenderedClip {
  sceneId: string;
  url: string;
}

export interface RenderResult {
  clips: RenderedClip[];
  engine: "higgsfield" | "none";
  error?: string;
}

export async function renderVideo(
  kind: VideoKind,
  scenes: VideoScene[],
  opts: { aspect?: string; maxScenes?: number; soulId?: string; music?: boolean } = {}
): Promise<RenderResult> {
  const creds = hfCredentials();
  if (!creds) return { clips: [], engine: "none" };

  // Import lazily so the SDK is only loaded server-side when needed.
  const { createHiggsfieldClient } = await import("@higgsfield/client/v2");
  const client = createHiggsfieldClient({ credentials: creds });

  const dims = dimsFor(opts.aspect || "9:16");
  const max = Math.max(1, Math.min(opts.maxScenes ?? scenes.length, scenes.length));
  const clips: RenderedClip[] = [];
  let error: string | undefined;

  for (const scene of scenes.slice(0, max)) {
    try {
      // 1) still frame — carry the creator's trained face (Soul) when provided
      const imgPrompt =
        kind === "ugc"
          ? `${scene.visual}. Vertical UGC selfie-style shot of a creator talking to camera. ${scene.caption}`
          : `${scene.visual}. Cinematic, high quality. ${scene.caption}`;
      const soulInput = opts.soulId
        ? { custom_reference_id: opts.soulId, custom_reference_strength: 0.8 }
        : {};
      const img = await client.subscribe("/v1/text2image/soul", {
        input: { prompt: imgPrompt, width_and_height: dims, quality: "1080p", batch_size: 1, ...soulInput },
        withPolling: true,
      });
      const imageUrl = img.images?.[0]?.url;
      if (!imageUrl) {
        error = "Image generation returned no result";
        continue;
      }

      // 2) animate into a clip
      const vid = await client.subscribe("/v1/image2video/dop", {
        input: {
          model: "dop-turbo",
          prompt: scene.visual || scene.voiceover,
          input_images: [{ type: "image_url", image_url: imageUrl }],
          enhance_prompt: true,
        },
        withPolling: true,
      });
      const url = vid.video?.url;
      if (url) clips.push({ sceneId: scene.id, url });
      else error = "Video generation returned no result";
    } catch (err: any) {
      error = err?.message || "Render failed";
    }
  }

  return { clips, engine: "higgsfield", error: clips.length ? undefined : error };
}

// ── CLI render path (honors a locally-authenticated `higgsfield` CLI) ──
// Enabled with HIGGSFIELD_USE_CLI=1. Uses Seedance 2.0 text-to-video — the
// skill's default video model — one clip per scene. Requires the CLI to be on
// PATH and authenticated (`higgsfield auth login`).

export function cliRenderEnabled(): boolean {
  return process.env.HIGGSFIELD_USE_CLI === "1";
}

export async function renderViaHiggsfieldCli(
  scenes: VideoScene[],
  opts: { aspect?: string; maxScenes?: number; model?: string } = {}
): Promise<RenderResult> {
  const { execFile } = await import("node:child_process");
  const { promisify } = await import("node:util");
  const run = promisify(execFile);

  const model = opts.model || "seedance_2_0";
  const ar = opts.aspect === "1:1" ? "1:1" : opts.aspect === "16:9" ? "16:9" : "9:16";
  const max = Math.max(1, Math.min(opts.maxScenes ?? scenes.length, scenes.length));
  const clips: RenderedClip[] = [];
  let error: string | undefined;

  for (const scene of scenes.slice(0, max)) {
    const prompt = `${scene.visual}. ${scene.voiceover}`.slice(0, 480);
    try {
      const { stdout } = await run(
        "higgsfield",
        [
          "generate",
          "create",
          model,
          "--prompt",
          prompt,
          "--duration",
          String(Math.min(15, Math.max(4, Math.round(scene.durationSec)))),
          "--aspect_ratio",
          ar,
          "--wait",
          "--wait-timeout",
          "20m",
          "--json",
        ],
        { maxBuffer: 1024 * 1024 * 8 }
      );
      const url = extractUrlFromCli(stdout);
      if (url) clips.push({ sceneId: scene.id, url });
      else error = "CLI returned no result URL";
    } catch (err: any) {
      error = err?.stderr || err?.message || "CLI render failed";
    }
  }
  return { clips, engine: "higgsfield", error: clips.length ? undefined : error };
}

// Repurpose an existing video to a different aspect ratio via Higgsfield's
// `reframe` workflow. Demo mode acknowledges the target ratio (the player
// already renders any aspect).
export async function reframeVideo(
  videoUrl: string,
  targetAspect: string
): Promise<{ ok: boolean; url: string | null; engine: "higgsfield" | "demo"; error?: string }> {
  if (!cliRenderEnabled()) {
    return { ok: true, url: null, engine: "demo" };
  }
  try {
    const { execFile } = await import("node:child_process");
    const { promisify } = await import("node:util");
    const run = promisify(execFile);
    const { stdout } = await run(
      "higgsfield",
      ["workflow", "run", "reframe", "--video", videoUrl, "--aspect_ratio", targetAspect, "--wait", "--json"],
      { maxBuffer: 1024 * 1024 * 8 }
    );
    const url = extractUrlFromCli(stdout);
    return { ok: Boolean(url), url, engine: "higgsfield", error: url ? undefined : "No result URL" };
  } catch (err: any) {
    return { ok: false, url: null, engine: "higgsfield", error: err?.stderr || err?.message };
  }
}

function extractUrlFromCli(stdout: string): string | null {
  // Try JSON first, then fall back to a raw URL match.
  try {
    const data = JSON.parse(stdout);
    const scan = (o: any): string | null => {
      if (!o) return null;
      if (typeof o === "string" && /^https?:\/\/.*\.(mp4|mov|webm)/i.test(o)) return o;
      if (typeof o === "object") {
        for (const k of Object.keys(o)) {
          const r = scan(o[k]);
          if (r) return r;
        }
      }
      return null;
    };
    const found = scan(data);
    if (found) return found;
  } catch {
    /* not json */
  }
  const m = stdout.match(/https?:\/\/\S+\.(?:mp4|mov|webm)\S*/i);
  return m ? m[0] : null;
}
