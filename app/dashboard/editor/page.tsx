"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useStore } from "@/lib/store";
import { useHydrated, timeAgo } from "@/lib/hooks";
import { transcribeClient } from "@/lib/studioClient";
import type {
  TranscriptSegment,
  TranscriptWord,
  CaptionStyle,
  VideoAspect,
  EditProject,
} from "@/lib/types";
import {
  IconClapper,
  IconVideo,
  IconMic,
  IconSpark,
  IconCheck,
  IconX,
  IconTrash,
  IconCopy,
  IconPlus,
  IconClock,
  IconLayers,
} from "@/components/Icons";

// ── helpers ──────────────────────────────────────────────────────
function mmss(sec: number): string {
  if (!isFinite(sec) || sec < 0) sec = 0;
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function uid(prefix = "edit") {
  return `${prefix}-${Math.random().toString(36).slice(2, 10)}`;
}

function aspectFromDims(w: number, h: number): VideoAspect {
  if (!w || !h) return "16:9";
  const r = w / h;
  if (r < 0.85) return "9:16";
  if (r < 1.2) return "1:1";
  return "16:9";
}

const CAPTION_STYLES: { key: CaptionStyle; label: string }[] = [
  { key: "clean", label: "Clean" },
  { key: "bold", label: "Bold" },
  { key: "highlight", label: "Highlight" },
];

const PROMPT_EXAMPLES = [
  "Cut the intro and remove all the ums",
  "Remove silence and keep the best take",
  "Add punchy captions",
  "Keep it under 20 seconds",
];

type Phase = "empty" | "transcribing" | "ready";

// ── page ─────────────────────────────────────────────────────────
export default function EditorPage() {
  const hydrated = useHydrated();
  const editProjects = useStore((s) => s.editProjects);
  const addEditProject = useStore((s) => s.addEditProject);
  const deleteEditProject = useStore((s) => s.deleteEditProject);

  // working project (kept in local state — object URLs don't persist)
  const [phase, setPhase] = useState<Phase>("empty");
  const [videoUrl, setVideoUrl] = useState("");
  const [videoDead, setVideoDead] = useState(false);
  const [durationSec, setDurationSec] = useState(0);
  const [aspect, setAspect] = useState<VideoAspect>("16:9");
  const [title, setTitle] = useState("");
  const [engine, setEngine] = useState<"whisper" | "demo">("demo");
  const [segments, setSegments] = useState<TranscriptSegment[]>([]);

  // edit flags
  const [captionStyle, setCaptionStyle] = useState<CaptionStyle>("bold");
  const [captionsOn, setCaptionsOn] = useState(true);
  const [removeSilence, setRemoveSilence] = useState(false);
  const [removeFillers, setRemoveFillers] = useState(false);
  const [bestTakeOnly, setBestTakeOnly] = useState(false);
  const [autoZoom, setAutoZoom] = useState(false);

  // prompt-to-edit
  const [prompt, setPrompt] = useState("");
  const [promptSummary, setPromptSummary] = useState("");
  const [promptChips, setPromptChips] = useState<string[]>([]);

  // player
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const probeRef = useRef<HTMLVideoElement | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);

  // save / copy
  const [savedId, setSavedId] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [dragging, setDragging] = useState(false);

  // revoke the object URL when it changes / unmounts
  useEffect(() => {
    return () => {
      if (videoUrl.startsWith("blob:")) URL.revokeObjectURL(videoUrl);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // whether a segment is CUT from the edit (manual removal OR a global toggle).
  // removeFillers is intentionally NOT here — fillers are struck visually and
  // dropped from captions, but playback stays at segment granularity.
  const isCut = useCallback(
    (seg: TranscriptSegment) =>
      !!seg.removed ||
      (removeSilence && !!seg.isSilence) ||
      (bestTakeOnly && !!seg.isAltTake),
    [removeSilence, bestTakeOnly]
  );

  const originalDuration = useMemo(() => {
    const last = segments.length ? segments[segments.length - 1].end : 0;
    return Math.max(durationSec, last);
  }, [segments, durationSec]);

  const editedDuration = useMemo(
    () =>
      segments.reduce((sum, s) => (isCut(s) ? sum : sum + (s.end - s.start)), 0),
    [segments, isCut]
  );

  const cutCount = useMemo(
    () => segments.filter((s) => isCut(s)).length,
    [segments, isCut]
  );

  const fillerCount = useMemo(
    () =>
      segments.reduce(
        (n, s) => n + s.words.filter((w) => w.filler).length,
        0
      ),
    [segments]
  );

  // ── upload ─────────────────────────────────────────────────────
  function onFiles(files: FileList | null) {
    const file = files?.[0];
    if (!file || !file.type.startsWith("video/")) return;
    if (videoUrl.startsWith("blob:")) URL.revokeObjectURL(videoUrl);

    const url = URL.createObjectURL(file);
    setVideoUrl(url);
    setVideoDead(false);
    setTitle(file.name.replace(/\.[^.]+$/, "") || "Untitled clip");
    setSavedId(null);
    setPromptSummary("");
    setPromptChips([]);
    setPhase("transcribing");

    // read duration via a hidden <video>
    const probe = probeRef.current;
    if (probe) {
      probe.src = url;
      // onloadedmetadata handler (below) kicks off transcription
    } else {
      // fallback: assume demo duration
      void startTranscribe(30, "16:9");
    }
  }

  async function onProbeLoaded() {
    const probe = probeRef.current;
    let d = probe?.duration ?? 0;
    if (!isFinite(d) || d <= 0) d = 30; // guard: no-audio / broken metadata
    const asp = aspectFromDims(
      probe?.videoWidth ?? 0,
      probe?.videoHeight ?? 0
    );
    setDurationSec(Math.round(d));
    setAspect(asp);
    await startTranscribe(Math.round(d), asp);
  }

  async function startTranscribe(d: number, _asp: VideoAspect) {
    try {
      const res = await transcribeClient({ durationSec: d });
      setSegments(res.segments || []);
      setEngine(res.engine || "demo");
    } catch {
      setSegments([]);
    } finally {
      setPhase("ready");
    }
  }

  // ── transcript editing ─────────────────────────────────────────
  function toggleSegment(id: string) {
    setSegments((prev) =>
      prev.map((s) => (s.id === id ? { ...s, removed: !s.removed } : s))
    );
  }

  // ── prompt interpreter (rule-based, self-contained) ────────────
  function applyPrompt() {
    const raw = prompt.trim();
    if (!raw) return;
    const p = raw.toLowerCase();
    const chips: string[] = [];

    if (/silen|dead ?air|pause/.test(p)) {
      setRemoveSilence(true);
      chips.push("Removed silence");
    }
    if (/\bum+s?\b|\buh+s?\b|filler|\berm\b|you know/.test(p)) {
      setRemoveFillers(true);
      chips.push("Struck filler words");
    }
    if (/best take|duplicate|alt(ernate)? take|retake|keep the (best|good)/.test(p)) {
      setBestTakeOnly(true);
      chips.push("Kept best takes");
    }
    if (/zoom|punch ?in|emphasi/.test(p)) {
      setAutoZoom(true);
      chips.push("Auto-zoom on");
    }
    if (/caption|subtitle|text on screen/.test(p)) {
      setCaptionsOn(true);
      let style: CaptionStyle = captionStyle;
      if (/punch|bold|big|loud/.test(p)) style = "bold";
      else if (/highlight|karaoke|box/.test(p)) style = "highlight";
      else if (/clean|minimal|simple|subtle/.test(p)) style = "clean";
      setCaptionStyle(style);
      chips.push(`Captions on · ${style}`);
    }
    if (/intro|the start|beginning|first bit/.test(p)) {
      let done = false;
      setSegments((prev) =>
        prev.map((s) => {
          if (!done && !s.isSilence && !s.removed) {
            done = true;
            return { ...s, removed: true };
          }
          return s;
        })
      );
      chips.push("Cut the intro");
    }

    // "under N seconds" / shorten / trim → drop trailing segments
    const numMatch = p.match(/(\d+)\s*(?:s|sec|second)/);
    const wantsShorter =
      /shorten|trim|tighten|under|less than|no longer than|max/.test(p) ||
      !!numMatch;
    if (wantsShorter) {
      const target = numMatch ? parseInt(numMatch[1], 10) : null;
      setSegments((prev) => {
        if (target && target > 0) {
          // keep from the front until we hit the budget
          let acc = 0;
          return prev.map((s) => {
            if (s.removed) return s;
            const len = s.end - s.start;
            if (acc + len > target && acc > 0) {
              return { ...s, removed: true };
            }
            if (!(removeSilence && s.isSilence)) acc += len;
            return s;
          });
        }
        // no number: drop the last kept, non-silence segment
        const idx = [...prev]
          .map((s, i) => ({ s, i }))
          .filter(({ s }) => !s.removed && !s.isSilence)
          .pop();
        if (!idx) return prev;
        return prev.map((s, i) =>
          i === idx.i ? { ...s, removed: true } : s
        );
      });
      chips.push(target ? `Trimmed to ~${target}s` : "Trimmed the ending");
    }

    setPromptChips(chips);
    setPromptSummary(
      chips.length
        ? `cre8tor applied ${chips.length} change${chips.length > 1 ? "s" : ""}.`
        : "Couldn't match that — try “remove silence”, “cut the ums”, or “add punchy captions”."
    );
    setPrompt("");
  }

  // ── player: skip removed runs + track caption ──────────────────
  const sortedSegs = useMemo(
    () => [...segments].sort((a, b) => a.start - b.start),
    [segments]
  );

  function onTimeUpdate() {
    const v = videoRef.current;
    if (!v) return;
    const t = v.currentTime;
    setCurrentTime(t);

    // if we're inside a CUT run, jump to the end of that run
    const idx = sortedSegs.findIndex(
      (s) => isCut(s) && t >= s.start - 0.02 && t < s.end
    );
    if (idx !== -1) {
      let end = sortedSegs[idx].end;
      for (let j = idx + 1; j < sortedSegs.length; j++) {
        if (isCut(sortedSegs[j]) && sortedSegs[j].start - end < 0.4) {
          end = sortedSegs[j].end;
        } else break;
      }
      if (end >= (v.duration || originalDuration) - 0.05) {
        v.pause();
        v.currentTime = Math.max(0, (v.duration || originalDuration) - 0.05);
        setIsPlaying(false);
      } else if (Math.abs(v.currentTime - end) > 0.05) {
        v.currentTime = end + 0.01;
      }
    }
  }

  const activeIndex = useMemo(() => {
    return sortedSegs.findIndex(
      (s) => !isCut(s) && currentTime >= s.start && currentTime < s.end
    );
  }, [sortedSegs, currentTime, isCut]);

  const activeSegment = activeIndex >= 0 ? sortedSegs[activeIndex] : null;

  const captionText = useMemo(() => {
    if (!captionsOn || !activeSegment || activeSegment.isSilence) return "";
    const words: TranscriptWord[] = activeSegment.words.length
      ? activeSegment.words
      : activeSegment.text
          .split(" ")
          .map((t) => ({ text: t, start: 0, end: 0 }));
    return words
      .filter((w) => !(removeFillers && w.filler))
      .map((w) => w.text)
      .join(" ");
  }, [captionsOn, activeSegment, removeFillers]);

  // auto-zoom pulse: emphasize alternating spoken segments
  const zoomActive =
    autoZoom &&
    !!activeSegment &&
    !activeSegment.isSilence &&
    activeIndex % 2 === 1;

  function play() {
    const v = videoRef.current;
    if (!v) return;
    // if starting inside a cut region, nudge to next kept frame
    v.play().catch(() => {});
  }
  function pause() {
    videoRef.current?.pause();
  }
  function restart() {
    const v = videoRef.current;
    if (!v) return;
    v.currentTime = 0;
    v.play().catch(() => {});
  }

  // ── save + export ──────────────────────────────────────────────
  function buildProject(): EditProject {
    const now = Date.now();
    // bake the current cut decisions into segment.removed
    const baked = segments.map((s) => ({ ...s, removed: isCut(s) }));
    return {
      id: uid(),
      title: title || "Untitled edit",
      videoUrl,
      durationSec: originalDuration,
      aspect,
      segments: baked,
      captionStyle,
      captionsOn,
      removeSilence,
      removeFillers,
      autoZoom,
      engine,
      createdAt: now,
      updatedAt: now,
    };
  }

  function saveEdit() {
    if (!segments.length) return;
    const project = buildProject();
    addEditProject(project);
    setSavedId(project.id);
  }

  async function copyPlan() {
    const kept = segments.filter((s) => !isCut(s));
    const lines = [
      `EDL — ${title || "Untitled edit"}`,
      `Original ${mmss(originalDuration)} → Edit ${mmss(editedDuration)} (${kept.length} clips)`,
      "",
      ...kept.map(
        (s, i) =>
          `${String(i + 1).padStart(2, "0")}  ${mmss(s.start)} → ${mmss(
            s.end
          )}   ${s.isSilence ? "(silence)" : s.text}`
      ),
    ];
    try {
      await navigator.clipboard.writeText(lines.join("\n"));
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      /* clipboard unavailable */
    }
  }

  function loadProject(e: EditProject) {
    if (videoUrl.startsWith("blob:")) URL.revokeObjectURL(videoUrl);
    setSegments(e.segments);
    setTitle(e.title);
    setDurationSec(e.durationSec);
    setAspect(e.aspect);
    setEngine(e.engine);
    setCaptionStyle(e.captionStyle);
    setCaptionsOn(e.captionsOn);
    setRemoveSilence(e.removeSilence);
    setRemoveFillers(e.removeFillers);
    setAutoZoom(e.autoZoom);
    setBestTakeOnly(false); // removals already baked into segments
    setVideoUrl(e.videoUrl);
    setVideoDead(false);
    setSavedId(e.id);
    setPhase("ready");
    setCurrentTime(0);
    setIsPlaying(false);
    setPromptSummary("");
    setPromptChips([]);
  }

  function resetEditor() {
    if (videoUrl.startsWith("blob:")) URL.revokeObjectURL(videoUrl);
    setPhase("empty");
    setVideoUrl("");
    setSegments([]);
    setSavedId(null);
    setPromptSummary("");
    setPromptChips([]);
    setCurrentTime(0);
    setIsPlaying(false);
  }

  const aspectClass =
    aspect === "9:16" ? "aspect-[9/16]" : aspect === "1:1" ? "aspect-square" : "aspect-video";

  // ── render ─────────────────────────────────────────────────────
  return (
    <div className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
      {/* hidden probe for duration/aspect */}
      <video
        ref={probeRef}
        onLoadedMetadata={onProbeLoaded}
        className="hidden"
        muted
        playsInline
        preload="metadata"
      />

      {/* header */}
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold tracking-tight">
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-brand-gradient text-white">
              <IconClapper width={18} height={18} />
            </span>
            AI Video Editor
          </h1>
          <p className="mt-1 text-sm text-ink-soft">
            Upload a clip — cre8tor transcribes it, cuts the dead air, kills the
            ums, and burns captions. Edit by prompt.
          </p>
        </div>
        <span className="chip">
          <IconMic width={13} height={13} className="text-brand-300" />
          {engine === "whisper" ? "Whisper transcript" : "Smart transcript"}
        </span>
      </div>

      {/* EMPTY STATE */}
      {phase === "empty" && (
        <UploadZone
          dragging={dragging}
          setDragging={setDragging}
          onFiles={onFiles}
          hydrated={hydrated}
          editProjects={editProjects}
          onLoad={loadProject}
          onDelete={deleteEditProject}
        />
      )}

      {/* TRANSCRIBING */}
      {phase === "transcribing" && (
        <div className="card grid place-items-center gap-3 px-6 py-20 text-center">
          <span className="h-9 w-9 animate-spin rounded-full border-2 border-line-strong border-t-brand-400" />
          <h3 className="text-lg font-semibold">Transcribing your clip…</h3>
          <p className="max-w-sm text-sm text-ink-soft">
            cre8tor is listening for words, silence, and duplicate takes. This
            only takes a second in demo mode.
          </p>
        </div>
      )}

      {/* EDITOR */}
      {phase === "ready" && (
        <div className="space-y-5">
          {/* toolbar */}
          <div className="card p-4">
            <div className="flex flex-wrap items-center gap-2">
              <ToggleChip
                active={removeSilence}
                onClick={() => setRemoveSilence((v) => !v)}
                label="Remove silence"
              />
              <ToggleChip
                active={removeFillers}
                onClick={() => setRemoveFillers((v) => !v)}
                label={`Remove fillers${fillerCount ? ` · ${fillerCount}` : ""}`}
              />
              <ToggleChip
                active={bestTakeOnly}
                onClick={() => setBestTakeOnly((v) => !v)}
                label="Best take only"
              />
              <ToggleChip
                active={autoZoom}
                onClick={() => setAutoZoom((v) => !v)}
                label="Auto zoom"
              />
              <ToggleChip
                active={captionsOn}
                onClick={() => setCaptionsOn((v) => !v)}
                label="Captions"
              />
              <div className="ml-auto flex items-center gap-1 rounded-full border border-line-strong bg-white/[0.02] p-0.5">
                {CAPTION_STYLES.map((c) => (
                  <button
                    key={c.key}
                    onClick={() => {
                      setCaptionStyle(c.key);
                      setCaptionsOn(true);
                    }}
                    className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                      captionStyle === c.key
                        ? "bg-brand-500/25 text-brand-100"
                        : "text-ink-soft hover:text-ink"
                    }`}
                  >
                    {c.label}
                  </button>
                ))}
              </div>
            </div>

            {/* prompt-to-edit */}
            <div className="mt-4">
              <div className="flex flex-col gap-2 sm:flex-row">
                <input
                  className="input"
                  placeholder="Tell cre8tor what to change — e.g. “cut the intro and remove all the ums”"
                  value={prompt}
                  onChange={(e) => setPrompt(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && applyPrompt()}
                />
                <button
                  onClick={applyPrompt}
                  disabled={!prompt.trim()}
                  className="btn-primary shrink-0"
                >
                  <IconSpark width={16} height={16} /> Apply
                </button>
              </div>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {PROMPT_EXAMPLES.map((ex) => (
                  <button
                    key={ex}
                    onClick={() => setPrompt(ex)}
                    className="rounded-full border border-line bg-white/[0.02] px-3 py-1 text-xs text-ink-soft hover:border-brand-500/40 hover:text-ink"
                  >
                    {ex}
                  </button>
                ))}
              </div>
              {promptSummary && (
                <div className="mt-2 flex flex-wrap items-center gap-2 rounded-lg border border-line bg-white/[0.02] px-3 py-2 text-xs text-ink-soft">
                  <span>{promptSummary}</span>
                  {promptChips.map((c) => (
                    <span
                      key={c}
                      className="rounded-full border border-brand-400/30 bg-brand-500/10 px-2 py-0.5 text-brand-200"
                    >
                      {c}
                    </span>
                  ))}
                </div>
              )}
            </div>
          </div>

          <div className="grid gap-5 lg:grid-cols-[1fr_360px]">
            {/* LEFT: transcript editor */}
            <div className="card p-4">
              <div className="mb-3 flex items-center justify-between">
                <h2 className="flex items-center gap-2 font-semibold">
                  <IconLayers width={16} height={16} className="text-brand-300" />
                  Transcript
                </h2>
                <span className="text-xs text-ink-faint">
                  {segments.length - cutCount}/{segments.length} kept
                </span>
              </div>
              <div className="space-y-1.5">
                {segments.map((seg) => (
                  <SegmentRow
                    key={seg.id}
                    seg={seg}
                    cut={isCut(seg)}
                    active={activeSegment?.id === seg.id}
                    removeFillers={removeFillers}
                    onToggle={() => toggleSegment(seg.id)}
                  />
                ))}
              </div>
            </div>

            {/* RIGHT: preview + controls */}
            <div className="space-y-4 lg:sticky lg:top-6 lg:self-start">
              <div className="card p-4">
                <div className="mb-3 text-xs font-semibold uppercase tracking-wide text-ink-faint">
                  Preview · edit skips cuts
                </div>
                <div
                  className={`relative mx-auto w-full max-w-[320px] overflow-hidden rounded-2xl border border-line bg-black ${aspectClass}`}
                >
                  {videoUrl && !videoDead ? (
                    <video
                      ref={videoRef}
                      src={videoUrl}
                      playsInline
                      onTimeUpdate={onTimeUpdate}
                      onPlay={() => setIsPlaying(true)}
                      onPause={() => setIsPlaying(false)}
                      onEnded={() => setIsPlaying(false)}
                      onError={() => setVideoDead(true)}
                      className="h-full w-full object-cover"
                      style={{
                        transform: zoomActive ? "scale(1.08)" : "scale(1)",
                        transition: `transform ${zoomActive ? 2.6 : 0.6}s ease-out`,
                      }}
                    />
                  ) : (
                    <div className="grid h-full place-items-center px-5 text-center text-xs text-ink-faint">
                      <div>
                        <IconVideo
                          width={22}
                          height={22}
                          className="mx-auto mb-2"
                        />
                        {videoDead
                          ? "This saved clip's source expired. Re-upload the file to preview — your edit plan is intact."
                          : "No video loaded."}
                      </div>
                    </div>
                  )}

                  {/* caption overlay (lower third / safe zone) */}
                  {captionText && !videoDead && (
                    <div className="pointer-events-none absolute inset-x-0 bottom-[12%] flex justify-center px-4">
                      <Caption text={captionText} style={captionStyle} />
                    </div>
                  )}
                </div>

                {/* transport */}
                <div className="mt-3 flex items-center justify-center gap-2">
                  {isPlaying ? (
                    <button onClick={pause} className="btn-ghost !px-4 !py-2">
                      Pause
                    </button>
                  ) : (
                    <button onClick={play} className="btn-primary !px-4 !py-2">
                      Play
                    </button>
                  )}
                  <button onClick={restart} className="btn-ghost !px-4 !py-2">
                    Restart
                  </button>
                </div>

                {/* duration readout */}
                <div className="mt-3 grid grid-cols-2 gap-2 text-center">
                  <div className="rounded-xl border border-line bg-white/[0.02] px-3 py-2">
                    <div className="flex items-center justify-center gap-1 text-[11px] text-ink-faint">
                      <IconClock width={11} height={11} /> Original
                    </div>
                    <div className="text-sm font-semibold text-ink-soft">
                      {mmss(originalDuration)}
                    </div>
                  </div>
                  <div className="rounded-xl border border-brand-400/30 bg-brand-500/10 px-3 py-2">
                    <div className="flex items-center justify-center gap-1 text-[11px] text-brand-200/80">
                      <IconSpark width={11} height={11} /> Edited
                    </div>
                    <div className="text-sm font-semibold text-brand-100">
                      {mmss(editedDuration)}
                    </div>
                  </div>
                </div>
              </div>

              {/* export */}
              <div className="card space-y-2 p-4">
                <div className="flex flex-wrap gap-2">
                  <button onClick={saveEdit} className="btn-primary flex-1">
                    {savedId ? (
                      <>
                        <IconCheck
                          width={16}
                          height={16}
                          className="text-white"
                        />{" "}
                        Saved
                      </>
                    ) : (
                      <>
                        <IconPlus width={16} height={16} /> Save edit
                      </>
                    )}
                  </button>
                  <button onClick={copyPlan} className="btn-ghost flex-1">
                    {copied ? (
                      <>
                        <IconCheck
                          width={16}
                          height={16}
                          className="text-accent-lime"
                        />{" "}
                        Copied
                      </>
                    ) : (
                      <>
                        <IconCopy width={16} height={16} /> Copy edit plan
                      </>
                    )}
                  </button>
                </div>
                <button
                  onClick={resetEditor}
                  className="btn-subtle w-full !py-2 text-xs"
                >
                  <IconX width={13} height={13} /> Start over with a new clip
                </button>
                <p className="text-[11px] leading-relaxed text-ink-faint">
                  Full one-click MP4 export renders on the server when a render
                  provider is configured. In demo mode, copy the edit plan (EDL)
                  or hand these cuts to your editor.
                </p>
              </div>
            </div>
          </div>

          {/* recent edits */}
          {hydrated && editProjects.length > 0 && (
            <RecentEdits
              editProjects={editProjects}
              currentId={savedId}
              onLoad={loadProject}
              onDelete={deleteEditProject}
            />
          )}
        </div>
      )}
    </div>
  );
}

// ── sub-components ───────────────────────────────────────────────

function ToggleChip({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition ${
        active
          ? "border-brand-400/50 bg-brand-500/15 text-brand-100"
          : "border-line-strong bg-white/[0.02] text-ink-soft hover:text-ink"
      }`}
    >
      <span
        className={`h-1.5 w-1.5 rounded-full ${
          active ? "bg-accent-lime" : "bg-ink-faint"
        }`}
      />
      {label}
    </button>
  );
}

function SegmentRow({
  seg,
  cut,
  active,
  removeFillers,
  onToggle,
}: {
  seg: TranscriptSegment;
  cut: boolean;
  active: boolean;
  removeFillers: boolean;
  onToggle: () => void;
}) {
  return (
    <div
      className={`group flex gap-3 rounded-xl border px-3 py-2.5 transition ${
        active
          ? "border-brand-400/50 bg-brand-500/10"
          : cut
          ? "border-line bg-white/[0.01]"
          : "border-line bg-white/[0.02] hover:border-line-strong"
      }`}
    >
      <button
        onClick={onToggle}
        title={cut ? "Keep this line" : "Cut this line"}
        className={`mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-lg border transition ${
          cut
            ? "border-line-strong bg-white/[0.02] text-ink-faint hover:text-ink"
            : "border-brand-400/40 bg-brand-500/15 text-brand-200"
        }`}
      >
        {cut ? <IconPlus width={13} height={13} /> : <IconCheck width={13} height={13} />}
      </button>

      <button onClick={onToggle} className="min-w-0 flex-1 text-left">
        <div className="mb-0.5 flex flex-wrap items-center gap-1.5">
          <span className="font-mono text-[10px] text-ink-faint">
            {mmss(seg.start)}–{mmss(seg.end)}
          </span>
          {seg.isSilence && (
            <span className="rounded-full border border-accent-warm/30 bg-accent-warm/10 px-1.5 py-0.5 text-[10px] text-accent-warm">
              silence
            </span>
          )}
          {seg.isAltTake && (
            <span className="rounded-full border border-accent/30 bg-accent/10 px-1.5 py-0.5 text-[10px] text-accent">
              alternate take
            </span>
          )}
          {cut && (
            <span className="rounded-full border border-line-strong bg-white/[0.03] px-1.5 py-0.5 text-[10px] text-ink-faint">
              cut
            </span>
          )}
        </div>
        <p
          className={`text-sm leading-snug ${
            cut ? "text-ink-faint line-through" : "text-ink"
          }`}
        >
          {seg.isSilence ? (
            <span className="italic text-ink-faint">(silence)</span>
          ) : seg.words.length ? (
            seg.words.map((w, i) => (
              <span
                key={i}
                className={
                  w.filler
                    ? `text-accent-warm ${removeFillers ? "line-through opacity-60" : ""}`
                    : ""
                }
              >
                {w.text}
                {i < seg.words.length - 1 ? " " : ""}
              </span>
            ))
          ) : (
            seg.text
          )}
        </p>
      </button>

      <button
        onClick={onToggle}
        title={cut ? "Keep" : "Cut"}
        className="mt-0.5 self-start text-ink-faint opacity-0 transition hover:text-red-400 group-hover:opacity-100"
      >
        <IconTrash width={14} height={14} />
      </button>
    </div>
  );
}

function Caption({ text, style }: { text: string; style: CaptionStyle }) {
  if (style === "highlight") {
    return (
      <span className="rounded-lg bg-brand-600 px-2.5 py-1 text-center text-[13px] font-bold leading-tight text-white shadow-[0_6px_20px_-6px_rgba(99,102,241,0.9)]">
        {text}
      </span>
    );
  }
  if (style === "bold") {
    return (
      <span
        className="text-center text-lg font-black uppercase leading-tight tracking-tight text-white"
        style={{
          WebkitTextStroke: "1.5px rgba(0,0,0,0.9)",
          textShadow: "0 2px 10px rgba(0,0,0,0.8)",
        }}
      >
        {text}
      </span>
    );
  }
  // clean
  return (
    <span
      className="text-center text-sm font-medium leading-tight text-white"
      style={{ textShadow: "0 1px 6px rgba(0,0,0,0.9)" }}
    >
      {text}
    </span>
  );
}

function UploadZone({
  dragging,
  setDragging,
  onFiles,
  hydrated,
  editProjects,
  onLoad,
  onDelete,
}: {
  dragging: boolean;
  setDragging: (v: boolean) => void;
  onFiles: (files: FileList | null) => void;
  hydrated: boolean;
  editProjects: EditProject[];
  onLoad: (e: EditProject) => void;
  onDelete: (id: string) => void;
}) {
  const inputRef = useRef<HTMLInputElement | null>(null);
  return (
    <div className="space-y-5">
      <label
        onDragOver={(e) => {
          e.preventDefault();
          setDragging(true);
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragging(false);
          onFiles(e.dataTransfer.files);
        }}
        className={`card flex cursor-pointer flex-col items-center justify-center gap-3 px-6 py-16 text-center transition ${
          dragging ? "border-brand-400 bg-brand-500/5" : "hover:border-line-strong"
        }`}
      >
        <input
          ref={inputRef}
          type="file"
          accept="video/*"
          className="hidden"
          onChange={(e) => onFiles(e.target.files)}
        />
        <span className="grid h-14 w-14 place-items-center rounded-2xl bg-brand-gradient text-white">
          <IconVideo width={26} height={26} />
        </span>
        <h3 className="text-lg font-semibold">Drop a video to start editing</h3>
        <p className="max-w-md text-sm text-ink-soft">
          Any talking-head clip works — a Reel, a webinar cut, a raw selfie
          take. cre8tor transcribes it, then you cut silence, kill filler words,
          keep the best take, and burn captions in a couple clicks.
        </p>
        <span className="btn-primary mt-1">
          <IconPlus width={16} height={16} /> Choose a video
        </span>
        <p className="text-[11px] text-ink-faint">
          MP4, MOV, WebM · nothing leaves your browser in demo mode
        </p>
      </label>

      {/* quick "how it works" */}
      <div className="grid gap-3 sm:grid-cols-3">
        {[
          {
            Icon: IconMic,
            t: "1 · Transcribe",
            d: "Word-level timing with silence + duplicate-take detection.",
          },
          {
            Icon: IconClapper,
            t: "2 · Edit by prompt",
            d: "“Cut the intro, remove the ums, add punchy captions.”",
          },
          {
            Icon: IconSpark,
            t: "3 · Preview live",
            d: "Playback skips every cut and burns captions in the safe zone.",
          },
        ].map(({ Icon, t, d }) => (
          <div key={t} className="card p-4">
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-brand-500/10 text-brand-300">
              <Icon width={18} height={18} />
            </span>
            <h4 className="mt-2 text-sm font-semibold">{t}</h4>
            <p className="mt-1 text-xs text-ink-soft">{d}</p>
          </div>
        ))}
      </div>

      {hydrated && editProjects.length > 0 && (
        <RecentEdits
          editProjects={editProjects}
          currentId={null}
          onLoad={onLoad}
          onDelete={onDelete}
        />
      )}
    </div>
  );
}

function RecentEdits({
  editProjects,
  currentId,
  onLoad,
  onDelete,
}: {
  editProjects: EditProject[];
  currentId: string | null;
  onLoad: (e: EditProject) => void;
  onDelete: (id: string) => void;
}) {
  return (
    <div className="card p-4">
      <div className="mb-3 text-xs font-semibold uppercase tracking-wide text-ink-faint">
        Recent edits
      </div>
      <div className="space-y-2">
        {editProjects.map((e) => {
          const kept = e.segments.filter((s) => !s.removed).length;
          return (
            <div
              key={e.id}
              className={`group flex items-center gap-3 rounded-xl border px-3 py-2.5 transition ${
                currentId === e.id
                  ? "border-brand-400/40 bg-brand-500/10"
                  : "border-line bg-white/[0.02] hover:border-line-strong"
              }`}
            >
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-brand-500/10 text-brand-300">
                <IconClapper width={15} height={15} />
              </span>
              <button
                onClick={() => onLoad(e)}
                className="min-w-0 flex-1 text-left"
              >
                <span className="block truncate text-sm font-medium">
                  {e.title}
                </span>
                <span className="block text-[11px] text-ink-faint">
                  {kept}/{e.segments.length} clips · {mmss(e.durationSec)} ·{" "}
                  {timeAgo(e.updatedAt)}
                </span>
              </button>
              {e.captionsOn && (
                <span className="hidden shrink-0 rounded-full border border-line-strong bg-white/[0.03] px-2 py-0.5 text-[10px] capitalize text-ink-soft sm:inline">
                  {e.captionStyle}
                </span>
              )}
              <button
                onClick={() => onDelete(e.id)}
                title="Delete"
                className="shrink-0 text-ink-faint opacity-0 transition hover:text-red-400 group-hover:opacity-100"
              >
                <IconTrash width={14} height={14} />
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
