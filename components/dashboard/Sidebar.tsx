"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useStore } from "@/lib/store";
import { Logo } from "@/components/Logo";
import {
  IconChat,
  IconChart,
  IconLayers,
  IconCalendar,
  IconLink,
  IconSettings,
  IconSpark,
  IconVideo,
  IconMic,
  IconX,
} from "@/components/Icons";

const nav = [
  { href: "/dashboard", label: "Create", Icon: IconChat, exact: true },
  { href: "/dashboard/studio", label: "Video Studio", Icon: IconVideo },
  { href: "/dashboard/ugc", label: "UGC Video", Icon: IconMic },
  { href: "/dashboard/library", label: "Library", Icon: IconLayers },
  { href: "/dashboard/calendar", label: "Calendar", Icon: IconCalendar },
  { href: "/dashboard/analytics", label: "Analytics", Icon: IconChart },
  { href: "/dashboard/connections", label: "Connections", Icon: IconLink },
  { href: "/dashboard/settings", label: "Settings", Icon: IconSettings },
];

export function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const router = useRouter();
  const user = useStore((s) => s.user);
  const voiceTrained = useStore((s) => s.voice.trained);

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between px-5 pb-6 pt-6">
        <Logo size="md" />
        {onNavigate && (
          <button onClick={onNavigate} className="rounded-lg p-1.5 text-ink-faint hover:bg-white/10 lg:hidden">
            <IconX width={18} height={18} />
          </button>
        )}
      </div>

      <nav className="flex-1 space-y-1 px-3">
        {nav.map(({ href, label, Icon, exact }) => {
          const active = exact ? pathname === href : pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              onClick={onNavigate}
              className={`group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition ${
                active
                  ? "bg-white/[0.07] text-ink"
                  : "text-ink-soft hover:bg-white/[0.04] hover:text-ink"
              }`}
            >
              <Icon
                width={19}
                height={19}
                className={active ? "text-brand-300" : "text-ink-faint group-hover:text-ink-soft"}
              />
              {label}
              {active && <span className="ml-auto h-1.5 w-1.5 rounded-full bg-brand-400" />}
            </Link>
          );
        })}
      </nav>

      {/* voice status */}
      <div className="px-3 pb-3">
        <div className="rounded-2xl border border-line bg-white/[0.02] p-3.5">
          <div className="flex items-center gap-2 text-xs font-medium">
            <IconSpark width={15} height={15} className="text-brand-300" />
            Voice profile
          </div>
          <p className="mt-1 text-xs text-ink-faint">
            {voiceTrained ? "Trained & active" : "Not trained yet"}
          </p>
          {!voiceTrained && (
            <Link
              href="/dashboard/settings"
              onClick={onNavigate}
              className="mt-2 inline-block text-xs font-semibold text-brand-300 hover:text-brand-200"
            >
              Train now →
            </Link>
          )}
        </div>
      </div>

      {/* user */}
      <div className="border-t border-line p-3">
        <button
          onClick={() => router.push("/dashboard/settings")}
          className="flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left hover:bg-white/[0.04]"
        >
          <span
            className="grid h-9 w-9 shrink-0 place-items-center rounded-full text-sm font-semibold text-white"
            style={{ background: user?.avatarColor || "#6366f1" }}
          >
            {user?.name?.[0]?.toUpperCase() || "U"}
          </span>
          <span className="min-w-0">
            <span className="block truncate text-sm font-medium">{user?.name || "You"}</span>
            <span className="block truncate text-xs capitalize text-ink-faint">
              {user?.plan || "trial"} plan
            </span>
          </span>
        </button>
      </div>
    </div>
  );
}
