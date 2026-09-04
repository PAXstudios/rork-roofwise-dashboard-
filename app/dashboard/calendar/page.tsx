"use client";

import { useEffect, useMemo, useState } from "react";
import { useStore } from "@/lib/store";
import type { Draft, Platform } from "@/lib/types";
import { useHydrated } from "@/lib/hooks";
import { PlatformBadge, PLATFORM_META } from "@/components/platform";
import { IconArrow, IconCalendar, IconClock, IconX } from "@/components/Icons";

const PLATFORMS: Platform[] = ["linkedin", "instagram", "x", "tiktok", "youtube"];
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

const DAY = 86_400_000;

function startOfDay(ts: number) {
  const d = new Date(ts);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export default function CalendarPage() {
  const hydrated = useHydrated();
  const drafts = useStore((s) => s.drafts);
  const setDraftStatus = useStore((s) => s.setDraftStatus);

  // compute "today" once on the client to avoid hydration mismatch
  const [today, setToday] = useState<number | null>(null);
  const [cursor, setCursor] = useState<{ year: number; month: number } | null>(
    null
  );
  const [selected, setSelected] = useState<number | null>(null);

  useEffect(() => {
    const now = new Date();
    setToday(startOfDay(now.getTime()));
    setCursor({ year: now.getFullYear(), month: now.getMonth() });
  }, []);

  const scheduledByDay = useMemo(() => {
    const map = new Map<number, Draft[]>();
    drafts.forEach((d) => {
      if (d.scheduledAt) {
        const key = startOfDay(d.scheduledAt);
        const arr = map.get(key) || [];
        arr.push(d);
        map.set(key, arr);
      }
    });
    return map;
  }, [drafts]);

  const unscheduled = useMemo(
    () => drafts.filter((d) => d.status === "draft" && !d.scheduledAt),
    [drafts]
  );

  const cells = useMemo(() => {
    if (!cursor) return [];
    const first = new Date(cursor.year, cursor.month, 1);
    const startPad = first.getDay();
    const daysInMonth = new Date(cursor.year, cursor.month + 1, 0).getDate();
    const list: (number | null)[] = [];
    for (let i = 0; i < startPad; i++) list.push(null);
    for (let d = 1; d <= daysInMonth; d++) {
      list.push(startOfDay(new Date(cursor.year, cursor.month, d).getTime()));
    }
    while (list.length % 7 !== 0) list.push(null);
    return list;
  }, [cursor]);

  if (!hydrated || !cursor || today === null) {
    return (
      <div className="space-y-6">
        <div className="h-10 w-48 shimmer rounded-xl bg-white/[0.04]" />
        <div className="h-[520px] shimmer rounded-2xl border border-line bg-white/[0.02]" />
      </div>
    );
  }

  function shift(delta: number) {
    setCursor((c) => {
      if (!c) return c;
      const m = c.month + delta;
      return {
        year: c.year + Math.floor(m / 12),
        month: ((m % 12) + 12) % 12,
      };
    });
  }

  const selectedDrafts = selected ? scheduledByDay.get(selected) || [] : [];

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
            Calendar
          </h1>
          <p className="mt-1 text-sm text-ink-soft">
            Plan the week ahead. Drag your best ideas onto the days that matter.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {PLATFORMS.map((p) => (
            <span
              key={p}
              className="inline-flex items-center gap-1.5 text-xs text-ink-soft"
            >
              <span
                className="h-2.5 w-2.5 rounded-full"
                style={{ background: PLATFORM_META[p].color }}
              />
              {PLATFORM_META[p].label}
            </span>
          ))}
        </div>
      </header>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        <section className="card overflow-hidden">
          <div className="flex items-center justify-between border-b border-line px-5 py-4">
            <h2 className="text-lg font-semibold">
              {MONTHS[cursor.month]} {cursor.year}
            </h2>
            <div className="flex items-center gap-1">
              <button
                onClick={() => shift(-1)}
                aria-label="Previous month"
                className="grid h-9 w-9 place-items-center rounded-lg border border-line-strong bg-white/[0.02] text-ink-soft transition hover:text-ink"
              >
                <IconArrow width={16} height={16} className="rotate-180" />
              </button>
              <button
                onClick={() => {
                  const n = new Date();
                  setCursor({ year: n.getFullYear(), month: n.getMonth() });
                }}
                className="btn-subtle px-3 py-1.5 text-xs"
              >
                Today
              </button>
              <button
                onClick={() => shift(1)}
                aria-label="Next month"
                className="grid h-9 w-9 place-items-center rounded-lg border border-line-strong bg-white/[0.02] text-ink-soft transition hover:text-ink"
              >
                <IconArrow width={16} height={16} />
              </button>
            </div>
          </div>

          <div className="grid grid-cols-7 border-b border-line text-center text-xs font-medium uppercase tracking-wide text-ink-faint">
            {WEEKDAYS.map((w) => (
              <div key={w} className="py-2">
                {w}
              </div>
            ))}
          </div>

          <div className="grid grid-cols-7">
            {cells.map((ts, i) => {
              if (ts === null)
                return (
                  <div
                    key={i}
                    className="min-h-[92px] border-b border-r border-line bg-white/[0.01]"
                  />
                );
              const dayDrafts = scheduledByDay.get(ts) || [];
              const isToday = ts === today;
              const isSelected = ts === selected;
              return (
                <button
                  key={i}
                  onClick={() => setSelected(ts)}
                  className={`min-h-[92px] border-b border-r border-line p-1.5 text-left align-top transition hover:bg-white/[0.03] ${
                    isSelected ? "bg-brand-500/10" : ""
                  }`}
                >
                  <span
                    className={`inline-grid h-6 w-6 place-items-center rounded-full text-xs font-medium ${
                      isToday
                        ? "bg-brand-gradient text-white"
                        : "text-ink-soft"
                    }`}
                  >
                    {new Date(ts).getDate()}
                  </span>
                  <div className="mt-1 space-y-1">
                    {dayDrafts.slice(0, 3).map((d) => (
                      <span
                        key={d.id}
                        className="flex items-center gap-1 rounded-md border border-line bg-white/[0.03] px-1 py-0.5"
                        style={{
                          borderLeftColor: PLATFORM_META[d.platform].color,
                          borderLeftWidth: 2,
                        }}
                      >
                        <PlatformBadge platform={d.platform} size={10} />
                        <span className="line-clamp-1 text-[11px] text-ink-soft">
                          {d.title}
                        </span>
                      </span>
                    ))}
                    {dayDrafts.length > 3 && (
                      <span className="px-1 text-[11px] text-ink-faint">
                        +{dayDrafts.length - 3} more
                      </span>
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </section>

        <aside className="space-y-6">
          {selected && (
            <div className="card p-4">
              <div className="mb-3 flex items-center justify-between">
                <h3 className="flex items-center gap-2 font-semibold">
                  <IconCalendar width={16} height={16} className="text-brand-300" />
                  {new Date(selected).toLocaleDateString(undefined, {
                    weekday: "short",
                    month: "short",
                    day: "numeric",
                  })}
                </h3>
                <button
                  onClick={() => setSelected(null)}
                  aria-label="Clear selection"
                  className="grid h-7 w-7 place-items-center rounded-lg text-ink-soft transition hover:bg-white/[0.06] hover:text-ink"
                >
                  <IconX width={15} height={15} />
                </button>
              </div>
              {selectedDrafts.length === 0 ? (
                <p className="text-sm text-ink-faint">
                  Nothing scheduled. Schedule a draft from the rail below.
                </p>
              ) : (
                <div className="space-y-2">
                  {selectedDrafts.map((d) => (
                    <div
                      key={d.id}
                      className="flex items-start gap-2 rounded-xl border border-line bg-white/[0.02] p-2.5"
                    >
                      <PlatformBadge platform={d.platform} size={14} />
                      <div className="min-w-0 flex-1">
                        <p className="line-clamp-1 text-sm font-medium">
                          {d.title}
                        </p>
                        <p className="line-clamp-1 text-xs text-ink-faint">
                          {d.body}
                        </p>
                      </div>
                      <button
                        onClick={() => setDraftStatus(d.id, "draft", undefined)}
                        title="Unschedule"
                        className="text-xs text-ink-faint transition hover:text-red-400"
                      >
                        Remove
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          <div className="card p-4">
            <h3 className="flex items-center gap-2 font-semibold">
              <IconClock width={16} height={16} className="text-brand-300" />
              Unscheduled drafts
            </h3>
            <p className="mt-1 text-xs text-ink-faint">
              {selected
                ? "Pick one to schedule for the selected day."
                : "Select a day, then schedule a draft."}
            </p>
            <div className="mt-3 space-y-2">
              {unscheduled.length === 0 ? (
                <p className="text-sm text-ink-faint">
                  All caught up — no loose drafts.
                </p>
              ) : (
                unscheduled.map((d) => (
                  <div
                    key={d.id}
                    className="flex items-start gap-2 rounded-xl border border-line bg-white/[0.02] p-2.5"
                  >
                    <PlatformBadge platform={d.platform} size={14} />
                    <div className="min-w-0 flex-1">
                      <p className="line-clamp-1 text-sm font-medium">
                        {d.title}
                      </p>
                      <p className="line-clamp-1 text-xs text-ink-faint">
                        {d.body}
                      </p>
                    </div>
                    <button
                      disabled={!selected}
                      onClick={() =>
                        selected &&
                        setDraftStatus(d.id, "scheduled", selected + 9 * 3600_000)
                      }
                      className="shrink-0 rounded-lg border border-brand-400/40 bg-brand-500/10 px-2.5 py-1 text-xs font-medium text-brand-200 transition hover:bg-brand-500/20 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Schedule
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
}
