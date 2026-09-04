"use client";

import { useMemo } from "react";
import Link from "next/link";
import { useStore } from "@/lib/store";
import type { SocialPost } from "@/lib/types";
import { useHydrated, compact } from "@/lib/hooks";
import { PlatformBadge, PLATFORM_META } from "@/components/platform";
import { IconChart, IconArrow, IconLink } from "@/components/Icons";

function engagement(p: { impressions: number; likes: number; comments: number; shares?: number }) {
  if (!p.impressions) return 0;
  return (p.likes + p.comments + (p.shares || 0)) / p.impressions;
}

export default function AnalyticsPage() {
  const hydrated = useHydrated();
  const connections = useStore((s) => s.connections);
  const drafts = useStore((s) => s.drafts);

  const data = useMemo(() => {
    const connected = connections.filter((c) => c.connected);
    const allPosts: SocialPost[] = connected.flatMap((c) => c.recentPosts || []);
    const published = drafts.filter((d) => d.status === "published" && d.metrics);

    const totalFollowers = connected.reduce((s, c) => s + (c.followers || 0), 0);
    const postImpr = allPosts.reduce((s, p) => s + p.impressions, 0);
    const draftImpr = published.reduce((s, d) => s + (d.metrics!.impressions), 0);
    const totalImpressions = postImpr + draftImpr;

    const engRates = allPosts.map(engagement);
    const avgEng =
      engRates.length > 0
        ? engRates.reduce((s, e) => s + e, 0) / engRates.length
        : 0;

    const recentBars = [...allPosts]
      .sort((a, b) => a.postedAt - b.postedAt)
      .slice(-8);

    const topPosts = [...allPosts]
      .sort((a, b) => b.impressions - a.impressions)
      .slice(0, 5);

    const breakdown = connected.map((c) => {
      const posts = c.recentPosts || [];
      const avgImpr =
        posts.length > 0
          ? Math.round(posts.reduce((s, p) => s + p.impressions, 0) / posts.length)
          : 0;
      return { connection: c, avgImpr };
    });

    return {
      connectedCount: connected.length,
      totalFollowers,
      totalImpressions,
      avgEng,
      publishedCount: published.length,
      recentBars,
      topPosts,
      breakdown,
    };
  }, [connections, drafts]);

  if (!hydrated) {
    return (
      <div className="space-y-6">
        <div className="h-10 w-44 shimmer rounded-xl bg-white/[0.04]" />
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="h-28 shimmer rounded-2xl border border-line bg-white/[0.02]"
            />
          ))}
        </div>
        <div className="h-72 shimmer rounded-2xl border border-line bg-white/[0.02]" />
      </div>
    );
  }

  if (data.connectedCount === 0) {
    return (
      <div className="space-y-6">
        <Header />
        <div className="card flex flex-col items-center justify-center gap-3 px-6 py-20 text-center">
          <span className="grid h-12 w-12 place-items-center rounded-2xl bg-brand-500/10 text-brand-300">
            <IconChart width={22} height={22} />
          </span>
          <h3 className="text-lg font-semibold">No data to chart yet</h3>
          <p className="max-w-sm text-sm text-ink-soft">
            Connect a platform and cre8tor will pull in your reach, engagement,
            and top posts.
          </p>
          <Link href="/dashboard/connections" className="btn-primary mt-1">
            <IconLink width={16} height={16} />
            Connect an account
          </Link>
        </div>
      </div>
    );
  }

  const maxBar = Math.max(...data.recentBars.map((p) => p.impressions), 1);

  return (
    <div className="space-y-6">
      <Header />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Total followers" value={compact(data.totalFollowers)} sub={`${data.connectedCount} connected`} />
        <Stat label="Total impressions" value={compact(data.totalImpressions)} sub="Last posts + published" />
        <Stat label="Avg engagement" value={`${(data.avgEng * 100).toFixed(1)}%`} sub="Across recent posts" />
        <Stat label="Posts published" value={String(data.publishedCount)} sub="Tracked in cre8tor" />
      </div>

      <section className="card p-5">
        <h2 className="flex items-center gap-2 font-semibold">
          <IconChart width={16} height={16} className="text-brand-300" />
          Impressions over recent posts
        </h2>
        <div className="mt-6 flex h-56 items-stretch gap-2 sm:gap-3">
          {data.recentBars.map((p) => (
            <div key={p.id} className="flex flex-1 flex-col items-center gap-2">
              <div className="flex w-full flex-1 items-end">
                <div
                  className="w-full rounded-t-md bg-brand-gradient transition-all"
                  style={{ height: `${Math.max((p.impressions / maxBar) * 100, 4)}%` }}
                  title={`${compact(p.impressions)} impressions`}
                />
              </div>
              <span className="text-[10px] text-ink-faint">
                {compact(p.impressions)}
              </span>
              <span className="text-[10px] text-ink-faint">
                {new Date(p.postedAt).toLocaleDateString(undefined, {
                  month: "short",
                  day: "numeric",
                })}
              </span>
            </div>
          ))}
        </div>
      </section>

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <section className="card p-5">
          <h2 className="font-semibold">Top performing posts</h2>
          <div className="mt-4 space-y-3">
            {data.topPosts.map((p, i) => (
              <div
                key={p.id}
                className="flex items-start gap-3 rounded-xl border border-line bg-white/[0.02] p-3"
              >
                <span className="mt-0.5 w-5 shrink-0 text-sm font-semibold text-ink-faint">
                  {i + 1}
                </span>
                <PlatformBadge platform={p.platform} size={14} />
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-2 text-sm text-ink-soft">{p.text}</p>
                  <div className="mt-1.5 flex flex-wrap gap-3 text-xs text-ink-faint">
                    <span>
                      <span className="font-semibold text-ink">
                        {compact(p.impressions)}
                      </span>{" "}
                      impressions
                    </span>
                    <span>
                      <span className="font-semibold text-ink">
                        {compact(p.likes)}
                      </span>{" "}
                      likes
                    </span>
                    <span>
                      <span className="font-semibold text-emerald-400">
                        {(engagement(p) * 100).toFixed(1)}%
                      </span>{" "}
                      eng.
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="card p-5">
          <h2 className="font-semibold">Platform breakdown</h2>
          <div className="mt-4 space-y-3">
            {data.breakdown.map(({ connection, avgImpr }) => (
              <div
                key={connection.platform}
                className="rounded-xl border border-line bg-white/[0.02] p-3"
              >
                <div className="flex items-center gap-2">
                  <PlatformBadge platform={connection.platform} size={16} />
                  <div className="min-w-0">
                    <p className="text-sm font-medium">
                      {PLATFORM_META[connection.platform].label}
                    </p>
                    <p className="truncate text-xs text-ink-faint">
                      {connection.handle}
                    </p>
                  </div>
                </div>
                <div className="mt-3 grid grid-cols-2 gap-2">
                  <div className="rounded-lg bg-white/[0.02] px-3 py-2">
                    <p className="text-lg font-semibold">
                      {compact(connection.followers || 0)}
                    </p>
                    <p className="text-xs text-ink-faint">Followers</p>
                  </div>
                  <div className="rounded-lg bg-white/[0.02] px-3 py-2">
                    <p className="text-lg font-semibold">{compact(avgImpr)}</p>
                    <p className="text-xs text-ink-faint">Avg impressions</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}

function Header() {
  return (
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Analytics
        </h1>
        <p className="mt-1 text-sm text-ink-soft">
          How your voice is landing — reach, engagement, and what&apos;s working.
        </p>
      </div>
      <Link href="/dashboard/connections" className="btn-ghost">
        Manage accounts
        <IconArrow width={16} height={16} />
      </Link>
    </header>
  );
}

function Stat({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <div className="card p-4">
      <p className="text-xs uppercase tracking-wide text-ink-faint">{label}</p>
      <p className="mt-2 text-3xl font-semibold tracking-tight gradient-text">
        {value}
      </p>
      <p className="mt-1 text-xs text-ink-faint">{sub}</p>
    </div>
  );
}
