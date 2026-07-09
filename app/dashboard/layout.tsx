"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useStore } from "@/lib/store";
import { useHydrated } from "@/lib/hooks";
import { Sidebar } from "@/components/dashboard/Sidebar";
import { Logo } from "@/components/Logo";
import { IconMenu } from "@/components/Icons";

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const hydrated = useHydrated();
  const user = useStore((s) => s.user);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    if (hydrated && !user) router.replace("/login");
  }, [hydrated, user, router]);

  if (!hydrated || !user) {
    return (
      <div className="grid min-h-screen place-items-center bg-bg text-ink-faint">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-line-strong border-t-brand-400" />
      </div>
    );
  }

  return (
    <div className="flex min-h-screen bg-bg">
      {/* desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 hidden w-64 border-r border-line bg-bg-soft lg:block">
        <Sidebar />
      </aside>

      {/* mobile drawer */}
      {mobileOpen && (
        <div className="fixed inset-0 z-40 lg:hidden">
          <div
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
            onClick={() => setMobileOpen(false)}
          />
          <aside className="absolute inset-y-0 left-0 w-72 border-r border-line bg-bg-soft">
            <Sidebar onNavigate={() => setMobileOpen(false)} />
          </aside>
        </div>
      )}

      {/* content */}
      <div className="flex min-h-screen w-full flex-col lg:pl-64">
        {/* mobile topbar */}
        <div className="sticky top-0 z-30 flex items-center justify-between border-b border-line bg-bg/80 px-4 py-3 backdrop-blur lg:hidden">
          <button
            onClick={() => setMobileOpen(true)}
            className="rounded-lg p-1.5 text-ink-soft hover:bg-white/10"
          >
            <IconMenu width={22} height={22} />
          </button>
          <Logo size="sm" />
          <span className="w-8" />
        </div>

        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}
