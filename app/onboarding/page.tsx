"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useStore } from "@/lib/store";
import { useHydrated } from "@/lib/hooks";
import { Logo } from "@/components/Logo";
import { PLATFORM_META, PlatformBadge } from "@/components/platform";
import {
  IconArrow,
  IconCheck,
  IconSpark,
  IconTarget,
  IconMic,
  IconPlus,
  IconX,
} from "@/components/Icons";
import type { Platform } from "@/lib/types";

const TONE_POLES: { key: keyof StoreTone; low: string; high: string; label: string }[] = [
  { key: "formal", low: "Casual", high: "Formal", label: "Formality" },
  { key: "playful", low: "Serious", high: "Playful", label: "Energy" },
  { key: "bold", low: "Measured", high: "Bold", label: "Stance" },
  { key: "technical", low: "Simple", high: "Expert", label: "Depth" },
];
type StoreTone = { formal: number; playful: number; bold: number; technical: number };

const GOAL_OPTIONS = [
  "Grow my following",
  "Land clients / leads",
  "Build authority",
  "Launch a product",
  "Post more consistently",
  "Improve engagement",
];

const steps = ["Welcome", "Connect", "About you", "Your voice", "Writing samples", "Goals"];

export default function Onboarding() {
  const router = useRouter();
  const hydrated = useHydrated();
  const user = useStore((s) => s.user);
  const voice = useStore((s) => s.voice);
  const connections = useStore((s) => s.connections);
  const updateVoice = useStore((s) => s.updateVoice);
  const trainVoice = useStore((s) => s.trainVoice);
  const toggleConnection = useStore((s) => s.toggleConnection);
  const completeOnboarding = useStore((s) => s.completeOnboarding);

  const [step, setStep] = useState(0);
  const [sampleInput, setSampleInput] = useState("");
  const [training, setTraining] = useState(false);

  useEffect(() => {
    if (hydrated && !user) router.replace("/signup");
  }, [hydrated, user, router]);

  const progress = useMemo(() => ((step + 1) / steps.length) * 100, [step]);

  if (!hydrated || !user) {
    return (
      <div className="grid min-h-screen place-items-center text-ink-faint">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-line-strong border-t-brand-400" />
      </div>
    );
  }

  function finishTraining() {
    setTraining(true);
    setTimeout(() => {
      trainVoice();
      completeOnboarding();
      router.push("/dashboard");
    }, 1600);
  }

  const next = () => setStep((s) => Math.min(s + 1, steps.length - 1));
  const back = () => setStep((s) => Math.max(s - 1, 0));

  return (
    <div className="relative min-h-screen overflow-hidden">
      <div className="pointer-events-none absolute inset-0 bg-radial-fade" />
      <header className="relative flex items-center justify-between px-5 py-5 sm:px-8">
        <Logo />
        <button onClick={() => router.push("/dashboard")} className="btn-subtle text-xs">
          Skip for now
        </button>
      </header>

      {/* progress */}
      <div className="relative mx-auto mt-2 w-full max-w-2xl px-5">
        <div className="mb-2 flex items-center justify-between text-xs text-ink-faint">
          <span>
            Step {step + 1} of {steps.length}
          </span>
          <span>{steps[step]}</span>
        </div>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-white/[0.06]">
          <div
            className="h-full rounded-full bg-brand-gradient transition-all duration-500"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      <main className="relative mx-auto w-full max-w-2xl px-5 py-8 sm:py-10">
        <div key={step} className="animate-fade-up">
          {/* STEP 0 — Welcome */}
          {step === 0 && (
            <div className="text-center">
              <div className="mx-auto mb-5 grid h-16 w-16 place-items-center rounded-2xl bg-brand-gradient shadow-glow">
                <IconSpark className="text-white" width={30} height={30} />
              </div>
              <h1 className="text-3xl font-semibold tracking-tight">
                Welcome to cre8tor, {user.name.split(" ")[0]}
              </h1>
              <p className="mx-auto mt-3 max-w-md text-ink-soft">
                In the next 2 minutes we'll connect your accounts and train cre8tor
                on your voice — so everything it writes sounds unmistakably like you.
              </p>
              <div className="mt-8 grid gap-3 text-left sm:grid-cols-3">
                {[
                  { Icon: IconMic, t: "Learn your voice", d: "From your samples & tone" },
                  { Icon: IconTarget, t: "Understand your goals", d: "So advice fits you" },
                  { Icon: IconSpark, t: "Start creating", d: "Posts in seconds" },
                ].map(({ Icon, t, d }) => (
                  <div key={t} className="card p-4">
                    <Icon className="text-brand-300" width={22} height={22} />
                    <div className="mt-2 text-sm font-semibold">{t}</div>
                    <div className="text-xs text-ink-faint">{d}</div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* STEP 1 — Connect */}
          {step === 1 && (
            <div>
              <StepHead
                title="Connect your accounts"
                sub="cre8tor uses these to analyze what's working and tailor your content. Connect at least one — you can add more later."
              />
              <div className="grid gap-3">
                {connections.map((c) => {
                  const meta = PLATFORM_META[c.platform];
                  return (
                    <button
                      key={c.platform}
                      onClick={() => toggleConnection(c.platform)}
                      className={`flex items-center justify-between rounded-2xl border p-4 text-left transition ${
                        c.connected
                          ? "border-brand-500/50 bg-brand-500/10"
                          : "border-line bg-white/[0.02] hover:bg-white/[0.05]"
                      }`}
                    >
                      <div className="flex items-center gap-3">
                        <PlatformBadge platform={c.platform} />
                        <div>
                          <div className="text-sm font-semibold">{meta.label}</div>
                          <div className="text-xs text-ink-faint">
                            {c.connected ? `Connected · ${c.handle}` : "Not connected"}
                          </div>
                        </div>
                      </div>
                      <span
                        className={`grid h-6 w-6 place-items-center rounded-full border ${
                          c.connected
                            ? "border-brand-400 bg-brand-500 text-white"
                            : "border-line-strong text-transparent"
                        }`}
                      >
                        <IconCheck width={14} height={14} />
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* STEP 2 — About you */}
          {step === 2 && (
            <div>
              <StepHead
                title="Tell us about you"
                sub="A few details so cre8tor writes with context, not clichés."
              />
              <div className="grid gap-4">
                <Field label="What's your niche or topic?">
                  <input
                    className="input"
                    placeholder="e.g. B2B SaaS growth, fitness for busy parents…"
                    value={voice.niche}
                    onChange={(e) => updateVoice({ niche: e.target.value })}
                  />
                </Field>
                <Field label="Who's your audience?">
                  <input
                    className="input"
                    placeholder="e.g. early-stage founders and indie hackers"
                    value={voice.audience}
                    onChange={(e) => updateVoice({ audience: e.target.value })}
                  />
                </Field>
                <Field label="Short bio / what you do">
                  <textarea
                    className="input min-h-[96px] resize-y"
                    placeholder="I help… / I'm building… / I write about…"
                    value={voice.bio}
                    onChange={(e) => updateVoice({ bio: e.target.value })}
                  />
                </Field>
              </div>
            </div>
          )}

          {/* STEP 3 — Voice / tone */}
          {step === 3 && (
            <div>
              <StepHead
                title="Dial in your voice"
                sub="Move the sliders until they feel like you. This shapes every draft."
              />
              <div className="grid gap-6">
                {TONE_POLES.map((p) => (
                  <div key={p.key}>
                    <div className="mb-1.5 flex items-center justify-between text-xs">
                      <span className="font-medium text-ink-soft">{p.label}</span>
                      <span className="text-ink-faint">
                        {p.low} · {p.high}
                      </span>
                    </div>
                    <input
                      type="range"
                      min={0}
                      max={100}
                      value={voice.tone[p.key]}
                      onChange={(e) =>
                        updateVoice({ tone: { ...voice.tone, [p.key]: Number(e.target.value) } })
                      }
                      className="w-full accent-brand-500"
                    />
                  </div>
                ))}
                <Field label="Emoji usage">
                  <div className="flex gap-2">
                    {(["none", "light", "heavy"] as const).map((e) => (
                      <button
                        key={e}
                        onClick={() => updateVoice({ emojiUsage: e })}
                        className={`flex-1 rounded-xl border px-3 py-2.5 text-sm capitalize transition ${
                          voice.emojiUsage === e
                            ? "border-brand-500/60 bg-brand-500/15 text-ink"
                            : "border-line text-ink-soft hover:bg-white/[0.04]"
                        }`}
                      >
                        {e}
                      </button>
                    ))}
                  </div>
                </Field>
              </div>
            </div>
          )}

          {/* STEP 4 — Writing samples */}
          {step === 4 && (
            <div>
              <StepHead
                title="Paste a few of your posts"
                sub="This is the secret sauce. 2-4 posts you've written give cre8tor your real rhythm and personality."
              />
              <div className="grid gap-3">
                <textarea
                  className="input min-h-[120px] resize-y"
                  placeholder="Paste one of your best posts here…"
                  value={sampleInput}
                  onChange={(e) => setSampleInput(e.target.value)}
                />
                <button
                  onClick={() => {
                    const v = sampleInput.trim();
                    if (v.length < 10) return;
                    updateVoice({ samples: [...voice.samples, v] });
                    setSampleInput("");
                  }}
                  className="btn-ghost w-full"
                >
                  <IconPlus width={16} height={16} /> Add sample
                </button>

                {voice.samples.length > 0 && (
                  <div className="mt-1 grid gap-2">
                    {voice.samples.map((s, i) => (
                      <div
                        key={i}
                        className="group relative rounded-xl border border-line bg-white/[0.02] p-3 pr-9 text-sm text-ink-soft"
                      >
                        <p className="line-clamp-3">{s}</p>
                        <button
                          onClick={() =>
                            updateVoice({ samples: voice.samples.filter((_, j) => j !== i) })
                          }
                          className="absolute right-2 top-2 rounded-md p-1 text-ink-faint hover:bg-white/10 hover:text-ink"
                        >
                          <IconX width={14} height={14} />
                        </button>
                      </div>
                    ))}
                  </div>
                )}
                <p className="text-xs text-ink-faint">
                  {voice.samples.length === 0
                    ? "Tip: add at least 1 sample for the best results."
                    : `${voice.samples.length} sample${voice.samples.length > 1 ? "s" : ""} added — nice.`}
                </p>
              </div>
            </div>
          )}

          {/* STEP 5 — Goals */}
          {step === 5 && (
            <div>
              <StepHead
                title="What are you here to do?"
                sub="Pick what matters most. cre8tor will bias its advice toward your goals."
              />
              <div className="flex flex-wrap gap-2.5">
                {GOAL_OPTIONS.map((g) => {
                  const active = voice.goals.includes(g);
                  return (
                    <button
                      key={g}
                      onClick={() =>
                        updateVoice({
                          goals: active
                            ? voice.goals.filter((x) => x !== g)
                            : [...voice.goals, g],
                        })
                      }
                      className={`rounded-full border px-4 py-2 text-sm transition ${
                        active
                          ? "border-brand-500/60 bg-brand-500/15 text-ink"
                          : "border-line text-ink-soft hover:bg-white/[0.04]"
                      }`}
                    >
                      {g}
                    </button>
                  );
                })}
              </div>

              {training && (
                <div className="mt-8 flex flex-col items-center gap-3 text-center">
                  <div className="h-10 w-10 animate-spin rounded-full border-2 border-line-strong border-t-brand-400" />
                  <p className="text-sm text-ink-soft">Training cre8tor on your voice…</p>
                </div>
              )}
            </div>
          )}
        </div>

        {/* nav */}
        <div className="mt-10 flex items-center justify-between">
          <button
            onClick={back}
            disabled={step === 0 || training}
            className="btn-subtle disabled:opacity-30"
          >
            Back
          </button>
          {step < steps.length - 1 ? (
            <button onClick={next} className="btn-primary">
              Continue <IconArrow width={16} height={16} />
            </button>
          ) : (
            <button onClick={finishTraining} disabled={training} className="btn-primary">
              {training ? "Training…" : "Finish & train voice"}
              {!training && <IconSpark width={16} height={16} />}
            </button>
          )}
        </div>
      </main>
    </div>
  );
}

function StepHead({ title, sub }: { title: string; sub: string }) {
  return (
    <div className="mb-6">
      <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-1.5 text-sm text-ink-soft">{sub}</p>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="label">{label}</label>
      {children}
    </div>
  );
}
