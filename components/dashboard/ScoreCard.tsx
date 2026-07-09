"use client";

import type { VideoScore } from "@/lib/types";
import { IconTarget, IconSpark } from "@/components/Icons";

function ring(score: number) {
  if (score >= 80) return "#a3e635"; // lime
  if (score >= 60) return "#818cf8"; // brand
  if (score >= 40) return "#fb923c"; // warm
  return "#f87171"; // red
}

function Meter({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <div className="mb-1 flex items-center justify-between text-xs">
        <span className="text-ink-soft">{label}</span>
        <span className="font-semibold text-ink">{value}</span>
      </div>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-white/[0.06]">
        <div
          className="h-full rounded-full"
          style={{ width: `${value}%`, background: ring(value) }}
        />
      </div>
    </div>
  );
}

export function ScoreCard({ score }: { score: VideoScore }) {
  const c = ring(score.overall);
  return (
    <div className="card p-5">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="flex items-center gap-2 font-semibold">
          <IconTarget width={16} height={16} className="text-brand-300" />
          Virality score
        </h3>
        <span className="chip">
          <span className={`h-1.5 w-1.5 rounded-full ${score.engine === "higgsfield" ? "bg-accent-lime" : "bg-accent-warm"}`} />
          {score.engine === "higgsfield" ? "Higgsfield" : "estimate"}
        </span>
      </div>

      <div className="flex items-center gap-5">
        <div
          className="relative grid h-24 w-24 shrink-0 place-items-center rounded-full"
          style={{ background: `conic-gradient(${c} ${score.overall * 3.6}deg, rgba(255,255,255,0.08) 0deg)` }}
        >
          <div className="grid h-[84px] w-[84px] place-items-center rounded-full bg-bg-card">
            <div className="text-center">
              <div className="text-2xl font-bold" style={{ color: c }}>{score.overall}</div>
              <div className="text-[10px] uppercase tracking-wide text-ink-faint">/ 100</div>
            </div>
          </div>
        </div>

        <div className="flex-1 space-y-2.5">
          <Meter label="Hook" value={score.hook} />
          <Meter label="Attention" value={score.attention} />
          <Meter label="Retention" value={score.retention} />
        </div>
      </div>

      {score.notes.length > 0 && (
        <div className="mt-4 space-y-1.5 border-t border-line pt-3">
          {score.notes.map((n, i) => (
            <p key={i} className="flex items-start gap-2 text-xs text-ink-soft">
              <IconSpark width={12} height={12} className="mt-0.5 shrink-0 text-brand-300" />
              {n}
            </p>
          ))}
        </div>
      )}
    </div>
  );
}
