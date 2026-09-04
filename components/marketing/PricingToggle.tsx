"use client";

import { useState } from "react";
import Link from "next/link";
import { IconCheck } from "@/components/Icons";

type Tier = {
  name: string;
  description: string;
  monthly: number;
  annual: number; // per-month price when billed annually
  cta: string;
  featured?: boolean;
  priceNote?: string; // overrides price rendering (e.g. Starter trial)
  features: string[];
};

const tiers: Tier[] = [
  {
    name: "Starter",
    description: "For testing the waters and finding your voice.",
    monthly: 0,
    annual: 0,
    priceNote: "7-day trial",
    cta: "Start free",
    features: [
      "1 connected account",
      "15 AI drafts / month",
      "Voice training (basics)",
      "Content library",
      "Post-level analytics",
    ],
  },
  {
    name: "Creator",
    description: "For serious creators posting every week.",
    monthly: 49,
    annual: 39,
    cta: "Get Creator",
    featured: true,
    features: [
      "3 connected accounts",
      "Unlimited AI drafts",
      "Full voice training + dials",
      "Interview mode",
      "Smart scheduling calendar",
      "Strategy & ideas on demand",
      "Advanced analytics",
    ],
  },
  {
    name: "Pro",
    description: "For teams and power users running at scale.",
    monthly: 99,
    annual: 79,
    cta: "Get Pro",
    features: [
      "Everything in Creator",
      "Unlimited connected accounts",
      "Up to 5 team seats",
      "Multiple voice profiles",
      "Competitor & trend analysis",
      "Priority support",
      "Early access to new features",
    ],
  },
];

export function PricingToggle() {
  const [annual, setAnnual] = useState(true);

  return (
    <div>
      {/* toggle */}
      <div className="flex items-center justify-center gap-4">
        <span
          className={`text-sm font-medium ${annual ? "text-ink-faint" : "text-ink"}`}
        >
          Monthly
        </span>
        <button
          type="button"
          role="switch"
          aria-checked={annual}
          aria-label="Toggle annual billing"
          onClick={() => setAnnual((v) => !v)}
          className="relative h-7 w-12 rounded-full border border-line-strong bg-white/[0.04] transition-colors"
        >
          <span
            className={`absolute top-1/2 h-5 w-5 -translate-y-1/2 rounded-full bg-brand-gradient transition-all ${
              annual ? "left-6" : "left-1"
            }`}
          />
        </button>
        <span
          className={`text-sm font-medium ${annual ? "text-ink" : "text-ink-faint"}`}
        >
          Annual
          <span className="ml-2 rounded-full bg-brand-500/15 px-2 py-0.5 text-xs font-semibold text-brand-200">
            Save 20%
          </span>
        </span>
      </div>

      {/* cards */}
      <div className="mt-12 grid gap-5 lg:grid-cols-3">
        {tiers.map((t) => {
          const price = annual ? t.annual : t.monthly;
          return (
            <div
              key={t.name}
              className={`card relative flex flex-col p-7 ${
                t.featured ? "border-transparent shadow-glow" : ""
              }`}
            >
              {t.featured && (
                <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-brand-gradient px-3 py-1 text-xs font-semibold text-white shadow-[0_8px_24px_-8px_rgba(99,102,241,0.8)]">
                  Most popular
                </span>
              )}

              <h3 className="text-lg font-semibold text-ink">{t.name}</h3>
              <p className="mt-1.5 min-h-[40px] text-sm text-ink-soft">
                {t.description}
              </p>

              <div className="mt-5 flex items-baseline gap-1">
                <span className="text-4xl font-semibold text-ink">${price}</span>
                <span className="text-sm text-ink-faint">
                  {t.priceNote ?? "/mo"}
                </span>
              </div>
              {!t.priceNote && annual && (
                <p className="mt-1 text-xs text-ink-faint">billed annually</p>
              )}
              {!t.priceNote && !annual && (
                <p className="mt-1 text-xs text-ink-faint">billed monthly</p>
              )}
              {t.priceNote && (
                <p className="mt-1 text-xs text-ink-faint">then $49/mo</p>
              )}

              <Link
                href="/signup"
                className={`mt-6 w-full ${t.featured ? "btn-primary" : "btn-ghost"}`}
              >
                {t.cta}
              </Link>

              <ul className="mt-7 space-y-3 border-t border-line pt-6">
                {t.features.map((f) => (
                  <li key={f} className="flex items-start gap-3 text-sm text-ink-soft">
                    <span className="mt-0.5 grid h-5 w-5 shrink-0 place-items-center rounded-full bg-brand-500/15 text-brand-300">
                      <IconCheck width={13} height={13} />
                    </span>
                    {f}
                  </li>
                ))}
              </ul>
            </div>
          );
        })}
      </div>
    </div>
  );
}
