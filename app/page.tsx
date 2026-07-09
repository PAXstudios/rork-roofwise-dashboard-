import Link from "next/link";
import { Nav } from "@/components/marketing/Nav";
import { Footer } from "@/components/marketing/Footer";
import {
  IconSpark,
  IconPen,
  IconChart,
  IconMic,
  IconLayers,
  IconCalendar,
  IconTarget,
  IconArrow,
  IconCheck,
  IconSend,
  IconLinkedIn,
  IconInstagram,
  IconXSocial,
  IconTikTok,
  IconYouTube,
} from "@/components/Icons";

/* ---------------------------------- data ---------------------------------- */

const features = [
  {
    Icon: IconPen,
    title: "Write in your voice",
    desc: "Drafts that sound like you wrote them at your sharpest — not like a robot borrowed your keyboard.",
  },
  {
    Icon: IconChart,
    title: "Analyze what's working",
    desc: "cre8tor reads your best-performing posts and tells you exactly why they landed, so you can do more of it.",
  },
  {
    Icon: IconMic,
    title: "Interview mode",
    desc: "Out of ideas? It interviews you like a great ghostwriter and turns your answers into finished posts.",
  },
  {
    Icon: IconLayers,
    title: "Content library",
    desc: "Every idea, draft, and published post in one organized home — searchable, taggable, and always ready.",
  },
  {
    Icon: IconCalendar,
    title: "Smart scheduling calendar",
    desc: "A weekly plan built around when your audience actually shows up, so nothing ships into the void.",
  },
  {
    Icon: IconTarget,
    title: "Strategy on demand",
    desc: "Ask for angles, hooks, or a full content plan. Your Head of Content always has the next move ready.",
  },
];

const steps = [
  {
    n: "01",
    title: "Connect your accounts",
    desc: "Link LinkedIn, Instagram, and X in a couple of clicks. cre8tor studies what you've already posted.",
  },
  {
    n: "02",
    title: "Train your voice",
    desc: "Answer a few quick prompts. cre8tor learns your tone, your takes, and the words you'd never use.",
  },
  {
    n: "03",
    title: "Create & grow",
    desc: "Get a plan, write in seconds, schedule, and watch what's working — every week, on repeat.",
  },
];

const testimonials = [
  {
    quote:
      "I used to spend Sundays dreading my content calendar. Now cre8tor hands me a week of posts that already sound like me. I just tweak and ship.",
    name: "Maya Chen",
    handle: "@mayabuilds",
    color: "#6366f1",
  },
  {
    quote:
      "The analysis is the unlock. It told me my carousels were carrying my whole account and to lean in. Followers up 3x in a quarter.",
    name: "Devon Parker",
    handle: "@devongrows",
    color: "#ec4899",
  },
  {
    quote:
      "Interview mode is unfair. It pulls the post out of my head faster than I could've typed the first sentence. Genuinely my favorite tool.",
    name: "Ana Reyes",
    handle: "@anawrites",
    color: "#a855f7",
  },
];

const platforms = [
  { label: "LinkedIn", Icon: IconLinkedIn },
  { label: "Instagram", Icon: IconInstagram },
  { label: "X", Icon: IconXSocial },
  { label: "TikTok", Icon: IconTikTok },
  { label: "YouTube", Icon: IconYouTube },
];

const plans = [
  { name: "Starter", price: "$0", note: "7-day trial" },
  { name: "Creator", price: "$49", note: "/mo", featured: true },
  { name: "Pro", price: "$99", note: "/mo" },
];

/* ------------------------------- small pieces ------------------------------ */

function Avatar({ initials, color }: { initials: string; color: string }) {
  return (
    <span
      className="grid h-9 w-9 shrink-0 place-items-center rounded-full text-xs font-semibold text-white ring-2 ring-bg"
      style={{ background: color }}
    >
      {initials}
    </span>
  );
}

/* --------------------------------- page ----------------------------------- */

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-bg text-ink">
      <Nav />

      <main>
        {/* ================================ HERO ================================ */}
        <section className="relative overflow-hidden bg-radial-fade">
          <div className="container-page relative pb-20 pt-16 sm:pt-24">
            <div className="mx-auto max-w-3xl text-center">
              <span className="chip animate-fade-up">
                <IconSpark width={14} height={14} className="text-brand-300" />
                Your AI Head of Content
              </span>

              <h1 className="mt-6 text-4xl font-semibold leading-[1.08] tracking-tight sm:text-6xl">
                Know exactly what to post.{" "}
                <span className="gradient-text">Sound exactly like you.</span>
              </h1>

              <p className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-ink-soft">
                cre8tor is the AI content partner that decides what to post,
                writes it in your voice, and tells you what's working — so you
                grow across LinkedIn, Instagram, and X without the guesswork.
              </p>

              <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
                <Link href="/signup" className="btn-primary w-full sm:w-auto">
                  Start free
                  <IconArrow width={16} height={16} />
                </Link>
                <Link href="#how" className="btn-ghost w-full sm:w-auto">
                  See how it works
                </Link>
              </div>

              <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
                <div className="flex -space-x-2">
                  <Avatar initials="MC" color="#6366f1" />
                  <Avatar initials="DP" color="#ec4899" />
                  <Avatar initials="AR" color="#a855f7" />
                  <Avatar initials="JL" color="#fb923c" />
                </div>
                <p className="text-sm text-ink-soft">
                  Trusted by{" "}
                  <span className="font-semibold text-ink">12,000+ creators</span>{" "}
                  building in public
                </p>
              </div>
            </div>

            {/* faux product preview */}
            <div className="relative mx-auto mt-16 max-w-3xl">
              <div className="absolute -inset-x-8 -top-8 bottom-0 -z-10 bg-radial-fade" />
              <div className="card overflow-hidden p-0">
                <div className="flex items-center gap-2 border-b border-line px-5 py-3">
                  <span className="h-3 w-3 rounded-full bg-white/10" />
                  <span className="h-3 w-3 rounded-full bg-white/10" />
                  <span className="h-3 w-3 rounded-full bg-white/10" />
                  <span className="ml-3 text-xs text-ink-faint">
                    cre8tor · Head of Content
                  </span>
                </div>

                <div className="space-y-5 p-6">
                  {/* assistant bubble */}
                  <div className="flex items-start gap-3">
                    <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-brand-gradient text-white">
                      <IconSpark width={16} height={16} />
                    </span>
                    <div className="max-w-md rounded-2xl rounded-tl-sm border border-line bg-bg-elevated px-4 py-3 text-sm leading-relaxed text-ink-soft">
                      Your Tuesday LinkedIn posts outperform everything else by
                      2.4x. Want me to draft this week's around the lesson that
                      got 40k views?
                    </div>
                  </div>

                  {/* user bubble */}
                  <div className="flex items-start justify-end gap-3">
                    <div className="max-w-xs rounded-2xl rounded-tr-sm bg-brand-600/20 px-4 py-3 text-sm leading-relaxed text-ink">
                      Yes — punchy hook, keep it personal.
                    </div>
                    <span className="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-white/10 text-xs font-semibold text-ink">
                      You
                    </span>
                  </div>

                  {/* input mock */}
                  <div className="rounded-2xl border border-line-strong bg-white/[0.03] p-3">
                    <p className="px-1 pb-3 pt-1 text-sm text-ink-faint">
                      What are we creating today?
                    </p>
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="chip">
                        <IconPen width={13} height={13} />
                        Write in my voice
                      </span>
                      <span className="chip">
                        <IconChart width={13} height={13} />
                        Analyze my posts
                      </span>
                      <span className="chip">
                        <IconMic width={13} height={13} />
                        Interview me
                      </span>
                      <span className="ml-auto grid h-9 w-9 place-items-center rounded-full bg-brand-gradient text-white">
                        <IconSend width={15} height={15} />
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* ============================= LOGO CLOUD ============================= */}
        <section className="border-y border-line bg-bg-soft/30">
          <div className="container-page py-10">
            <p className="text-center text-xs font-medium uppercase tracking-widest text-ink-faint">
              Grows accounts on
            </p>
            <div className="mt-6 flex flex-wrap items-center justify-center gap-x-10 gap-y-5">
              {platforms.map(({ label, Icon }) => (
                <span
                  key={label}
                  className="flex items-center gap-2 text-ink-faint transition-colors hover:text-ink-soft"
                >
                  <Icon width={22} height={22} />
                  <span className="text-sm font-medium">{label}</span>
                </span>
              ))}
            </div>
          </div>
        </section>

        {/* ============================== FEATURES ============================== */}
        <section id="features" className="scroll-mt-20">
          <div className="container-page py-24">
            <div className="mx-auto max-w-2xl text-center">
              <span className="chip">
                <IconSpark width={14} height={14} className="text-brand-300" />
                Everything a Head of Content does
              </span>
              <h2 className="mt-5 text-3xl font-semibold tracking-tight sm:text-4xl">
                One partner for the whole content loop
              </h2>
              <p className="mt-4 text-lg text-ink-soft">
                From the blank page to the next big idea — cre8tor handles the
                strategy so you can stay in your zone of genius.
              </p>
            </div>

            <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {features.map(({ Icon, title, desc }) => (
                <div
                  key={title}
                  className="card group p-6 transition-colors hover:border-line-strong"
                >
                  <span className="grid h-11 w-11 place-items-center rounded-xl border border-line bg-white/[0.03] text-brand-300 transition-colors group-hover:text-brand-200">
                    <Icon width={20} height={20} />
                  </span>
                  <h3 className="mt-5 text-lg font-semibold text-ink">{title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-soft">
                    {desc}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ============================ HOW IT WORKS ============================ */}
        <section id="how" className="scroll-mt-20 border-y border-line bg-bg-soft/30">
          <div className="container-page py-24">
            <div className="mx-auto max-w-2xl text-center">
              <span className="chip">Get going in minutes</span>
              <h2 className="mt-5 text-3xl font-semibold tracking-tight sm:text-4xl">
                From signup to shipping in three steps
              </h2>
            </div>

            <div className="relative mt-14 grid gap-6 md:grid-cols-3">
              <div
                className="pointer-events-none absolute left-0 right-0 top-9 hidden h-px bg-gradient-to-r from-transparent via-line-strong to-transparent md:block"
                aria-hidden
              />
              {steps.map((s) => (
                <div key={s.n} className="relative">
                  <div className="card h-full p-7">
                    <span className="grid h-14 w-14 place-items-center rounded-2xl bg-brand-gradient text-lg font-semibold text-white shadow-[0_10px_30px_-10px_rgba(99,102,241,0.7)]">
                      {s.n}
                    </span>
                    <h3 className="mt-5 text-lg font-semibold text-ink">
                      {s.title}
                    </h3>
                    <p className="mt-2 text-sm leading-relaxed text-ink-soft">
                      {s.desc}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* ============================ DEEP DIVE ============================== */}
        <section className="container-page space-y-24 py-24">
          {/* row 1 */}
          <div className="grid items-center gap-12 lg:grid-cols-2">
            <div>
              <span className="chip">
                <IconPen width={13} height={13} className="text-brand-300" />
                Your voice, captured
              </span>
              <h2 className="mt-5 text-3xl font-semibold tracking-tight sm:text-4xl">
                Sounds unmistakably like you
              </h2>
              <p className="mt-4 text-lg leading-relaxed text-ink-soft">
                cre8tor learns your tone, your favorite phrases, and the lines
                you'd never cross. Every draft comes back sounding like your best
                writing day — ready to post, not rewrite.
              </p>
              <ul className="mt-6 space-y-3">
                {[
                  "Trained on your real posts, not a generic template",
                  "Dials for formal, playful, bold, and technical",
                  "Keep-and-avoid word lists it never forgets",
                ].map((t) => (
                  <li key={t} className="flex items-start gap-3 text-sm text-ink-soft">
                    <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-brand-500/15 text-brand-300">
                      <IconCheck width={13} height={13} />
                    </span>
                    {t}
                  </li>
                ))}
              </ul>
            </div>

            <div className="card p-6">
              <p className="text-xs font-medium uppercase tracking-wide text-ink-faint">
                Voice profile
              </p>
              <div className="mt-4 space-y-4">
                {[
                  { label: "Playful", value: 72 },
                  { label: "Bold", value: 84 },
                  { label: "Technical", value: 38 },
                ].map((d) => (
                  <div key={d.label}>
                    <div className="mb-1.5 flex justify-between text-sm">
                      <span className="text-ink-soft">{d.label}</span>
                      <span className="text-ink-faint">{d.value}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-white/5">
                      <div
                        className="h-full rounded-full bg-brand-gradient"
                        style={{ width: `${d.value}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
              <div className="mt-5 flex flex-wrap gap-2">
                {["build in public", "no fluff", "real talk"].map((w) => (
                  <span key={w} className="chip">
                    {w}
                  </span>
                ))}
              </div>
            </div>
          </div>

          {/* row 2 */}
          <div className="grid items-center gap-12 lg:grid-cols-2">
            <div className="order-2 lg:order-1 card p-6">
              <div className="flex items-center justify-between">
                <p className="text-xs font-medium uppercase tracking-wide text-ink-faint">
                  Last 30 days
                </p>
                <span className="chip text-brand-200">
                  <IconChart width={13} height={13} />
                  +214%
                </span>
              </div>
              <div className="mt-5 flex h-36 items-end gap-2">
                {[28, 40, 34, 52, 46, 64, 58, 78, 70, 92, 84, 100].map((h, i) => (
                  <div
                    key={i}
                    className="flex-1 rounded-t-md bg-brand-gradient"
                    style={{ height: `${h}%`, opacity: 0.35 + (h / 100) * 0.65 }}
                  />
                ))}
              </div>
              <div className="mt-5 grid grid-cols-3 gap-3 border-t border-line pt-5 text-center">
                {[
                  { k: "Impressions", v: "1.2M" },
                  { k: "New followers", v: "8.4K" },
                  { k: "Best day", v: "Tue" },
                ].map((m) => (
                  <div key={m.k}>
                    <p className="text-lg font-semibold text-ink">{m.v}</p>
                    <p className="text-xs text-ink-faint">{m.k}</p>
                  </div>
                ))}
              </div>
            </div>

            <div className="order-1 lg:order-2">
              <span className="chip">
                <IconChart width={13} height={13} className="text-brand-300" />
                Analytics with a point of view
              </span>
              <h2 className="mt-5 text-3xl font-semibold tracking-tight sm:text-4xl">
                Analytics that tell you what to do next
              </h2>
              <p className="mt-4 text-lg leading-relaxed text-ink-soft">
                Numbers are easy. Knowing what they mean is the hard part.
                cre8tor turns your metrics into plain-English moves: what to
                double down on, what to drop, and what to post next.
              </p>
              <ul className="mt-6 space-y-3">
                {[
                  "Spots your winning formats automatically",
                  "Tells you the best time to publish per platform",
                  "Turns insights into your next draft in one click",
                ].map((t) => (
                  <li key={t} className="flex items-start gap-3 text-sm text-ink-soft">
                    <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-brand-500/15 text-brand-300">
                      <IconCheck width={13} height={13} />
                    </span>
                    {t}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </section>

        {/* ============================ TESTIMONIALS ========================== */}
        <section className="border-y border-line bg-bg-soft/30">
          <div className="container-page py-24">
            <div className="mx-auto max-w-2xl text-center">
              <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">
                Creators who stopped guessing
              </h2>
              <p className="mt-4 text-lg text-ink-soft">
                Real momentum, less busywork. Here's what changed for them.
              </p>
            </div>

            <div className="mt-14 grid gap-5 md:grid-cols-3">
              {testimonials.map((t) => (
                <figure key={t.name} className="card flex h-full flex-col p-6">
                  <blockquote className="flex-1 text-sm leading-relaxed text-ink-soft">
                    “{t.quote}”
                  </blockquote>
                  <figcaption className="mt-6 flex items-center gap-3">
                    <Avatar
                      initials={t.name
                        .split(" ")
                        .map((n) => n[0])
                        .join("")}
                      color={t.color}
                    />
                    <span>
                      <span className="block text-sm font-semibold text-ink">
                        {t.name}
                      </span>
                      <span className="block text-xs text-ink-faint">
                        {t.handle}
                      </span>
                    </span>
                  </figcaption>
                </figure>
              ))}
            </div>
          </div>
        </section>

        {/* ============================ PRICING TEASER ======================== */}
        <section className="container-page py-24">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">
              Simple pricing that grows with you
            </h2>
            <p className="mt-4 text-lg text-ink-soft">
              Start free. Upgrade when cre8tor is pulling its weight — which is
              usually week one.
            </p>
          </div>

          <div className="mx-auto mt-12 grid max-w-3xl gap-4 sm:grid-cols-3">
            {plans.map((p) => (
              <div
                key={p.name}
                className={`card p-6 text-center ${
                  p.featured
                    ? "border-transparent bg-brand-500/[0.06] shadow-glow"
                    : ""
                }`}
              >
                {p.featured && (
                  <span className="chip mb-3 border-brand-400/40 text-brand-200">
                    Most popular
                  </span>
                )}
                <p className="text-sm font-medium text-ink-soft">{p.name}</p>
                <p className="mt-2 text-3xl font-semibold text-ink">
                  {p.price}
                  <span className="text-base font-normal text-ink-faint">
                    {p.note}
                  </span>
                </p>
              </div>
            ))}
          </div>

          <div className="mt-8 text-center">
            <Link href="/pricing" className="btn-ghost">
              Compare all plans
              <IconArrow width={16} height={16} />
            </Link>
          </div>
        </section>

        {/* ============================== FINAL CTA =========================== */}
        <section className="container-page pb-24">
          <div className="relative overflow-hidden rounded-3xl border border-line-strong bg-bg-card p-10 text-center sm:p-16">
            <div className="pointer-events-none absolute inset-0 -z-10 bg-radial-fade opacity-90" />
            <div
              className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-1 bg-brand-gradient"
              aria-hidden
            />
            <h2 className="mx-auto max-w-2xl text-4xl font-semibold tracking-tight sm:text-5xl">
              Stop guessing.{" "}
              <span className="gradient-text">Start growing.</span>
            </h2>
            <p className="mx-auto mt-5 max-w-xl text-lg text-ink-soft">
              Give cre8tor a week. It'll hand you a content plan, drafts in your
              voice, and a clear read on what's working.
            </p>
            <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
              <Link href="/signup" className="btn-primary">
                Start free
                <IconArrow width={16} height={16} />
              </Link>
              <Link href="/pricing" className="btn-ghost">
                View pricing
              </Link>
            </div>
            <p className="mt-5 text-xs text-ink-faint">
              No credit card required · 7-day trial
            </p>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
