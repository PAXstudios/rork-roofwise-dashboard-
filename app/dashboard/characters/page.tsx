"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useStore } from "@/lib/store";
import { useHydrated } from "@/lib/hooks";
import {
  createCharacter,
  generatePortraitClient,
  listHeyGenAvatars,
  type HeyGenAvatarItem,
} from "@/lib/studioClient";
import { CharacterAvatar } from "@/components/dashboard/CharacterPicker";
import type { Character } from "@/lib/types";
import {
  IconPlus,
  IconSpark,
  IconTrash,
  IconCheck,
  IconX,
  IconMic,
  IconVideo,
} from "@/components/Icons";

const MAX_PHOTOS = 8;

export default function CharactersPage() {
  const hydrated = useHydrated();
  const characters = useStore((s) => s.characters);
  const deleteCharacter = useStore((s) => s.deleteCharacter);

  const addCharacter = useStore((s) => s.addCharacter);
  const [creating, setCreating] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [heygen, setHeygen] = useState<HeyGenAvatarItem[]>([]);
  const [heygenState, setHeygenState] = useState<"loading" | "off" | "error" | "ready">("loading");

  useEffect(() => {
    let cancelled = false;
    listHeyGenAvatars()
      .then((res) => {
        if (cancelled) return;
        if (!res.configured) setHeygenState("off");
        else if (!res.ok) setHeygenState("error");
        else {
          setHeygen(res.avatars);
          setHeygenState("ready");
        }
      })
      .catch(() => !cancelled && setHeygenState("error"));
    return () => {
      cancelled = true;
    };
  }, []);

  function addHeyGenAvatar(a: HeyGenAvatarItem) {
    if (characters.some((c) => c.heygenAvatarId === a.id)) {
      setToast(`${a.name} is already in your characters.`);
      window.setTimeout(() => setToast(null), 3000);
      return;
    }
    addCharacter({
      id: `char-${Math.random().toString(36).slice(2, 10)}`,
      name: a.name,
      kind: "custom",
      vibe: "real HeyGen presenter — speaks your script with lip-sync",
      gender: (a.gender as Character["gender"]) || undefined,
      imageUrl: a.preview,
      heygenAvatarId: a.id,
      heygenPreviewVideo: a.previewVideo,
      status: "ready",
      engine: "heygen",
      createdAt: Date.now(),
    });
    setToast(`${a.name} added — pick them in the UGC studio.`);
    window.setTimeout(() => setToast(null), 3500);
  }

  const { presets, custom } = useMemo(() => {
    return {
      presets: characters.filter((c) => c.kind === "preset"),
      custom: characters.filter((c) => c.kind === "custom"),
    };
  }, [characters]);

  function flashToast(msg: string) {
    setToast(msg);
    window.setTimeout(() => setToast(null), 4000);
  }

  return (
    <div className="mx-auto max-w-6xl px-5 py-6 sm:px-8">
      {/* header */}
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold tracking-tight">
            <span className="grid h-9 w-9 place-items-center rounded-xl bg-brand-gradient text-white">
              <IconMic width={18} height={18} />
            </span>
            Characters
          </h1>
          <p className="mt-1 max-w-xl text-sm text-ink-soft">
            Pick a ready-made UGC creator to front your videos — or upload your own
            face and train an AI twin you can reuse forever.
          </p>
        </div>
        <span className="chip">
          <IconSpark width={13} height={13} className="text-brand-300" />
          Powered by HeyGen + Higgsfield
        </span>
      </div>

      {/* create-your-own banner */}
      <button
        onClick={() => setCreating(true)}
        className="group mb-8 flex w-full items-center gap-4 rounded-2xl border border-dashed border-line-strong bg-white/[0.02] p-5 text-left transition hover:border-brand-500/50 hover:bg-white/[0.04]"
      >
        <span className="grid h-14 w-14 shrink-0 place-items-center rounded-2xl bg-brand-gradient text-white">
          <IconPlus width={22} height={22} />
        </span>
        <span className="min-w-0">
          <span className="block font-semibold">Create your own character</span>
          <span className="block text-sm text-ink-soft">
            Scan your face with the camera (or upload photos) and cre8tor analyzes
            it into a realistic AI twin — yours to cast in every UGC video.
          </span>
        </span>
        <span className="ml-auto hidden shrink-0 text-brand-300 transition group-hover:translate-x-0.5 sm:block">
          <IconSpark width={18} height={18} />
        </span>
      </button>

      {!hydrated ? (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="card h-48 animate-pulse bg-white/[0.02]" />
          ))}
        </div>
      ) : (
        <>
          {/* your characters (custom) */}
          {custom.length > 0 && (
            <section className="mb-8">
              <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-faint">
                Your characters
              </h2>
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
                {custom.map((c) => (
                  <CharacterCard
                    key={c.id}
                    character={c}
                    onDelete={() => deleteCharacter(c.id)}
                  />
                ))}
              </div>
            </section>
          )}

          {/* HeyGen real-avatar library */}
          <section className="mb-8">
            <div className="mb-3 flex items-center justify-between">
              <h2 className="text-sm font-semibold uppercase tracking-wide text-ink-faint">
                HeyGen avatar library
              </h2>
              <span className="chip !text-[10px]">real presenters · lip-synced speech</span>
            </div>

            {heygenState === "loading" && (
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
                {Array.from({ length: 5 }).map((_, i) => (
                  <div key={i} className="card h-44 animate-pulse bg-white/[0.02]" />
                ))}
              </div>
            )}

            {heygenState === "off" && (
              <div className="card p-4 text-sm text-ink-soft">
                Connect HeyGen to browse 100+ real human avatars: add{" "}
                <code className="rounded bg-white/[0.06] px-1.5 py-0.5 text-xs">HEYGEN_API_KEY=…</code>{" "}
                to <code className="rounded bg-white/[0.06] px-1.5 py-0.5 text-xs">.env.local</code> and
                restart the dev server.
              </div>
            )}

            {heygenState === "error" && (
              <div className="card p-4 text-sm text-amber-200">
                Couldn&apos;t reach HeyGen right now — check your API key or try again shortly.
              </div>
            )}

            {heygenState === "ready" && (
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
                {heygen.slice(0, 20).map((a) => (
                  <div key={a.id} className="card group flex flex-col overflow-hidden p-0">
                    <div className="relative aspect-[4/5] w-full overflow-hidden bg-bg-elevated">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img
                        src={a.preview}
                        alt={a.name}
                        className="h-full w-full object-cover transition group-hover:scale-[1.03]"
                        loading="lazy"
                      />
                      {a.premium && (
                        <span className="absolute left-2 top-2 rounded-full bg-black/60 px-2 py-0.5 text-[10px] font-semibold text-amber-300">
                          Premium
                        </span>
                      )}
                    </div>
                    <div className="flex items-center justify-between gap-2 p-2.5">
                      <div className="min-w-0">
                        <p className="truncate text-xs font-semibold">{a.name}</p>
                        <p className="text-[10px] capitalize text-ink-faint">{a.gender || "presenter"}</p>
                      </div>
                      <button
                        onClick={() => addHeyGenAvatar(a)}
                        className="btn-primary h-7 shrink-0 !px-2.5 text-[11px]"
                      >
                        <IconPlus width={11} height={11} /> Add
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>

          {/* preset library */}
          <section>
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-ink-faint">
              Illustrated presets
            </h2>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
              {presets.map((c) => (
                <CharacterCard key={c.id} character={c} />
              ))}
            </div>
          </section>
        </>
      )}

      {/* explainer */}
      <div className="card mt-8 flex flex-col gap-3 p-5 sm:flex-row sm:items-center">
        <span className="grid h-11 w-11 shrink-0 place-items-center rounded-xl bg-brand-500/15 text-brand-300">
          <IconSpark width={20} height={20} />
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-semibold">One character, every video</p>
          <p className="text-sm text-ink-soft">
            Once a character is ready, cast it in the UGC generator and it stays
            consistent across every hook, script, and post — same face, same vibe.
          </p>
        </div>
        <Link href="/dashboard/ugc" className="btn-primary shrink-0">
          <IconMic width={16} height={16} /> Open UGC studio
        </Link>
      </div>

      {creating && (
        <CreateCharacterModal
          onClose={() => setCreating(false)}
          onCreated={(msg) => flashToast(msg)}
        />
      )}

      {/* toast */}
      {toast && (
        <div className="fixed bottom-5 left-1/2 z-50 -translate-x-1/2 animate-fade-up">
          <div className="flex items-center gap-2 rounded-xl border border-line-strong bg-bg-elevated px-4 py-2.5 text-sm shadow-lg">
            <IconCheck width={15} height={15} className="text-accent-lime" />
            {toast}
          </div>
        </div>
      )}
    </div>
  );
}

function CharacterCard({
  character,
  onDelete,
}: {
  character: Character;
  onDelete?: () => void;
}) {
  const isCustom = character.kind === "custom";
  const training = character.status === "training";
  const failed = character.status === "failed";

  return (
    <div className="card group relative flex flex-col items-center p-4 text-center">
      {onDelete && (
        <button
          onClick={onDelete}
          aria-label={`Delete ${character.name}`}
          className="absolute right-2 top-2 rounded-lg p-1 text-ink-faint opacity-0 transition hover:text-red-400 group-hover:opacity-100"
        >
          <IconTrash width={15} height={15} />
        </button>
      )}

      <CharacterAvatar character={character} size={72} />

      <div className="mt-3 flex items-center gap-1.5">
        <span className="font-semibold">{character.name}</span>
        {isCustom && character.soulId && (
          <span className="chip !px-2 !py-0.5 !text-[10px]">
            <IconSpark width={10} height={10} className="text-brand-300" />
            AI twin
          </span>
        )}
      </div>

      <span
        className={`mt-1 inline-flex rounded-full border px-2 py-0.5 text-[10px] font-medium ${
          isCustom
            ? "border-brand-400/30 bg-brand-500/10 text-brand-300"
            : "border-line bg-white/[0.03] text-ink-faint"
        }`}
      >
        {isCustom ? "Custom" : "Preset"}
      </span>

      <p className="mt-2 line-clamp-2 text-xs text-ink-soft">{character.vibe}</p>

      <div className="mt-2 flex items-center gap-1.5 text-[11px]">
        {training ? (
          <>
            <span className="h-1.5 w-1.5 animate-pulse-dot rounded-full bg-amber-400" />
            <span className="text-amber-300">Training…</span>
          </>
        ) : failed ? (
          <>
            <span className="h-1.5 w-1.5 rounded-full bg-red-400" />
            <span className="text-red-400">Failed</span>
          </>
        ) : (
          <>
            <span className="h-1.5 w-1.5 rounded-full bg-accent-lime" />
            <span className="text-ink-faint">Ready</span>
          </>
        )}
      </div>
    </div>
  );
}

// Guided webcam face scan: live selfie preview + staged capture prompts.
// Each shot is grabbed off a canvas as a data URL and handed to the parent.
const SCAN_STEPS = [
  "Look straight at the camera",
  "Turn slightly to your left",
  "Turn slightly to your right",
  "Tilt your chin up a touch",
  "Big natural smile",
];

function CameraCapture({
  onCapture,
  onDone,
  captured,
}: {
  onCapture: (dataUrl: string) => void;
  onDone: () => void;
  captured: number;
}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [ready, setReady] = useState(false);
  const [camError, setCamError] = useState<string | null>(null);
  const [flash, setFlash] = useState(false);
  const step = Math.min(captured, SCAN_STEPS.length - 1);

  useEffect(() => {
    let cancelled = false;
    async function start() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user", width: { ideal: 720 }, height: { ideal: 720 } },
          audio: false,
        });
        if (cancelled) {
          stream.getTracks().forEach((t) => t.stop());
          return;
        }
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          await videoRef.current.play().catch(() => {});
        }
        setReady(true);
      } catch {
        setCamError(
          "Couldn't access the camera. Allow camera permission in your browser, or add photos from files instead."
        );
      }
    }
    start();
    return () => {
      cancelled = true;
      streamRef.current?.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    };
  }, []);

  function snap() {
    const video = videoRef.current;
    if (!video || !ready) return;
    const side = Math.min(video.videoWidth, video.videoHeight) || 640;
    const canvas = document.createElement("canvas");
    canvas.width = side;
    canvas.height = side;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    // center-crop to a square and mirror so it matches the preview
    const sx = (video.videoWidth - side) / 2;
    const sy = (video.videoHeight - side) / 2;
    ctx.translate(side, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(video, sx, sy, side, side, 0, 0, side, side);
    onCapture(canvas.toDataURL("image/jpeg", 0.85));
    setFlash(true);
    window.setTimeout(() => setFlash(false), 180);
  }

  if (camError) {
    return (
      <p className="rounded-lg border border-amber-400/30 bg-amber-400/10 px-3 py-2 text-xs text-amber-200">
        {camError}
      </p>
    );
  }

  return (
    <div className="overflow-hidden rounded-xl border border-line">
      <div className="relative mx-auto aspect-square w-full max-w-[320px] bg-black">
        <video
          ref={videoRef}
          playsInline
          muted
          className="h-full w-full object-cover"
          style={{ transform: "scaleX(-1)" }}
        />
        {/* face guide ring */}
        <div className="pointer-events-none absolute inset-0 grid place-items-center">
          <div className="h-[68%] w-[54%] rounded-[50%] border-2 border-dashed border-white/50" />
        </div>
        {flash && <div className="absolute inset-0 bg-white/70" />}
        {!ready && (
          <div className="absolute inset-0 grid place-items-center text-xs text-ink-faint">
            Starting camera…
          </div>
        )}
        <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 to-transparent px-3 pb-3 pt-8 text-center">
          <p className="text-sm font-semibold text-white">{SCAN_STEPS[step]}</p>
          <p className="text-[11px] text-white/70">
            {captured}/{SCAN_STEPS.length} captures
          </p>
        </div>
      </div>
      <div className="flex items-center justify-center gap-2 border-t border-line bg-white/[0.02] p-3">
        <button type="button" onClick={snap} disabled={!ready} className="btn-primary h-10 px-5 text-sm">
          {captured === 0 ? "Capture" : "Capture next"}
        </button>
        {captured >= 3 && (
          <button type="button" onClick={onDone} className="btn-ghost h-10 px-4 text-sm">
            <IconCheck width={15} height={15} /> Done
          </button>
        )}
      </div>
    </div>
  );
}

const ANALYSIS_STEPS = [
  "Detecting face in captures…",
  "Mapping facial landmarks…",
  "Analyzing skin tone & lighting…",
  "Building your identity model…",
  "Generating your AI avatar…",
];

function CreateCharacterModal({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: (msg: string) => void;
}) {
  const addCharacter = useStore((s) => s.addCharacter);
  const [name, setName] = useState("");
  const [vibe, setVibe] = useState("");
  const [images, setImages] = useState<string[]>([]);
  const [training, setTraining] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [demoNote, setDemoNote] = useState(false);
  const [source, setSource] = useState<"camera" | "upload">("camera");
  const [analysisStep, setAnalysisStep] = useState(-1);

  function handleFiles(fileList: FileList | null) {
    if (!fileList) return;
    setError(null);
    const files = Array.from(fileList).filter((f) => f.type.startsWith("image/"));
    const room = MAX_PHOTOS - images.length;
    files.slice(0, room).forEach((file) => {
      const reader = new FileReader();
      reader.onload = () => {
        if (typeof reader.result === "string") {
          setImages((prev) =>
            prev.length >= MAX_PHOTOS ? prev : [...prev, reader.result as string]
          );
        }
      };
      reader.readAsDataURL(file);
    });
  }

  function removeImage(idx: number) {
    setImages((prev) => prev.filter((_, i) => i !== idx));
  }

  async function onSubmit() {
    if (training) return;
    if (!name.trim()) {
      setError("Give your character a name.");
      return;
    }
    if (images.length === 0) {
      setError("Capture your face with the camera or add at least one photo.");
      return;
    }
    setError(null);
    setDemoNote(false);
    setTraining(true);

    // Walk the analysis stages while the training/portrait calls run, so the
    // user sees what's happening to their face captures.
    setAnalysisStep(0);
    const ticker = window.setInterval(() => {
      setAnalysisStep((s) => Math.min(s + 1, ANALYSIS_STEPS.length - 1));
    }, 1100);

    try {
      const res = await createCharacter(name.trim(), images);
      if (!res.ok) {
        window.clearInterval(ticker);
        setAnalysisStep(-1);
        setError(res.error || "Couldn't train that character. Please try again.");
        setTraining(false);
        return;
      }

      // Generate a photoreal AI avatar from the trained identity. Falls back
      // to the first face capture when no Higgsfield credentials are set.
      setAnalysisStep(ANALYSIS_STEPS.length - 1);
      let avatarUrl = images[0];
      try {
        const portrait = await generatePortraitClient({
          name: name.trim(),
          vibe: vibe.trim() || "confident, friendly creator",
          soulId: res.soulId,
        });
        if (portrait.url) avatarUrl = portrait.url;
      } catch {
        /* keep the captured photo */
      }

      window.clearInterval(ticker);
      addCharacter({
        id: `char-${Math.random().toString(36).slice(2, 10)}`,
        name: name.trim(),
        kind: "custom",
        vibe: vibe.trim() || "custom AI creator",
        imageUrl: avatarUrl,
        soulId: res.soulId,
        heygenTalkingPhotoId: res.talkingPhotoId,
        status: "ready",
        engine: res.engine,
        createdAt: Date.now(),
      });
      if (res.engine === "heygen") {
        onCreated(`${name.trim()} is ready — a real speaking avatar of your face.`);
        onClose();
        return;
      }
      if (res.engine === "demo") {
        // Surface the demo note briefly, then close.
        setDemoNote(true);
        setTraining(false);
        setAnalysisStep(-1);
        window.setTimeout(() => {
          onCreated(`${name.trim()} is ready to cast.`);
          onClose();
        }, 2600);
        return;
      }
      onCreated(`${name.trim()} is trained and ready to cast.`);
      onClose();
    } catch {
      window.clearInterval(ticker);
      setAnalysisStep(-1);
      setError("Something went wrong while training. Please try again.");
      setTraining(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 grid place-items-center bg-black/60 p-4 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="card w-full max-w-lg overflow-hidden p-0"
        onClick={(e) => e.stopPropagation()}
      >
        {/* modal header */}
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <h2 className="flex items-center gap-2 font-semibold">
            <IconSpark width={16} height={16} className="text-brand-300" />
            Create your AI twin
          </h2>
          <button
            onClick={onClose}
            aria-label="Close"
            className="rounded-lg p-1 text-ink-faint hover:text-ink"
          >
            <IconX width={18} height={18} />
          </button>
        </div>

        <div className="max-h-[70vh] space-y-4 overflow-y-auto px-5 py-5">
          <div>
            <label className="label">Name</label>
            <input
              className="input"
              placeholder="e.g. River"
              value={name}
              onChange={(e) => setName(e.target.value)}
              disabled={training}
            />
          </div>

          {/* face capture */}
          <div>
            <div className="mb-1.5 flex items-center justify-between">
              <label className="label !mb-0">Your face</label>
              <div className="flex rounded-lg border border-line p-0.5">
                {(
                  [
                    { key: "camera", label: "Camera", Icon: IconVideo },
                    { key: "upload", label: "Upload", Icon: IconPlus },
                  ] as const
                ).map(({ key, label, Icon }) => (
                  <button
                    key={key}
                    type="button"
                    disabled={training}
                    onClick={() => setSource(key)}
                    className={`inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs transition ${
                      source === key
                        ? "bg-brand-500/20 text-brand-200"
                        : "text-ink-faint hover:text-ink"
                    }`}
                  >
                    <Icon width={13} height={13} />
                    {label}
                  </button>
                ))}
              </div>
            </div>

            {source === "camera" && !training && images.length < MAX_PHOTOS && (
              <CameraCapture
                captured={images.length}
                onCapture={(dataUrl) =>
                  setImages((prev) =>
                    prev.length >= MAX_PHOTOS ? prev : [...prev, dataUrl]
                  )
                }
                onDone={() => setSource("upload")}
              />
            )}

            {source === "upload" && (
              <label
                className={`flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border border-dashed border-line-strong bg-white/[0.02] px-4 py-6 text-center transition hover:border-brand-500/50 ${
                  training ? "pointer-events-none opacity-60" : ""
                }`}
              >
                <span className="grid h-10 w-10 place-items-center rounded-xl bg-brand-500/15 text-brand-300">
                  <IconPlus width={18} height={18} />
                </span>
                <span className="text-sm text-ink-soft">
                  Tap to add photos ({images.length}/{MAX_PHOTOS})
                </span>
                <span className="text-[11px] text-ink-faint">
                  Upload 5–20 clear photos of one face, varied angles &amp; lighting.
                </span>
                <input
                  type="file"
                  accept="image/*"
                  multiple
                  className="hidden"
                  disabled={training}
                  onChange={(e) => {
                    handleFiles(e.target.files);
                    e.target.value = "";
                  }}
                />
              </label>
            )}

            {images.length > 0 && (
              <div className="mt-3 grid grid-cols-4 gap-2 sm:grid-cols-5">
                {images.map((src, i) => (
                  <div
                    key={i}
                    className="group/thumb relative aspect-square overflow-hidden rounded-lg border border-line"
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={src}
                      alt={`Face ${i + 1}`}
                      className="h-full w-full object-cover"
                    />
                    {!training && (
                      <button
                        onClick={() => removeImage(i)}
                        aria-label={`Remove photo ${i + 1}`}
                        className="absolute right-1 top-1 grid h-5 w-5 place-items-center rounded-full bg-black/60 text-white opacity-0 transition group-hover/thumb:opacity-100"
                      >
                        <IconX width={11} height={11} />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

          <div>
            <label className="label">Vibe</label>
            <input
              className="input"
              placeholder="e.g. warm, fast-talking, girl-next-door energy"
              value={vibe}
              onChange={(e) => setVibe(e.target.value)}
              disabled={training}
            />
            <p className="mt-1 text-[11px] text-ink-faint">
              How should they come across on camera? This guides their scripts.
            </p>
          </div>

          {training && analysisStep >= 0 && (
            <div className="rounded-xl border border-line bg-white/[0.02] p-3.5">
              <div className="mb-2 flex items-center gap-2 text-xs font-semibold">
                <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-line-strong border-t-brand-400" />
                Analyzing your face
              </div>
              <div className="space-y-1.5">
                {ANALYSIS_STEPS.map((s, i) => (
                  <p
                    key={s}
                    className={`flex items-center gap-2 text-xs ${
                      i < analysisStep
                        ? "text-ink-faint line-through"
                        : i === analysisStep
                          ? "text-ink"
                          : "text-ink-faint/60"
                    }`}
                  >
                    {i < analysisStep ? (
                      <IconCheck width={12} height={12} className="text-accent-lime" />
                    ) : (
                      <span
                        className={`h-1.5 w-1.5 rounded-full ${
                          i === analysisStep ? "animate-pulse-dot bg-brand-400" : "bg-white/15"
                        }`}
                      />
                    )}
                    {s}
                  </p>
                ))}
              </div>
            </div>
          )}

          {error && (
            <p className="rounded-lg border border-red-400/30 bg-red-400/10 px-3 py-2 text-xs text-red-300">
              {error}
            </p>
          )}

          {demoNote && (
            <p className="rounded-lg border border-amber-400/30 bg-amber-400/10 px-3 py-2 text-xs text-amber-200">
              Created in demo mode — add Higgsfield credentials (paid plan) to train
              a real face-faithful Soul.
            </p>
          )}
        </div>

        {/* modal footer */}
        <div className="flex items-center justify-end gap-2 border-t border-line px-5 py-4">
          <button onClick={onClose} className="btn-ghost" disabled={training}>
            Cancel
          </button>
          <button
            onClick={onSubmit}
            disabled={training}
            className="btn-primary"
          >
            {training ? (
              <>
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" />
                Training your Soul…
              </>
            ) : (
              <>
                <IconSpark width={16} height={16} /> Train character
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}
