"use client";

import { useMemo, useState } from "react";
import { useStore } from "@/lib/store";
import type { Connection, Platform } from "@/lib/types";
import { useHydrated, timeAgo, compact } from "@/lib/hooks";
import { PlatformBadge, PLATFORM_META } from "@/components/platform";
import { IconLink, IconCheck, IconX, IconSpark } from "@/components/Icons";

const ORDER: Platform[] = ["linkedin", "instagram", "x", "tiktok", "youtube"];

const BLURB: Record<Platform, string> = {
  linkedin: "Long-form authority and B2B reach.",
  instagram: "Visual storytelling and Reels.",
  x: "Fast takes, threads, and real-time reach.",
  tiktok: "Short video and discovery.",
  youtube: "Deep video and evergreen search.",
};

export default function ConnectionsPage() {
  const hydrated = useHydrated();
  const connections = useStore((s) => s.connections);
  const toggleConnection = useStore((s) => s.toggleConnection);

  const [busy, setBusy] = useState<Platform | null>(null);
  const [toast, setToast] = useState<{ platform: Platform; message: string } | null>(null);

  const byPlatform = useMemo(() => {
    const m = new Map<Platform, Connection>();
    connections.forEach((c) => m.set(c.platform, c));
    return m;
  }, [connections]);

  const connectedCount = connections.filter((c) => c.connected).length;

  async function connect(platform: Platform) {
    setBusy(platform);
    try {
      const res = await fetch("/api/connect", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ platform }),
      });
      const data = await res.json();
      if (data.ok && data.mode === "oauth" && data.authorizeUrl) {
        window.location.href = data.authorizeUrl;
        return;
      }
      if (data.ok) {
        toggleConnection(platform, data.handle);
        setToast({ platform, message: data.message || "Connected." });
        setTimeout(
          () => setToast((t) => (t?.platform === platform ? null : t)),
          4000
        );
      }
    } catch {
      setToast({ platform, message: "Could not reach the connect service." });
    } finally {
      setBusy(null);
    }
  }

  if (!hydrated) {
    return (
      <div className="space-y-6">
        <div className="h-10 w-52 shimmer rounded-xl bg-white/[0.04]" />
        <div className="space-y-3">
          {Array.from({ length: 5 }).map((_, i) => (
            <div
              key={i}
              className="h-24 shimmer rounded-2xl border border-line bg-white/[0.02]"
            />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          Connections
        </h1>
        <p className="mt-1 max-w-2xl text-sm text-ink-soft">
          Connected accounts power Analyze mode and your analytics — cre8tor
          reads your recent posts to learn what lands and study your voice.{" "}
          <span className="text-ink-faint">
            {connectedCount} of {ORDER.length} connected.
          </span>
        </p>
      </header>

      <div className="space-y-3">
        {ORDER.map((platform) => {
          const c = byPlatform.get(platform);
          const meta = PLATFORM_META[platform];
          const connected = !!c?.connected;
          return (
            <div
              key={platform}
              className="card flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between"
            >
              <div className="flex items-start gap-3">
                <PlatformBadge platform={platform} size={22} />
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="font-semibold">{meta.label}</h3>
                    {connected && (
                      <span className="inline-flex items-center gap-1 rounded-full border border-emerald-400/30 bg-emerald-400/10 px-2 py-0.5 text-[11px] font-medium text-emerald-300">
                        <IconCheck width={11} height={11} />
                        Connected
                      </span>
                    )}
                  </div>
                  {connected ? (
                    <p className="mt-0.5 text-sm text-ink-soft">
                      <span className="text-ink">{c?.handle}</span>
                      {" · "}
                      {compact(c?.followers || 0)} followers
                      {c?.connectedAt && (
                        <span className="text-ink-faint">
                          {" · "}Connected {timeAgo(c.connectedAt)}
                        </span>
                      )}
                    </p>
                  ) : (
                    <p className="mt-0.5 text-sm text-ink-faint">
                      {BLURB[platform]}
                    </p>
                  )}
                  {toast?.platform === platform && (
                    <p className="mt-2 flex items-start gap-1.5 rounded-lg border border-brand-400/30 bg-brand-500/10 px-2.5 py-1.5 text-xs text-brand-100">
                      <IconSpark width={13} height={13} className="mt-0.5 shrink-0" />
                      {toast.message}
                    </p>
                  )}
                </div>
              </div>

              <div className="shrink-0">
                {connected ? (
                  <button
                    onClick={() => toggleConnection(platform)}
                    className="btn-ghost"
                  >
                    <IconX width={16} height={16} />
                    Disconnect
                  </button>
                ) : (
                  <button
                    onClick={() => connect(platform)}
                    disabled={busy === platform}
                    className="btn-primary"
                  >
                    <IconLink width={16} height={16} />
                    {busy === platform ? "Connecting…" : "Connect"}
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>

      <p className="rounded-2xl border border-line bg-white/[0.02] px-4 py-3 text-xs text-ink-faint">
        Demo connections are simulated so you can explore cre8tor end to end. To
        link a real account, add that platform&apos;s API credentials to{" "}
        <code className="rounded bg-white/[0.06] px-1 py-0.5 text-ink-soft">
          .env.local
        </code>{" "}
        and the Connect button will start a live OAuth handshake.
      </p>
    </div>
  );
}
