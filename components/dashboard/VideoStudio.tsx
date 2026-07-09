"use client";

import { useMemo, useState } from "react";
import { useStore } from "@/lib/store";
import { useHydrated, timeAgo } from "@/lib/hooks";
import { generateStoryboard, renderClips } from "@/lib/videoClient";
import { scoreVideoClient, reframeClient, renderHeyGen, pollHeyGen } from "@/lib/studioClient";
import { VideoPlayer } from "./VideoPlayer";
import { CharacterPicker } from "./CharacterPicker";
import { ScoreCard } from "./ScoreCard";
import { PLATFORM_META, PlatformBadge } from "@/components/platform";
import Link from "next/link";
import type { VideoKind, VideoAspect, VideoScene, VideoProject, Platform, VideoScore } from "@/lib/types";
import {
  IconSpark,
  IconTrash,
  IconPlus,
  IconCheck,
  IconLayers,
  IconClock,
  IconTarget,
} from "@/components/Icons";

const ASPECTS: { key: VideoAspect; label: string }[] = [
  { key: "9:16", label: "9:16 · Reels/TikTok" },
  { key: "1:1", label: "1:1 · Feed" },
  { key: "16:9", label: "16:9 · YouTube" },
];

const VOICE_STYLES = ["energetic", "calm", "authoritative", "friendly", "hype", "storyteller"];
const HOOK_STYLES = ["Contrarian", "Question", "Bold claim", "Story", "Listicle", "Pattern interrupt"];
const PERSONAS = [
  "Maya — energetic creator",
  "Jordan — calm expert",
  "Alex — hype hypebeast",
  "Sam — friendly girl-next-door",
  "Chris — authoritative founder",
];

export function VideoStudio({ kind }: { kind: VideoKind }) {
  const hydrated = useHydrated();
  const voice = useStore((s) => s.voice);
  const videos = useStore((s) => s.videos);
  const characters = useStore((s) => s.characters);
  const addVideo = useStore((s) => s.addVideo);
  const updateVideo = useStore((s) => s.updateVideo);
  const deleteVideo = useStore((s) => s.deleteVideo);

  const isUgc = kind === "ugc";
  const [prompt, setPrompt] = useState("");
  const [aspect, setAspect] = useState<VideoAspect>("9:16");
  const [platform, setPlatform] = useState<Platform>(isUgc ? "instagram" : "youtube");
  const [voiceStyle, setVoiceStyle] = useState(isUgc ? "energetic" : "storyteller");
  const [persona, setPersona] = useState(PERSONAS[0]);
  const [hookStyle, setHookStyle] = useState(HOOK_STYLES[0]);
  const [characterId, setCharacterId] = useState<string>("");
  const [music, setMusic] = useState(true);

  const [scenes, setScenes] = useState<VideoScene[]>([]);
  const [title, setTitle] = useState("");
  const [engine, setEngine] = useState<"provider" | "demo" | null>(null);
  const [generating, setGenerating] = useState(false);
  const [rendering, setRendering] = useState(false);
  const [clips, setClips] = useState<{ sceneId: string; url: string }[]>([]);
  const [renderUrl, setRenderUrl] = useState<string | null>(null);
  const [renderPhase, setRenderPhase] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [savedId, setSavedId] = useState<string | null>(null);
  const [score, setScore] = useState<VideoScore | null>(null);
  const [scoring, setScoring] = useState(false);

  const character = characters.find((c) => c.id === characterId) || null;
  const effectivePersona = character ? `${character.name} — ${character.vibe}` : persona;

  const myVideos = useMemo(() => videos.filter((v) => v.kind === kind), [videos, kind]);

  async function onGenerate() {
    if (!prompt.trim() || generating) return;
    setGenerating(true);
    setNotice(null);
    setClips([]);
    setSavedId(null);
    setScore(null);
    const res = await generateStoryboard({
      kind,
      prompt: prompt.trim(),
      aspect,
      voiceStyle,
      persona: isUgc ? effectivePersona : undefined,
      hookStyle: isUgc ? hookStyle : undefined,
      niche: voice.niche,
      audience: voice.audience,
      voiceSamples: voice.trained ? voice.samples : undefined,
    });
    setGenerating(false);
    if (!res.ok) {
      setNotice(res.error || "Generation failed");
      return;
    }
    setScenes(res.scenes);
    setTitle(res.title);
    setEngine(res.engine);
  }

  const heygenBacked = Boolean(character?.heygenAvatarId || character?.heygenTalkingPhotoId);

  async function onRender() {
    if (!scenes.length || rendering) return;
    setRendering(true);
    setNotice(null);
    setRenderUrl(null);

    // UGC + a HeyGen-backed character → a real talking avatar video.
    if (isUgc && heygenBacked) {
      setRenderPhase("Sending your script to HeyGen…");
      const submit = await renderHeyGen({
        scenes,
        aspect,
        avatarId: character?.heygenAvatarId,
        talkingPhotoId: character?.heygenTalkingPhotoId,
        voiceId: character?.voiceId,
        gender: character?.gender,
      });
      if (!submit.ok || !submit.videoId) {
        setRendering(false);
        setRenderPhase(null);
        setNotice(
          submit.error
            ? `HeyGen: ${submit.error}`
            : "HeyGen isn't configured — add HEYGEN_API_KEY to .env.local and restart."
        );
        return;
      }
      setRenderPhase("HeyGen is filming your avatar… usually 1–3 minutes.");
      const done = await pollHeyGen(submit.videoId, (s) =>
        setRenderPhase(`HeyGen is filming your avatar… (${s})`)
      );
      setRendering(false);
      setRenderPhase(null);
      if (done.ok && done.videoUrl) {
        setRenderUrl(done.videoUrl);
        setNotice(`Your avatar video is ready — rendered with HeyGen.`);
      } else {
        setNotice(`HeyGen: ${done.error || "render failed"}. Preview is playing below.`);
      }
      return;
    }

    // Otherwise → Higgsfield per-scene clips.
    const res = await renderClips(kind, scenes, aspect, {
      soulId: character?.soulId,
      music,
    });
    setRendering(false);
    if (res.clips.length) {
      setClips(res.clips);
      setNotice(`Rendered ${res.clips.length} clip${res.clips.length > 1 ? "s" : ""} with Higgsfield.`);
    } else {
      setNotice(
        res.error
          ? `Higgsfield render unavailable: ${res.error}. Preview is playing below.`
          : isUgc
            ? "Tip: pick a HeyGen character above (Characters → HeyGen library) for real avatar video — or add HF_CREDENTIALS for Higgsfield rendering. Playing the in-browser preview."
            : "Real AI rendering is off — playing the in-browser preview. To turn it on: get an API key at higgsfield.ai (Account → API Keys), create a .env.local file in the project root with HF_CREDENTIALS=KEY_ID:KEY_SECRET, then restart the dev server."
      );
    }
  }

  async function onScore() {
    if (!scenes.length || scoring) return;
    setScoring(true);
    const res = await scoreVideoClient({ scenes, videoUrl: clips[0]?.url });
    setScoring(false);
    if (res.ok && res.score) setScore(res.score);
  }

  async function onReframe(target: VideoAspect) {
    setAspect(target);
    if (!clips.length) {
      setNotice(`Preview reframed to ${target}. Render to produce a real ${target} cut.`);
      return;
    }
    setNotice(`Repurposing to ${target}…`);
    const res = await reframeClient(clips[0].url, target);
    setNotice(
      res.url
        ? `Repurposed to ${target} with Higgsfield.`
        : `Reframe queued for ${target}. Add Higgsfield credentials to produce the ${target} MP4.`
    );
  }

  function saveProject() {
    if (!scenes.length) return;
    const project: VideoProject = {
      id: `vid-${Math.random().toString(36).slice(2, 10)}`,
      kind,
      title: title || prompt.slice(0, 48),
      prompt,
      platform,
      aspect,
      persona: isUgc ? effectivePersona : undefined,
      characterId: isUgc ? characterId || undefined : undefined,
      hookStyle: isUgc ? hookStyle : undefined,
      voiceStyle,
      music,
      scenes,
      status: renderUrl || clips.length ? "ready" : "draft",
      renderUrl: renderUrl || undefined,
      sceneClips: clips.length ? clips : undefined,
      engine: renderUrl || clips.length ? "provider" : "demo",
      provider: renderUrl ? "heygen" : clips.length ? "higgsfield" : undefined,
      score: score || undefined,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    addVideo(project);
    setSavedId(project.id);
    setNotice("Saved to your library.");
  }

  function updateScene(id: string, patch: Partial<VideoScene>) {
    setScenes((prev) => prev.map((s) => (s.id === id ? { ...s, ...patch } : s)));
  }
  function removeScene(id: string) {
    setScenes((prev) => prev.filter((s) => s.id !== id));
    setClips((prev) => prev.filter((c) => c.sceneId !== id));
  }

  function loadProject(v: VideoProject) {
    setPrompt(v.prompt);
    setAspect(v.aspect);
    setPlatform(v.platform);
    setVoiceStyle(v.voiceStyle);
    if (v.persona) setPersona(v.persona);
    if (v.hookStyle) setHookStyle(v.hookStyle);
    if (v.characterId) setCharacterId(v.characterId);
    setMusic(v.music ?? true);
    setScenes(v.scenes);
    setTitle(v.title);
    setClips(v.sceneClips || []);
    setRenderUrl(v.renderUrl || null);
    setEngine(v.engine === "provider" ? "provider" : "demo");
    setScore(v.score || null);
    setSavedId(v.id);
    setNotice(null);
  }

  const examples = isUgc
    ? [
        "A UGC hook about why my product saves creators 10 hours a week",
        "Unboxing-style video for a new productivity app",
        "Talking-head: 3 myths about growing on Instagram",
      ]
    : [
        "A cinematic 30s brand video about building in public",
        "Fast-cut motivational short on consistency",
        "Explainer: how our AI writes in your voice",
      ];

  return (
    <div className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
      {/* header */}
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold tracking-tight">
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-brand-gradient text-white">
              <IconSpark width={18} height={18} />
            </span>
            {isUgc ? "UGC Video Generator" : "Video Studio"}
          </h1>
          <p className="mt-1 text-sm text-ink-soft">
            {isUgc
              ? "Turn a prompt into a scripted, creator-style UGC video — in your voice."
              : "Prompt → storyboard → real AI video. Rendered with Higgsfield."}
          </p>
        </div>
        <span className="chip">
          <IconSpark width={13} height={13} className="text-brand-300" />
          Powered by Higgsfield
        </span>
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        {/* left: builder */}
        <div className="space-y-5">
          {/* prompt + options */}
          <div className="card p-5">
            <label className="label">What's the video about?</label>
            <textarea
              className="input min-h-[92px] resize-y"
              placeholder={isUgc ? "e.g. Why most creators quit right before it works…" : "e.g. A cinematic short about our launch…"}
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
            />
            <div className="mt-2 flex flex-wrap gap-1.5">
              {examples.map((ex) => (
                <button
                  key={ex}
                  onClick={() => setPrompt(ex)}
                  className="rounded-full border border-line bg-white/[0.02] px-3 py-1 text-xs text-ink-soft hover:border-brand-500/40 hover:text-ink"
                >
                  {ex}
                </button>
              ))}
            </div>

            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <div>
                <label className="label">Aspect</label>
                <select className="input" value={aspect} onChange={(e) => setAspect(e.target.value as VideoAspect)}>
                  {ASPECTS.map((a) => (
                    <option key={a.key} value={a.key}>{a.label}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="label">Voice / energy</label>
                <select className="input" value={voiceStyle} onChange={(e) => setVoiceStyle(e.target.value)}>
                  {VOICE_STYLES.map((v) => (
                    <option key={v} value={v} className="capitalize">{v}</option>
                  ))}
                </select>
              </div>
              {isUgc && (
                <div className="sm:col-span-2">
                  <div className="mb-1.5 flex items-center justify-between">
                    <label className="label !mb-0">Creator character</label>
                    <Link href="/dashboard/characters" className="text-xs font-semibold text-brand-300 hover:text-brand-200">
                      Manage / create →
                    </Link>
                  </div>
                  <CharacterPicker value={characterId} onChange={setCharacterId} />
                </div>
              )}
              {isUgc && (
                <div>
                  <label className="label">Hook style</label>
                  <select className="input" value={hookStyle} onChange={(e) => setHookStyle(e.target.value)}>
                    {HOOK_STYLES.map((h) => (
                      <option key={h} value={h}>{h}</option>
                    ))}
                  </select>
                </div>
              )}
              <div>
                <label className="label">Publish to</label>
                <select className="input" value={platform} onChange={(e) => setPlatform(e.target.value as Platform)}>
                  {(Object.keys(PLATFORM_META) as Platform[]).map((p) => (
                    <option key={p} value={p}>{PLATFORM_META[p].label}</option>
                  ))}
                </select>
              </div>
              <div className="flex items-end">
                <button
                  type="button"
                  onClick={() => setMusic((m) => !m)}
                  className={`flex w-full items-center justify-between rounded-xl border px-4 py-3 text-sm transition ${
                    music ? "border-brand-500/50 bg-brand-500/10 text-ink" : "border-line text-ink-soft hover:bg-white/[0.04]"
                  }`}
                >
                  <span>🎵 Background music</span>
                  <span className={`grid h-5 w-9 items-center rounded-full px-0.5 ${music ? "bg-brand-500" : "bg-white/10"}`}>
                    <span className={`h-4 w-4 rounded-full bg-white transition ${music ? "translate-x-4" : ""}`} />
                  </span>
                </button>
              </div>
            </div>

            <button onClick={onGenerate} disabled={generating || !prompt.trim()} className="btn-primary mt-4 w-full">
              {generating ? (
                <><span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" /> Writing your storyboard…</>
              ) : (
                <><IconSpark width={16} height={16} /> {scenes.length ? "Regenerate storyboard" : "Generate storyboard"}</>
              )}
            </button>
            {!voice.trained && (
              <p className="mt-2 text-center text-[11px] text-ink-faint">
                Tip: train your voice in Settings so scripts sound like you.
              </p>
            )}
          </div>

          {/* storyboard */}
          {scenes.length > 0 && (
            <div className="card p-5">
              <div className="mb-3 flex items-center justify-between">
                <h2 className="flex items-center gap-2 font-semibold">
                  <IconLayers width={16} height={16} className="text-brand-300" /> Storyboard
                  <span className="chip ml-1">
                    <span className={`h-1.5 w-1.5 rounded-full ${engine === "provider" ? "bg-accent-lime" : "bg-accent-warm"}`} />
                    {engine === "provider" ? "AI-written" : "demo script"}
                  </span>
                </h2>
                <span className="text-xs text-ink-faint">{scenes.length} scenes</span>
              </div>

              <div className="space-y-3">
                {scenes.map((s, i) => (
                  <div key={s.id} className="rounded-xl border border-line bg-white/[0.02] p-3">
                    <div className="mb-2 flex items-center justify-between">
                      <span className="flex items-center gap-2 text-xs font-semibold text-ink-soft">
                        <span className="grid h-5 w-5 place-items-center rounded-full bg-brand-500/20 text-[10px] text-brand-200">{i + 1}</span>
                        Scene {i + 1}
                        <span className="flex items-center gap-1 text-ink-faint"><IconClock width={11} height={11} />{s.durationSec}s</span>
                      </span>
                      <button onClick={() => removeScene(s.id)} className="text-ink-faint hover:text-red-400">
                        <IconTrash width={14} height={14} />
                      </button>
                    </div>
                    <input
                      className="input mb-2 !py-2 text-sm font-semibold"
                      value={s.caption}
                      onChange={(e) => updateScene(s.id, { caption: e.target.value })}
                      placeholder="On-screen caption"
                    />
                    <textarea
                      className="input mb-2 min-h-[52px] resize-y !py-2 text-sm"
                      value={s.voiceover}
                      onChange={(e) => updateScene(s.id, { voiceover: e.target.value })}
                      placeholder="Voiceover / narration"
                    />
                    <input
                      className="input !py-2 text-xs text-ink-soft"
                      value={s.visual}
                      onChange={(e) => updateScene(s.id, { visual: e.target.value })}
                      placeholder="Visual / b-roll description"
                    />
                  </div>
                ))}
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                <button onClick={onRender} disabled={rendering} className="btn-primary">
                  {rendering ? (
                    <><span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" /> Rendering…</>
                  ) : (
                    <>
                      <IconSpark width={16} height={16} />
                      {isUgc && heygenBacked
                        ? `Render with HeyGen (${character?.name})`
                        : "Render real video"}
                    </>
                  )}
                </button>
                <button onClick={onScore} disabled={scoring} className="btn-ghost">
                  {scoring ? (
                    <><span className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" /> Scoring…</>
                  ) : (
                    <><IconTarget width={16} height={16} /> Score virality</>
                  )}
                </button>
                <button onClick={saveProject} className="btn-ghost">
                  {savedId ? <><IconCheck width={16} height={16} className="text-accent-lime" /> Saved</> : <><IconPlus width={16} height={16} /> Save to library</>}
                </button>
              </div>
              {notice && (
                <p className="mt-3 rounded-lg border border-line bg-white/[0.02] px-3 py-2 text-xs text-ink-soft">{notice}</p>
              )}
              {rendering && (
                <p className="mt-2 flex items-center gap-2 text-xs text-ink-faint">
                  <span className="h-1.5 w-1.5 animate-pulse-dot rounded-full bg-brand-400" />
                  {renderPhase ||
                    "Higgsfield is generating each scene (image → motion). This can take a few minutes per clip."}
                </p>
              )}
            </div>
          )}
        </div>

        {/* right: preview + library */}
        <div className="space-y-5">
          <div className="card p-4">
            <div className="mb-3 text-xs font-semibold uppercase tracking-wide text-ink-faint">
              {clips.length ? "Rendered video" : "Preview"}
            </div>
            {scenes.length ? (
              <VideoPlayer
                scenes={scenes}
                kind={kind}
                aspect={aspect}
                persona={isUgc ? (character?.name || effectivePersona) : undefined}
                clips={!renderUrl && clips.length ? clips : undefined}
                renderUrl={renderUrl || undefined}
              />
            ) : (
              <div className={`mx-auto grid w-full max-w-[300px] place-items-center rounded-2xl border border-dashed border-line-strong text-center ${aspect === "9:16" ? "aspect-[9/16]" : aspect === "1:1" ? "aspect-square" : "aspect-video"}`}>
                <div className="px-6 text-sm text-ink-faint">
                  <IconSpark width={22} height={22} className="mx-auto mb-2 text-ink-faint" />
                  Your video preview appears here after you generate a storyboard.
                </div>
              </div>
            )}
            {scenes.length > 0 && (
              <div className="mt-4 border-t border-line pt-3">
                <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-ink-faint">
                  Repurpose (reframe)
                </div>
                <div className="flex gap-1.5">
                  {(["9:16", "1:1", "16:9"] as VideoAspect[]).map((a) => (
                    <button
                      key={a}
                      onClick={() => onReframe(a)}
                      className={`flex-1 rounded-lg border px-2 py-1.5 text-xs transition ${
                        aspect === a
                          ? "border-brand-500/50 bg-brand-500/10 text-ink"
                          : "border-line text-ink-soft hover:bg-white/[0.04]"
                      }`}
                    >
                      {a}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>

          {score && <ScoreCard score={score} />}

          {hydrated && myVideos.length > 0 && (
            <div className="card p-4">
              <div className="mb-3 text-xs font-semibold uppercase tracking-wide text-ink-faint">
                Your {isUgc ? "UGC" : "videos"}
              </div>
              <div className="space-y-2">
                {myVideos.map((v) => (
                  <div key={v.id} className="group flex items-center gap-2 rounded-lg px-2 py-2 hover:bg-white/[0.04]">
                    <PlatformBadge platform={v.platform} size={14} />
                    <button onClick={() => loadProject(v)} className="min-w-0 flex-1 text-left">
                      <span className="block truncate text-sm">{v.title}</span>
                      <span className="block text-[11px] text-ink-faint">
                        {v.status === "ready" ? "Rendered · " : ""}{timeAgo(v.updatedAt)}
                      </span>
                    </button>
                    <button onClick={() => deleteVideo(v.id)} className="opacity-0 transition group-hover:opacity-100">
                      <IconTrash width={14} height={14} className="text-ink-faint hover:text-red-400" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
