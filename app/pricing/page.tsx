import Link from "next/link";
import { Nav } from "@/components/marketing/Nav";
import { Footer } from "@/components/marketing/Footer";
import { PricingToggle } from "@/components/marketing/PricingToggle";
import { IconSpark, IconArrow } from "@/components/Icons";

export const metadata = {
  title: "Pricing — cre8tor",
  description:
    "Simple, creator-friendly pricing for cre8tor. Start free, then pick the plan that grows with you.",
};

const faqs = [
  {
    q: "Can I really start for free?",
    a: "Yes. The 7-day Starter trial gives you real drafts, voice training, and analytics — no credit card required. Upgrade only when cre8tor is earning its keep.",
  },
  {
    q: "How does cre8tor learn my voice?",
    a: "It studies the posts you've already published and a few quick prompts about your tone and taste. From there, every draft comes back sounding like you — you can fine-tune the dials any time.",
  },
  {
    q: "Which platforms are supported?",
    a: "cre8tor writes, schedules, and analyzes for LinkedIn, Instagram, and X today, with TikTok and YouTube support rolling out. Connect as many accounts as your plan allows.",
  },
  {
    q: "Can I switch or cancel plans?",
    a: "Any time, from your dashboard. Upgrades take effect immediately and downgrades apply at your next billing date. No lock-in, no awkward emails.",
  },
  {
    q: "Do you offer team seats?",
    a: "The Pro plan includes up to 5 seats with multiple voice profiles — ideal for agencies and founder-led teams managing several accounts.",
  },
];

export default function PricingPage() {
  return (
    <div className="min-h-screen bg-bg text-ink">
      <Nav />

      <main>
        {/* header */}
        <section className="relative overflow-hidden bg-radial-fade">
          <div className="container-page pb-4 pt-16 text-center sm:pt-24">
            <span className="chip">
              <IconSpark width={14} height={14} className="text-brand-300" />
              Pricing
            </span>
            <h1 className="mx-auto mt-6 max-w-3xl text-4xl font-semibold tracking-tight sm:text-5xl">
              Pricing that pays for itself in{" "}
              <span className="gradient-text">one good post</span>
            </h1>
            <p className="mx-auto mt-5 max-w-xl text-lg text-ink-soft">
              Start free. Upgrade when cre8tor is drafting, scheduling, and
              growing your accounts for you.
            </p>
          </div>
        </section>

        {/* tiers + toggle */}
        <section className="container-page py-14">
          <PricingToggle />
        </section>

        {/* FAQ */}
        <section className="border-t border-line bg-bg-soft/30">
          <div className="container-page py-24">
            <div className="mx-auto max-w-2xl text-center">
              <h2 className="text-3xl font-semibold tracking-tight sm:text-4xl">
                Questions, answered
              </h2>
              <p className="mt-4 text-lg text-ink-soft">
                Still curious? Everything you need to know before you start.
              </p>
            </div>

            <div className="mx-auto mt-12 max-w-3xl divide-y divide-line">
              {faqs.map((f) => (
                <div key={f.q} className="py-6">
                  <h3 className="text-base font-semibold text-ink">{f.q}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-ink-soft">
                    {f.a}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* final CTA */}
        <section className="container-page py-24">
          <div className="relative overflow-hidden rounded-3xl border border-line-strong bg-bg-card p-10 text-center sm:p-16">
            <div className="pointer-events-none absolute inset-0 -z-10 bg-radial-fade opacity-90" />
            <div
              className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-1 bg-brand-gradient"
              aria-hidden
            />
            <h2 className="mx-auto max-w-2xl text-3xl font-semibold tracking-tight sm:text-4xl">
              Try cre8tor free for 7 days
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-lg text-ink-soft">
              Bring your accounts. Leave with a plan, drafts in your voice, and a
              clear read on what's working.
            </p>
            <div className="mt-8 flex justify-center">
              <Link href="/signup" className="btn-primary">
                Start free
                <IconArrow width={16} height={16} />
              </Link>
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
