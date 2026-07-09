"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useStore } from "@/lib/store";
import { Logo } from "@/components/Logo";
import { IconArrow, IconCheck } from "@/components/Icons";

const socials = [
  { key: "google", label: "Continue with Google" },
  { key: "apple", label: "Continue with Apple" },
];

export function AuthCard({ mode }: { mode: "login" | "signup" }) {
  const router = useRouter();
  const signup = useStore((s) => s.signup);
  const login = useStore((s) => s.login);
  const voiceTrained = useStore((s) => s.voice.trained);

  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const isSignup = mode === "signup";

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    if (isSignup && name.trim().length < 2) return setError("Please enter your name.");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return setError("Enter a valid email.");
    if (password.length < 6) return setError("Password must be at least 6 characters.");

    setLoading(true);
    setTimeout(() => {
      if (isSignup) {
        signup(name.trim(), email.trim());
        router.push("/onboarding");
      } else {
        login(email.trim());
        router.push(voiceTrained ? "/dashboard" : "/onboarding");
      }
    }, 450);
  }

  function quickDemo(social: string) {
    setLoading(true);
    setTimeout(() => {
      const demoEmail = `you@${social}.demo`;
      if (isSignup) {
        signup("Demo Creator", demoEmail);
        router.push("/onboarding");
      } else {
        login(demoEmail);
        router.push("/onboarding");
      }
    }, 400);
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden px-5 py-10">
      <div className="pointer-events-none absolute inset-0 bg-radial-fade" />
      <div className="pointer-events-none absolute -top-40 left-1/2 h-96 w-96 -translate-x-1/2 rounded-full bg-brand-600/20 blur-3xl" />

      <div className="relative w-full max-w-md animate-fade-up">
        <div className="mb-8 flex justify-center">
          <Logo size="lg" />
        </div>

        <div className="card p-7 sm:p-8">
          <h1 className="text-2xl font-semibold tracking-tight">
            {isSignup ? "Create your account" : "Welcome back"}
          </h1>
          <p className="mt-1.5 text-sm text-ink-soft">
            {isSignup
              ? "Start growing with your AI Head of Content."
              : "Sign in to pick up where you left off."}
          </p>

          <div className="mt-6 grid gap-2.5">
            {socials.map((s) => (
              <button
                key={s.key}
                onClick={() => quickDemo(s.key)}
                disabled={loading}
                className="btn-ghost w-full"
              >
                {s.label}
              </button>
            ))}
          </div>

          <div className="my-6 flex items-center gap-3 text-xs text-ink-faint">
            <span className="h-px flex-1 bg-line" />
            or with email
            <span className="h-px flex-1 bg-line" />
          </div>

          <form onSubmit={submit} className="grid gap-4">
            {isSignup && (
              <div>
                <label className="label">Name</label>
                <input
                  className="input"
                  placeholder="Aria Chen"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  autoComplete="name"
                />
              </div>
            )}
            <div>
              <label className="label">Email</label>
              <input
                className="input"
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
              />
            </div>
            <div>
              <label className="label">Password</label>
              <input
                className="input"
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete={isSignup ? "new-password" : "current-password"}
              />
            </div>

            {error && (
              <div className="rounded-xl border border-red-500/30 bg-red-500/10 px-3.5 py-2.5 text-sm text-red-300">
                {error}
              </div>
            )}

            <button type="submit" disabled={loading} className="btn-primary w-full">
              {loading ? (
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/40 border-t-white" />
              ) : (
                <>
                  {isSignup ? "Create account" : "Sign in"}
                  <IconArrow width={16} height={16} />
                </>
              )}
            </button>
          </form>

          {isSignup && (
            <ul className="mt-5 grid gap-1.5 text-xs text-ink-faint">
              {["7-day free trial", "No credit card required", "Cancel anytime"].map((t) => (
                <li key={t} className="flex items-center gap-2">
                  <IconCheck width={13} height={13} className="text-accent-lime" />
                  {t}
                </li>
              ))}
            </ul>
          )}
        </div>

        <p className="mt-6 text-center text-sm text-ink-soft">
          {isSignup ? "Already have an account? " : "New to cre8tor? "}
          <Link
            href={isSignup ? "/login" : "/signup"}
            className="font-semibold text-brand-300 hover:text-brand-200"
          >
            {isSignup ? "Log in" : "Start free"}
          </Link>
        </p>
      </div>
    </div>
  );
}
