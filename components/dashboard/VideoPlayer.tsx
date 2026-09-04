"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { VIDEO_BG } from "@/lib/seed";
import type { VideoScene, VideoKind, VideoAspect } from "@/lib/types";

const ASPECT_CLASS: Record<VideoAspect, string> = {
  "9:16": "aspect-[9/16]",
  "1:1": "aspect-square",
  "16:9": "aspect-video",
};

// Plays real rendered MP4 clips (one per scene) sequentially, with captions.
function ClipReel({
  scenes,
  clips,
  aspect,
  className = "",
}: {
  scenes: VideoScene[];
  clips: { sceneId: string; url: string }[];
  aspect: VideoAspect;
  className?: string;
}) {
  const [i, setI] = useState(0);
  const ref = useRef<HTMLVideoElement>(null);
  const clip = clips[i];
  const scene = scenes.find((s) => s.id === clip?.sceneId);

  useEffect(() => {
    ref.current?.play().catch(() => {});
  }, [i]);

  return (
    <div className={className}>
      <div className={`relative mx-auto w-full max-w-[300px] overflow-hidden rounded-2xl border border-line ${ASPECT_CLASS[aspect]}`}>
        <video
          ref={ref}
          key={clip?.url}
          src={clip?.url}
          className="h-full w-full object-cover"
          playsInline
          controls={false}
          onEnded={() => setI((p) => (p + 1 < clips.length ? p + 1 : p))}
        />
        {scene?.caption && (
          <div className="pointer-events-none absolute inset-x-0 top-1/2 -translate-y-1/2 px-5 text-center">
            <span className="inline-block rounded-xl bg-black/35 px-3 py-2 text-lg font-extrabold leading-tight text-white drop-shadow">
              {scene.caption}
            </span>
          </div>
        )}
        <div className="absolute left-3 top-3 rounded-full bg-black/40 px-2 py-0.5 text-[10px] font-semibold text-white">
          clip {i + 1}/{clips.length} · Higgsfield
        </div>
      </div>
      <div className="mx-auto mt-3 flex w-full max-w-[300px] items-center justify-between">
        <div className="flex gap-1.5">
          <button onClick={() => { setI(0); }} className="btn-ghost h-9 px-3 text-xs">
            Restart
          </button>
          {clips.length > 1 && (
            <button
              onClick={() => setI((p) => (p + 1 < clips.length ? p + 1 : 0))}
              className="btn-ghost h-9 px-3 text-xs"
            >
              Next clip
            </button>
          )}
        </div>
        <a href={clip?.url} target="_blank" rel="noreferrer" className="btn-primary h-9 px-3 text-xs">
          Download
        </a>
      </div>
      <p className="mt-1.5 text-center text-[10px] text-ink-faint">
        Rendered with Higgsfield · {clips.length} clip{clips.length > 1 ? "s" : ""}
      </p>
    </div>
  );
}

export function VideoPlayer({
  scenes,
  kind,
  aspect = "9:16",
  persona,
  renderUrl,
  clips,
  className = "",
}: {
  scenes: VideoScene[];
  kind: VideoKind;
  aspect?: VideoAspect;
  persona?: string;
  renderUrl?: string;
  clips?: { sceneId: string; url: string }[];
  className?: string;
}) {
  // Real rendered clips (e.g. Higgsfield MP4s) → play them back-to-back.
  if (clips && clips.length > 0) {
    return (
      <ClipReel scenes={scenes} clips={clips} aspect={aspect} className={className} />
    );
  }
  const [playing, setPlaying] = useState(false);
  const [idx, setIdx] = useState(0);
  const [elapsed, setElapsed] = useState(0); // seconds within current scene
  const [muted, setMuted] = useState(false);
  const tick = useRef<ReturnType<typeof setInterval> | null>(null);
  const spokenFor = useRef<number>(-1);

  const total = scenes.reduce((s, sc) => s + sc.durationSec, 0);
  const before = scenes.slice(0, idx).reduce((s, sc) => s + sc.durationSec, 0);
  const globalElapsed = before + elapsed;
  const scene = scenes[idx];

  const speak = useCallback(
    (text: string) => {
      if (muted || typeof window === "undefined" || !window.speechSynthesis || !text) return;
      window.speechSynthesis.cancel();
      const u = new SpeechSynthesisUtterance(text);
      u.rate = 1.05;
      u.pitch = 1;
      window.speechSynthesis.speak(u);
    },
    [muted]
  );

  const stopSpeech = () => {
    if (typeof window !== "undefined" && window.speechSynthesis) window.speechSynthesis.cancel();
  };

  const reset = useCallback(() => {
    setPlaying(false);
    setIdx(0);
    setElapsed(0);
    spokenFor.current = -1;
    stopSpeech();
  }, []);

  // main timeline loop
  useEffect(() => {
    if (!playing) return;
    tick.current = setInterval(() => {
      setElapsed((e) => {
        const cur = scenes[idx];
        if (!cur) return e;
        const nextE = e + 0.1;
        if (nextE >= cur.durationSec) {
          if (idx >= scenes.length - 1) {
            setPlaying(false);
            stopSpeech();
            return cur.durationSec;
          }
          setIdx((i) => i + 1);
          return 0;
        }
        return nextE;
      });
    }, 100);
    return () => {
      if (tick.current) clearInterval(tick.current);
    };
  }, [playing, idx, scenes]);

  // speak at the start of each scene while playing
  useEffect(() => {
    if (playing && scene && spokenFor.current !== idx) {
      spokenFor.current = idx;
      speak(scene.voiceover);
    }
  }, [playing, idx, scene, speak]);

  // cleanup on unmount
  useEffect(() => () => stopSpeech(), []);

  function togglePlay() {
    if (playing) {
      setPlaying(false);
      stopSpeech();
    } else {
      if (globalElapsed >= total) {
        setIdx(0);
        setElapsed(0);
      }
      spokenFor.current = -1;
      setPlaying(true);
    }
  }

  function seekScene(i: number) {
    stopSpeech();
    spokenFor.current = -1;
    setIdx(i);
    setElapsed(0);
    if (playing) spokenFor.current = -1;
  }

  const bg = VIDEO_BG[scene?.bg] || VIDEO_BG.indigo;
  const initials = (persona || "Creator")
    .split(/[\s—-]+/)
    .map((w) => w[0])
    .filter(Boolean)
    .slice(0, 2)
    .join("")
    .toUpperCase();

  return (
    <div className={className}>
      {/* stage */}
      <div className={`relative mx-auto w-full max-w-[300px] overflow-hidden rounded-2xl border border-line ${ASPECT_CLASS[aspect]}`}>
        {renderUrl ? (
          <video src={renderUrl} controls className="h-full w-full object-cover" />
        ) : (
          <div
            className="relative h-full w-full"
            style={{ background: bg, transition: "background 0.6s ease" }}
          >
            {/* subtle motion */}
            <div
              key={idx}
              className="absolute inset-0"
              style={{
                background:
                  "radial-gradient(60% 60% at 30% 20%, rgba(255,255,255,0.22), transparent 60%)",
                animation: playing ? "spin-slow 14s linear infinite" : "none",
              }}
            />

            {/* UGC persona bubble */}
            {kind === "ugc" && (
              <div className="absolute bottom-4 right-3 grid h-16 w-16 place-items-center rounded-full border-2 border-white/40 bg-black/30 text-lg font-bold text-white backdrop-blur">
                {initials}
              </div>
            )}

            {/* caption */}
            <div className="absolute inset-x-0 top-1/2 -translate-y-1/2 px-5 text-center">
              <span
                key={`cap-${idx}`}
                className="inline-block animate-fade-up rounded-xl bg-black/35 px-3 py-2 text-lg font-extrabold leading-tight text-white drop-shadow"
                style={{ textWrap: "balance" as any }}
              >
                {scene?.caption}
              </span>
            </div>

            {/* voiceover subtitle */}
            <div className="absolute inset-x-0 bottom-4 px-4 text-center">
              <p className="mx-auto max-w-[240px] text-xs font-medium text-white/90 drop-shadow">
                {scene?.voiceover}
              </p>
            </div>

            {/* scene counter */}
            <div className="absolute left-3 top-3 rounded-full bg-black/40 px-2 py-0.5 text-[10px] font-semibold text-white">
              {idx + 1}/{scenes.length}
            </div>

            {/* big play overlay when paused at start */}
            {!playing && globalElapsed === 0 && (
              <button
                onClick={togglePlay}
                className="absolute inset-0 grid place-items-center bg-black/20"
                aria-label="Play"
              >
                <span className="grid h-14 w-14 place-items-center rounded-full bg-white/90 text-black shadow-lg">
                  <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M8 5v14l11-7z" />
                  </svg>
                </span>
              </button>
            )}
          </div>
        )}
      </div>

      {/* timeline / controls */}
      {!renderUrl && (
        <div className="mx-auto mt-3 w-full max-w-[300px]">
          <div className="flex gap-1">
            {scenes.map((sc, i) => (
              <button
                key={sc.id}
                onClick={() => seekScene(i)}
                className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10"
                title={`Scene ${i + 1}`}
                style={{ flexGrow: sc.durationSec }}
              >
                <span
                  className="block h-full rounded-full bg-brand-gradient"
                  style={{
                    width: i < idx ? "100%" : i === idx ? `${(elapsed / sc.durationSec) * 100}%` : "0%",
                  }}
                />
              </button>
            ))}
          </div>

          <div className="mt-2.5 flex items-center justify-between">
            <div className="flex items-center gap-1.5">
              <button onClick={togglePlay} className="btn-primary h-9 px-4 text-xs">
                {playing ? "Pause" : globalElapsed >= total ? "Replay" : "Play"}
              </button>
              <button onClick={reset} className="btn-ghost h-9 px-3 text-xs">
                Restart
              </button>
            </div>
            <div className="flex items-center gap-2 text-xs text-ink-faint">
              <button
                onClick={() => {
                  setMuted((m) => !m);
                  if (!muted) stopSpeech();
                }}
                className={`rounded-lg px-2 py-1 ${muted ? "text-ink-faint" : "text-brand-300"} hover:bg-white/5`}
                title={muted ? "Voiceover off" : "Voiceover on"}
              >
                {muted ? "🔇 VO off" : "🔊 VO on"}
              </button>
              <span>~{Math.round(total)}s</span>
            </div>
          </div>
          <p className="mt-1.5 text-center text-[10px] text-ink-faint">
            In-browser preview · voiceover uses your device speech engine
          </p>
        </div>
      )}
    </div>
  );
}
