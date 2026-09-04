"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useStore } from "@/lib/store";
import type { VoiceProfile } from "@/lib/types";
import { useHydrated, formatDate } from "@/lib/hooks";
import {
  IconSpark,
  IconCheck,
  IconPlus,
  IconX,
  IconTrash,
} from "@/components/Icons";

type Tab = "voice" | "account" | "billing" | "notifications";

const TABS: { key: Tab; label: string }[] = [
  { key: "voice", label: "Voice profile" },
  { key: "account", label: "Account" },
  { key: "billing", label: "Billing" },
  { key: "notifications", label: "Notifications" },
];

export default function SettingsPage() {
  const hydrated = useHydrated();
  const [tab, setTab] = useState<Tab>("voice");

  if (!hydrated) {
    return (
      <div className="space-y-6">
        <div className="h-10 w-40 shimmer rounded-xl bg-white/[0.04]" />
        <div className="h-96 shimmer rounded-2xl border border-line bg-white/[0.02]" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Settings
        </h1>
        <p className="mt-1 text-sm text-ink-soft">
          Tune your voice, manage your account, and control cre8tor.
        </p>
      </header>

      <div className="grid gap-6 lg:grid-cols-[220px_1fr]">
        <nav className="flex gap-2 overflow-x-auto lg:flex-col lg:overflow-visible">
          {TABS.map((t) => {
            const active = tab === t.key;
            return (
              <button
                key={t.key}
                onClick={() => setTab(t.key)}
                className={`shrink-0 rounded-xl border px-4 py-2.5 text-left text-sm font-medium transition lg:w-full ${
                  active
                    ? "border-brand-400/40 bg-brand-500/10 text-ink"
                    : "border-transparent text-ink-soft hover:bg-white/[0.04] hover:text-ink"
                }`}
              >
                {t.label}
              </button>
            );
          })}
        </nav>

        <div>
          {tab === "voice" && <VoiceTab />}
          {tab === "account" && <AccountTab />}
          {tab === "billing" && <BillingTab />}
          {tab === "notifications" && <NotificationsTab />}
        </div>
      </div>
    </div>
  );
}

/* ── Voice ─────────────────────────────────────────────── */

const TONE_POLES: {
  key: keyof VoiceProfile["tone"];
  low: string;
  high: string;
}[] = [
  { key: "formal", low: "Casual", high: "Formal" },
  { key: "playful", low: "Serious", high: "Playful" },
  { key: "bold", low: "Measured", high: "Bold" },
  { key: "technical", low: "Simple", high: "Technical" },
];

const EMOJI_OPTS: VoiceProfile["emojiUsage"][] = ["none", "light", "heavy"];

function VoiceTab() {
  const voice = useStore((s) => s.voice);
  const updateVoice = useStore((s) => s.updateVoice);
  const trainVoice = useStore((s) => s.trainVoice);

  const [favorite, setFavorite] = useState(voice.favoriteWords.join(", "));
  const [avoid, setAvoid] = useState(voice.avoidWords.join(", "));
  const [goals, setGoals] = useState(voice.goals.join(", "));
  const [sample, setSample] = useState("");

  const toList = (v: string) =>
    v.split(",").map((s) => s.trim()).filter(Boolean);

  function addSample() {
    const text = sample.trim();
    if (!text) return;
    updateVoice({ samples: [...voice.samples, text] });
    setSample("");
  }

  return (
    <div className="space-y-6">
      <div className="card flex flex-wrap items-center justify-between gap-3 p-4">
        <div className="flex items-center gap-3">
          <span
            className={`grid h-10 w-10 place-items-center rounded-xl ${
              voice.trained
                ? "bg-emerald-400/10 text-emerald-300"
                : "bg-white/[0.04] text-ink-faint"
            }`}
          >
            {voice.trained ? (
              <IconCheck width={18} height={18} />
            ) : (
              <IconSpark width={18} height={18} />
            )}
          </span>
          <div>
            <p className="font-semibold">
              {voice.trained ? "Voice trained" : "Voice not trained yet"}
            </p>
            <p className="text-xs text-ink-faint">
              {voice.samples.length} sample
              {voice.samples.length === 1 ? "" : "s"} on file
            </p>
          </div>
        </div>
        <button className="btn-primary" onClick={() => trainVoice()}>
          <IconSpark width={16} height={16} />
          {voice.trained ? "Re-train voice" : "Train voice"}
        </button>
      </div>

      <Section title="Who you are">
        <div>
          <label className="label">Bio</label>
          <textarea
            className="input min-h-[100px] resize-y"
            value={voice.bio}
            onChange={(e) => updateVoice({ bio: e.target.value })}
            placeholder="A one-paragraph description of you and what you write about."
          />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="label">Niche</label>
            <input
              className="input"
              value={voice.niche}
              onChange={(e) => updateVoice({ niche: e.target.value })}
              placeholder="e.g. Creator growth"
            />
          </div>
          <div>
            <label className="label">Audience</label>
            <input
              className="input"
              value={voice.audience}
              onChange={(e) => updateVoice({ audience: e.target.value })}
              placeholder="e.g. Solo founders and creators"
            />
          </div>
        </div>
      </Section>

      <Section title="Tone">
        <div className="grid gap-5 sm:grid-cols-2">
          {TONE_POLES.map(({ key, low, high }) => (
            <div key={key}>
              <div className="mb-1 flex justify-between text-xs text-ink-soft">
                <span>{low}</span>
                <span className="font-semibold text-ink">{voice.tone[key]}</span>
                <span>{high}</span>
              </div>
              <input
                type="range"
                min={0}
                max={100}
                value={voice.tone[key]}
                onChange={(e) =>
                  updateVoice({
                    tone: { ...voice.tone, [key]: Number(e.target.value) },
                  })
                }
                className="w-full accent-brand-500"
              />
            </div>
          ))}
        </div>

        <div>
          <label className="label">Emoji usage</label>
          <div className="inline-flex rounded-xl border border-line-strong bg-white/[0.02] p-1">
            {EMOJI_OPTS.map((opt) => {
              const active = voice.emojiUsage === opt;
              return (
                <button
                  key={opt}
                  onClick={() => updateVoice({ emojiUsage: opt })}
                  className={`rounded-lg px-4 py-1.5 text-sm font-medium capitalize transition ${
                    active
                      ? "bg-brand-gradient text-white"
                      : "text-ink-soft hover:text-ink"
                  }`}
                >
                  {opt}
                </button>
              );
            })}
          </div>
        </div>
      </Section>

      <Section title="Words & goals">
        <div>
          <label className="label">Favorite words</label>
          <input
            className="input"
            value={favorite}
            onChange={(e) => {
              setFavorite(e.target.value);
              updateVoice({ favoriteWords: toList(e.target.value) });
            }}
            placeholder="ship, momentum, promise"
          />
          <p className="mt-1 text-xs text-ink-faint">Comma separated.</p>
        </div>
        <div>
          <label className="label">Avoid words</label>
          <input
            className="input"
            value={avoid}
            onChange={(e) => {
              setAvoid(e.target.value);
              updateVoice({ avoidWords: toList(e.target.value) });
            }}
            placeholder="synergy, leverage, disrupt"
          />
          <p className="mt-1 text-xs text-ink-faint">Comma separated.</p>
        </div>
        <div>
          <label className="label">Goals</label>
          <input
            className="input"
            value={goals}
            onChange={(e) => {
              setGoals(e.target.value);
              updateVoice({ goals: toList(e.target.value) });
            }}
            placeholder="Grow to 100k, launch a course"
          />
          <p className="mt-1 text-xs text-ink-faint">Comma separated.</p>
        </div>
      </Section>

      <Section title="Writing samples">
        <p className="-mt-2 text-xs text-ink-faint">
          Paste posts that sound like you. These are the raw material cre8tor
          learns from.
        </p>
        <textarea
          className="input min-h-[110px] resize-y"
          value={sample}
          onChange={(e) => setSample(e.target.value)}
          placeholder="Paste a post you're proud of…"
        />
        <div>
          <button
            className="btn-ghost"
            onClick={addSample}
            disabled={!sample.trim()}
          >
            <IconPlus width={16} height={16} />
            Add sample
          </button>
        </div>

        {voice.samples.length > 0 && (
          <div className="space-y-2">
            {voice.samples.map((s, i) => (
              <div
                key={i}
                className="flex items-start gap-3 rounded-xl border border-line bg-white/[0.02] p-3"
              >
                <p className="min-w-0 flex-1 whitespace-pre-wrap text-sm text-ink-soft">
                  {s}
                </p>
                <button
                  onClick={() =>
                    updateVoice({
                      samples: voice.samples.filter((_, j) => j !== i),
                    })
                  }
                  aria-label="Remove sample"
                  className="grid h-7 w-7 shrink-0 place-items-center rounded-lg text-ink-faint transition hover:text-red-400"
                >
                  <IconX width={15} height={15} />
                </button>
              </div>
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function Section({
  title,
  children,
}: {
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="card space-y-4 p-5">
      <h2 className="font-semibold">{title}</h2>
      {children}
    </section>
  );
}

/* ── Account ───────────────────────────────────────────── */

function AccountTab() {
  const router = useRouter();
  const user = useStore((s) => s.user);
  const logout = useStore((s) => s.logout);
  const resetDemo = useStore((s) => s.resetDemo);

  const planLabel: Record<string, string> = {
    trial: "Starter",
    creator: "Creator",
    pro: "Pro",
  };

  return (
    <div className="space-y-6">
      <section className="card p-5">
        <h2 className="font-semibold">Profile</h2>
        <div className="mt-4 flex items-center gap-4">
          <span
            className="grid h-14 w-14 place-items-center rounded-2xl text-xl font-semibold text-white"
            style={{ background: user?.avatarColor || "#6366f1" }}
          >
            {(user?.name || "?").charAt(0).toUpperCase()}
          </span>
          <div>
            <p className="text-lg font-semibold">{user?.name || "Guest"}</p>
            <p className="text-sm text-ink-soft">{user?.email}</p>
          </div>
        </div>

        <div className="mt-5 grid gap-4 sm:grid-cols-2">
          <div>
            <label className="label">Name</label>
            <input className="input" value={user?.name || ""} readOnly />
            <p className="mt-1 text-xs text-ink-faint">
              Display name is read-only in this demo.
            </p>
          </div>
          <div>
            <label className="label">Email</label>
            <input className="input" value={user?.email || ""} readOnly />
          </div>
        </div>

        <div className="mt-5 grid gap-3 sm:grid-cols-2">
          <InfoRow label="Plan" value={planLabel[user?.plan || "trial"]} />
          <InfoRow
            label="Member since"
            value={user ? formatDate(user.createdAt) : "—"}
          />
        </div>
      </section>

      <section className="card space-y-4 p-5">
        <h2 className="font-semibold">Session</h2>
        <div className="flex flex-wrap gap-3">
          <button
            className="btn-ghost"
            onClick={() => {
              logout();
              router.push("/login");
            }}
          >
            Sign out
          </button>
        </div>
      </section>

      <section className="card space-y-3 border-red-500/20 p-5">
        <h2 className="font-semibold text-red-300">Danger zone</h2>
        <p className="text-sm text-ink-soft">
          Reset drafts, voice profile, and connections back to the cre8tor demo
          seed. This cannot be undone.
        </p>
        <button
          onClick={() => {
            if (
              confirm(
                "Reset all demo data? Your drafts, voice, and connections will be restored to defaults."
              )
            ) {
              resetDemo();
            }
          }}
          className="inline-flex items-center gap-2 rounded-full border border-red-500/40 bg-red-500/10 px-5 py-2.5 text-sm font-semibold text-red-300 transition hover:bg-red-500/20"
        >
          <IconTrash width={16} height={16} />
          Reset demo data
        </button>
      </section>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-line bg-white/[0.02] px-4 py-3">
      <p className="text-xs uppercase tracking-wide text-ink-faint">{label}</p>
      <p className="mt-1 font-medium">{value}</p>
    </div>
  );
}

/* ── Billing ───────────────────────────────────────────── */

const PLANS: {
  key: "trial" | "creator" | "pro";
  name: string;
  price: string;
  blurb: string;
  features: string[];
}[] = [
  {
    key: "trial",
    name: "Starter",
    price: "$0",
    blurb: "Find your voice.",
    features: ["Voice profile", "25 drafts / mo", "1 connected account"],
  },
  {
    key: "creator",
    name: "Creator",
    price: "$49",
    blurb: "Ship consistently.",
    features: ["Unlimited drafts", "3 connected accounts", "Analyze mode", "Calendar"],
  },
  {
    key: "pro",
    name: "Pro",
    price: "$99",
    blurb: "Scale your output.",
    features: ["Everything in Creator", "All platforms", "Advanced analytics", "Priority AI"],
  },
];

function BillingTab() {
  const user = useStore((s) => s.user);
  const current = user?.plan || "trial";
  const [note, setNote] = useState(false);

  return (
    <div className="space-y-6">
      <section className="card p-5">
        <p className="text-xs uppercase tracking-wide text-ink-faint">
          Current plan
        </p>
        <div className="mt-2 flex items-center gap-3">
          <p className="text-2xl font-semibold gradient-text">
            {PLANS.find((p) => p.key === current)?.name}
          </p>
          <span className="chip">Active</span>
        </div>
        <p className="mt-1 text-sm text-ink-soft">
          You&apos;re on the {PLANS.find((p) => p.key === current)?.name} plan.
          Manage or change it below.
        </p>
      </section>

      <div className="grid gap-4 md:grid-cols-3">
        {PLANS.map((plan) => {
          const isCurrent = plan.key === current;
          return (
            <div
              key={plan.key}
              className={`card flex flex-col p-5 ${
                isCurrent ? "border-brand-400/50 shadow-glow" : ""
              }`}
            >
              <div className="flex items-center justify-between">
                <h3 className="font-semibold">{plan.name}</h3>
                {isCurrent && (
                  <span className="rounded-full border border-brand-400/40 bg-brand-500/10 px-2 py-0.5 text-[11px] font-medium text-brand-200">
                    Current
                  </span>
                )}
              </div>
              <p className="mt-2 text-3xl font-semibold">
                {plan.price}
                <span className="text-sm font-normal text-ink-faint">/mo</span>
              </p>
              <p className="mt-1 text-sm text-ink-soft">{plan.blurb}</p>
              <ul className="mt-4 flex-1 space-y-2">
                {plan.features.map((f) => (
                  <li
                    key={f}
                    className="flex items-start gap-2 text-sm text-ink-soft"
                  >
                    <IconCheck
                      width={15}
                      height={15}
                      className="mt-0.5 shrink-0 text-emerald-400"
                    />
                    {f}
                  </li>
                ))}
              </ul>
              <button
                disabled={isCurrent}
                onClick={() => setNote(true)}
                className={`mt-5 ${isCurrent ? "btn-ghost" : "btn-primary"}`}
              >
                {isCurrent ? "Current plan" : "Upgrade"}
              </button>
            </div>
          );
        })}
      </div>

      {note && (
        <p className="rounded-2xl border border-brand-400/30 bg-brand-500/10 px-4 py-3 text-sm text-brand-100">
          Billing is in demo mode — no card is charged. Wire up a payment
          provider to make upgrades live.
        </p>
      )}
    </div>
  );
}

/* ── Notifications ─────────────────────────────────────── */

function NotificationsTab() {
  const [prefs, setPrefs] = useState({
    weekly: true,
    reminders: true,
    features: false,
  });

  const ROWS: { key: keyof typeof prefs; title: string; desc: string }[] = [
    {
      key: "weekly",
      title: "Weekly performance email",
      desc: "A Monday digest of your reach and top posts.",
    },
    {
      key: "reminders",
      title: "Post reminders",
      desc: "Nudges when a scheduled draft is about to go out.",
    },
    {
      key: "features",
      title: "New feature announcements",
      desc: "Occasional updates when cre8tor ships something new.",
    },
  ];

  return (
    <section className="card divide-y divide-line p-2">
      {ROWS.map((row) => {
        const on = prefs[row.key];
        return (
          <div
            key={row.key}
            className="flex items-center justify-between gap-4 px-3 py-4"
          >
            <div>
              <p className="font-medium">{row.title}</p>
              <p className="text-sm text-ink-soft">{row.desc}</p>
            </div>
            <button
              role="switch"
              aria-checked={on}
              aria-label={row.title}
              onClick={() =>
                setPrefs((p) => ({ ...p, [row.key]: !p[row.key] }))
              }
              className={`relative h-6 w-11 shrink-0 rounded-full transition ${
                on ? "bg-brand-gradient" : "bg-white/[0.1]"
              }`}
            >
              <span
                className={`absolute top-0.5 h-5 w-5 rounded-full bg-white transition-all ${
                  on ? "left-[22px]" : "left-0.5"
                }`}
              />
            </button>
          </div>
        );
      })}
    </section>
  );
}
