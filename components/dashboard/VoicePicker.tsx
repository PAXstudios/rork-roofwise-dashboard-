"use client";

import { useEffect, useRef, useState } from "react";
import { listHeyGenVoices, type HeyGenVoiceItem } from "@/lib/studioClient";
import { IconSpark } from "@/components/Icons";

// Voice picker backed by HeyGen's full voice catalog (including any cloned
// voices on the account). Filter by language + search, preview audio, select.
export function VoicePicker({
  value,
  onChange,
  defaultGender,
}: {
  value?: string;
  onChange: (voiceId: string, name: string) => void;
  defaultGender?: string | null;
}) {
  const [state, setState] = useState<"loading" | "off" | "error" | "ready">("loading");
  const [languages, setLanguages] = useState<string[]>([]);
  const [language, setLanguage] = useState("English");
  const [q, setQ] = useState("");
  const [voices, setVoices] = useState<HeyGenVoiceItem[]>([]);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setState("loading");
    listHeyGenVoices({ language, q })
      .then((res) => {
        if (cancelled) return;
        if (!res.configured) return setState("off");
        if (!res.ok) return setState("error");
        setLanguages(res.languages || []);
        // Prefer default-gender voices at the top.
        const v = [...res.voices];
        if (defaultGender) {
          v.sort((a, b) => {
            const am = (a.gender || "").toLowerCase() === defaultGender.toLowerCase() ? 0 : 1;
            const bm = (b.gender || "").toLowerCase() === defaultGender.toLowerCase() ? 0 : 1;
            return am - bm;
          });
        }
        setVoices(v);
        setState("ready");
      })
      .catch(() => !cancelled && setState("error"));
    return () => {
      cancelled = true;
    };
  }, [language, q, defaultGender]);

  function preview(v: HeyGenVoiceItem) {
    if (!v.preview) return;
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current = null;
    }
    if (playing === v.id) {
      setPlaying(null);
      return;
    }
    const audio = new Audio(v.preview);
    audioRef.current = audio;
    audio.onended = () => setPlaying(null);
    audio.play().catch(() => {});
    setPlaying(v.id);
  }

  if (state === "off") {
    return (
      <p className="rounded-lg border border-line bg-white/[0.02] px-3 py-2 text-xs text-ink-faint">
        Connect HeyGen (HEYGEN_API_KEY) to choose from 2,000+ voices — including your cloned voice.
      </p>
    );
  }
  if (state === "error") {
    return (
      <p className="rounded-lg border border-amber-400/30 bg-amber-400/10 px-3 py-2 text-xs text-amber-200">
        Couldn&apos;t load voices — check your HeyGen key.
      </p>
    );
  }

  return (
    <div className="rounded-xl border border-line bg-white/[0.02] p-2.5">
      <div className="mb-2 flex gap-2">
        <select
          value={language}
          onChange={(e) => setLanguage(e.target.value)}
          className="input !py-1.5 !text-xs"
          style={{ maxWidth: 150 }}
        >
          {languages.map((l) => (
            <option key={l} value={l}>{l}</option>
          ))}
        </select>
        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search voices…"
          className="input !py-1.5 !text-xs"
        />
      </div>

      <div className="max-h-52 space-y-1 overflow-y-auto pr-1">
        {state === "loading" ? (
          <div className="py-6 text-center text-xs text-ink-faint">Loading voices…</div>
        ) : voices.length === 0 ? (
          <div className="py-6 text-center text-xs text-ink-faint">No voices match.</div>
        ) : (
          voices.map((v) => {
            const selected = v.id === value;
            return (
              <div
                key={v.id}
                className={`flex items-center gap-2 rounded-lg border px-2.5 py-1.5 text-sm transition ${
                  selected
                    ? "border-brand-500/50 bg-brand-500/10"
                    : "border-transparent hover:bg-white/[0.04]"
                }`}
              >
                {v.preview && (
                  <button
                    type="button"
                    onClick={() => preview(v)}
                    title="Preview voice"
                    className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-white/[0.06] text-ink-soft hover:text-ink"
                  >
                    {playing === v.id ? (
                      <span className="h-2 w-2 rounded-sm bg-brand-300" />
                    ) : (
                      <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>
                    )}
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => onChange(v.id, v.name)}
                  className="min-w-0 flex-1 text-left"
                >
                  <span className="flex items-center gap-1.5">
                    <span className="truncate font-medium">{v.name}</span>
                    {v.emotion && <IconSpark width={10} height={10} className="shrink-0 text-brand-300" />}
                  </span>
                  <span className="block text-[10px] capitalize text-ink-faint">
                    {v.gender || "neutral"} · {v.language}
                  </span>
                </button>
                {selected && <span className="text-[10px] font-semibold text-brand-300">Selected</span>}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
