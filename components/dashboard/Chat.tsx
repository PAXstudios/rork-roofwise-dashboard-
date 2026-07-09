"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { useStore } from "@/lib/store";
import { useHydrated, timeAgo } from "@/lib/hooks";
import { streamChat } from "@/lib/chatClient";
import { INTERVIEW_SEED_QUESTIONS } from "@/lib/prompts";
import { Markdown } from "./Markdown";
import { PLATFORM_META, PlatformBadge } from "@/components/platform";
import type { ChatMode, Platform } from "@/lib/types";
import {
  IconSend,
  IconPen,
  IconChart,
  IconMic,
  IconSpark,
  IconCopy,
  IconCheck,
  IconLayers,
  IconPlus,
  IconTrash,
} from "@/components/Icons";

const MODES: { key: ChatMode; label: string; sub: string; Icon: (p: any) => JSX.Element; prompt: string }[] = [
  {
    key: "voice",
    label: "Write in my voice",
    sub: "Draft a post that sounds like you",
    Icon: IconPen,
    prompt: "Write me a post about ",
  },
  {
    key: "analyze",
    label: "Analyze my posts",
    sub: "See what's working & what to do next",
    Icon: IconChart,
    prompt: "Analyze my recent posts and tell me what to create next.",
  },
  {
    key: "interview",
    label: "Interview me",
    sub: "Turn your ideas into finished content",
    Icon: IconMic,
    prompt: "Interview me to find my next great post.",
  },
];

export function Chat() {
  const hydrated = useHydrated();
  const voice = useStore((s) => s.voice);
  const connections = useStore((s) => s.connections);
  const conversations = useStore((s) => s.conversations);
  const activeId = useStore((s) => s.activeConversationId);
  const newConversation = useStore((s) => s.newConversation);
  const setActive = useStore((s) => s.setActiveConversation);
  const addMessage = useStore((s) => s.addMessage);
  const appendToMessage = useStore((s) => s.appendToMessage);
  const deleteConversation = useStore((s) => s.deleteConversation);

  const active = conversations.find((c) => c.id === activeId) || null;

  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [engine, setEngine] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const abortRef = useRef<AbortController | null>(null);

  const scrollToBottom = useCallback(() => {
    requestAnimationFrame(() => {
      scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
    });
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [active?.messages.length, scrollToBottom]);

  const send = useCallback(
    async (text: string, convId: string, mode: ChatMode) => {
      const clean = text.trim();
      if (!clean || busy) return;

      addMessage(convId, { role: "user", content: clean });
      setInput("");
      setBusy(true);
      scrollToBottom();

      // Build wire history from current store state. addMessage above already
      // committed the user turn synchronously, so it's included here.
      const conv = useStore.getState().conversations.find((c) => c.id === convId);
      const wire =
        conv?.messages.map((m) => ({ role: m.role, content: m.content })) || [];

      const assistantId = addMessage(convId, { role: "assistant", content: "" });
      const controller = new AbortController();
      abortRef.current = controller;

      await streamChat({
        mode,
        messages: wire,
        voice: voice.trained ? voice : null,
        connections,
        signal: controller.signal,
        onMeta: (e) => setEngine(e),
        onDelta: (t) => {
          appendToMessage(convId, assistantId, t);
          scrollToBottom();
        },
        onDone: () => {
          setBusy(false);
          abortRef.current = null;
        },
        onError: (msg) => {
          appendToMessage(convId, assistantId, `\n\n_⚠ ${msg}_`);
          setBusy(false);
          abortRef.current = null;
        },
      });
    },
    [busy, addMessage, appendToMessage, voice, connections, scrollToBottom]
  );

  function startMode(mode: ChatMode, seed?: string) {
    const id = newConversation(mode);
    if (mode === "interview") {
      // seed with the first interview question from the assistant
      const q = INTERVIEW_SEED_QUESTIONS[0];
      addMessage(id, { role: "assistant", content: `Let's find your next great post. ${q}` });
    } else if (mode === "analyze") {
      send("Analyze my recent posts and tell me what to create next.", id, mode);
    } else if (seed) {
      setInput(seed);
    }
  }

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!input.trim()) return;
    if (active) {
      send(input, active.id, active.mode);
    } else {
      const id = newConversation("voice");
      send(input, id, "voice");
    }
  }

  function stop() {
    abortRef.current?.abort();
    setBusy(false);
  }

  if (!hydrated) {
    return <div className="grid h-full place-items-center text-ink-faint">Loading…</div>;
  }

  const recent = conversations.slice(0, 8);

  return (
    <div className="flex h-[calc(100vh-0px)] flex-col lg:h-screen">
      {/* header */}
      <div className="flex items-center justify-between border-b border-line px-5 py-3.5 sm:px-8">
        <div className="flex items-center gap-3">
          {active ? (
            <>
              <ModePill mode={active.mode} />
              <h2 className="max-w-[40vw] truncate text-sm font-medium text-ink-soft">
                {active.title}
              </h2>
            </>
          ) : (
            <h2 className="flex items-center gap-2 text-sm font-medium text-ink-soft">
              <IconSpark width={16} height={16} className="text-brand-300" />
              cre8tor studio
            </h2>
          )}
        </div>
        <div className="flex items-center gap-2">
          {engine && (
            <span className="chip hidden sm:inline-flex">
              <span className={`h-1.5 w-1.5 rounded-full ${engine === "claude" ? "bg-accent-lime" : "bg-accent-warm"}`} />
              {engine === "claude" ? "Claude" : "Demo mode"}
            </span>
          )}
          <button onClick={() => setActive(null)} className="btn-ghost px-3 py-1.5 text-xs">
            <IconPlus width={14} height={14} /> New
          </button>
        </div>
      </div>

      <div className="flex min-h-0 flex-1">
        {/* main column */}
        <div className="flex min-h-0 flex-1 flex-col">
          <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto px-4 py-6 sm:px-8">
            {!active ? (
              <Welcome onPick={startMode} onSeed={(p) => setInput(p)} name={voice.niche} />
            ) : (
              <div className="mx-auto max-w-3xl space-y-5">
                {active.messages.map((m) => (
                  <Message key={m.id} role={m.role} content={m.content} busy={busy} />
                ))}
                {busy && active.messages[active.messages.length - 1]?.content === "" && (
                  <TypingDots />
                )}
              </div>
            )}
          </div>

          {/* composer */}
          <div className="border-t border-line bg-bg/60 px-4 py-4 sm:px-8">
            <form onSubmit={onSubmit} className="mx-auto max-w-3xl">
              {active && <QuickActions mode={active.mode} onSeed={setInput} />}
              <div className="flex items-end gap-2 rounded-2xl border border-line-strong bg-white/[0.03] p-2 focus-within:border-brand-400 focus-within:ring-2 focus-within:ring-brand-500/25">
                <textarea
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.shiftKey) {
                      e.preventDefault();
                      onSubmit(e);
                    }
                  }}
                  rows={1}
                  placeholder={
                    active
                      ? "Reply, or ask for a tweak…"
                      : "What are we creating today?"
                  }
                  className="max-h-40 flex-1 resize-none bg-transparent px-3 py-2.5 text-sm text-ink outline-none placeholder:text-ink-faint"
                />
                {busy ? (
                  <button
                    type="button"
                    onClick={stop}
                    className="btn-ghost h-10 w-10 !rounded-xl !px-0"
                    title="Stop"
                  >
                    <span className="h-3 w-3 rounded-sm bg-ink" />
                  </button>
                ) : (
                  <button
                    type="submit"
                    disabled={!input.trim()}
                    className="btn-primary h-10 w-10 !rounded-xl !px-0"
                  >
                    <IconSend width={17} height={17} />
                  </button>
                )}
              </div>
              <p className="mt-2 text-center text-[11px] text-ink-faint">
                cre8tor tailors everything to your voice profile. Enter to send · Shift+Enter for newline
              </p>
            </form>
          </div>
        </div>

        {/* recent conversations rail */}
        <aside className="hidden w-64 shrink-0 border-l border-line bg-bg-soft/50 xl:block">
          <div className="px-4 py-4">
            <div className="mb-3 text-xs font-semibold uppercase tracking-wide text-ink-faint">
              Recent
            </div>
            {recent.length === 0 ? (
              <p className="text-xs text-ink-faint">Your conversations show up here.</p>
            ) : (
              <div className="space-y-1">
                {recent.map((c) => (
                  <div
                    key={c.id}
                    className={`group flex items-center gap-2 rounded-lg px-2.5 py-2 text-sm ${
                      c.id === activeId ? "bg-white/[0.07]" : "hover:bg-white/[0.04]"
                    }`}
                  >
                    <button
                      onClick={() => setActive(c.id)}
                      className="min-w-0 flex-1 text-left"
                    >
                      <span className="block truncate text-ink-soft">{c.title}</span>
                      <span className="block text-[11px] text-ink-faint">{timeAgo(c.updatedAt)}</span>
                    </button>
                    <button
                      onClick={() => deleteConversation(c.id)}
                      className="opacity-0 transition group-hover:opacity-100"
                    >
                      <IconTrash width={14} height={14} className="text-ink-faint hover:text-red-400" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </aside>
      </div>
    </div>
  );
}

function Welcome({
  onPick,
  onSeed,
}: {
  onPick: (m: ChatMode, seed?: string) => void;
  onSeed: (p: string) => void;
  name?: string;
}) {
  const ideas = [
    "Write a LinkedIn post about a lesson I learned this week",
    "Give me 5 hook ideas for a thread on my niche",
    "Turn my last win into a story-driven post",
    "What should I post today?",
  ];
  return (
    <div className="mx-auto max-w-3xl pt-6">
      <div className="text-center">
        <div className="mx-auto mb-4 grid h-14 w-14 place-items-center rounded-2xl bg-brand-gradient shadow-glow">
          <IconSpark className="text-white" width={26} height={26} />
        </div>
        <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
          What are we creating today?
        </h1>
        <p className="mt-2 text-ink-soft">
          Pick a mode, or just start typing below.
        </p>
      </div>

      <div className="mt-8 grid gap-3 sm:grid-cols-3">
        {MODES.map(({ key, label, sub, Icon, prompt }) => (
          <button
            key={key}
            onClick={() => (key === "voice" ? onSeed(prompt) : onPick(key))}
            className="card group p-5 text-left transition hover:border-brand-500/40 hover:bg-white/[0.04]"
          >
            <span className="grid h-10 w-10 place-items-center rounded-xl bg-white/[0.05] text-brand-300 transition group-hover:bg-brand-500/15">
              <Icon width={20} height={20} />
            </span>
            <div className="mt-3 text-sm font-semibold">{label}</div>
            <div className="mt-0.5 text-xs text-ink-faint">{sub}</div>
          </button>
        ))}
      </div>

      <div className="mt-8">
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-faint">
          Try
        </div>
        <div className="flex flex-wrap gap-2">
          {ideas.map((i) => (
            <button
              key={i}
              onClick={() => onSeed(i)}
              className="chip transition hover:border-brand-500/40 hover:text-ink"
            >
              {i}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function Message({ role, content, busy }: { role: "user" | "assistant"; content: string; busy: boolean }) {
  const isUser = role === "user";
  if (isUser) {
    return (
      <div className="flex justify-end">
        <div className="max-w-[85%] rounded-2xl rounded-br-md bg-brand-600/90 px-4 py-2.5 text-sm text-white shadow-[0_8px_24px_-12px_rgba(99,102,241,0.7)]">
          {content}
        </div>
      </div>
    );
  }
  return (
    <div className="flex gap-3">
      <span className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-brand-gradient text-white">
        <IconSpark width={16} height={16} />
      </span>
      <div className="min-w-0 flex-1">
        <div className="rounded-2xl rounded-tl-md border border-line bg-bg-card px-4 py-3 text-sm text-ink">
          {content ? <Markdown content={content} /> : <span className="text-ink-faint">…</span>}
        </div>
        {content && !busy && <AssistantActions content={content} />}
      </div>
    </div>
  );
}

function AssistantActions({ content }: { content: string }) {
  const addDraft = useStore((s) => s.addDraft);
  const [copied, setCopied] = useState(false);
  const [saved, setSaved] = useState(false);
  const [showPlatforms, setShowPlatforms] = useState(false);

  function copy() {
    navigator.clipboard?.writeText(content);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }
  function save(platform: Platform) {
    addDraft({ body: content, platform, status: "draft" });
    setSaved(true);
    setShowPlatforms(false);
    setTimeout(() => setSaved(false), 1800);
  }

  return (
    <div className="mt-1.5 flex items-center gap-1.5">
      <button
        onClick={copy}
        className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs text-ink-faint hover:bg-white/[0.05] hover:text-ink"
      >
        {copied ? <IconCheck width={13} height={13} className="text-accent-lime" /> : <IconCopy width={13} height={13} />}
        {copied ? "Copied" : "Copy"}
      </button>
      <div className="relative">
        <button
          onClick={() => setShowPlatforms((v) => !v)}
          className="inline-flex items-center gap-1 rounded-lg px-2 py-1 text-xs text-ink-faint hover:bg-white/[0.05] hover:text-ink"
        >
          {saved ? <IconCheck width={13} height={13} className="text-accent-lime" /> : <IconLayers width={13} height={13} />}
          {saved ? "Saved to library" : "Save as draft"}
        </button>
        {showPlatforms && (
          <div className="absolute bottom-full left-0 z-20 mb-1 flex gap-1 rounded-xl border border-line-strong bg-bg-elevated p-1.5 shadow-card">
            {(["linkedin", "x", "instagram"] as Platform[]).map((p) => (
              <button
                key={p}
                onClick={() => save(p)}
                className="grid place-items-center rounded-lg p-1 hover:bg-white/10"
                title={PLATFORM_META[p].label}
              >
                <PlatformBadge platform={p} size={16} />
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function QuickActions({ mode, onSeed }: { mode: ChatMode; onSeed: (s: string) => void }) {
  const map: Record<ChatMode, string[]> = {
    voice: ["Make it punchier", "Shorten for X", "Add a stronger hook", "More story, less list"],
    analyze: ["What's my best format?", "What should I stop doing?", "Give me 3 post ideas"],
    interview: ["Turn this into a post", "Ask me something else", "Go deeper on that"],
    chat: ["Give me a content plan for this week"],
  };
  return (
    <div className="mb-2 flex flex-wrap gap-1.5">
      {map[mode].map((q) => (
        <button
          key={q}
          type="button"
          onClick={() => onSeed(q)}
          className="rounded-full border border-line bg-white/[0.02] px-3 py-1 text-xs text-ink-soft transition hover:border-brand-500/40 hover:text-ink"
        >
          {q}
        </button>
      ))}
    </div>
  );
}

function ModePill({ mode }: { mode: ChatMode }) {
  const meta: Record<ChatMode, { label: string; Icon: (p: any) => JSX.Element }> = {
    voice: { label: "Voice", Icon: IconPen },
    analyze: { label: "Analyze", Icon: IconChart },
    interview: { label: "Interview", Icon: IconMic },
    chat: { label: "Chat", Icon: IconSpark },
  };
  const M = meta[mode];
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-brand-500/15 px-2.5 py-1 text-xs font-medium text-brand-200">
      <M.Icon width={13} height={13} />
      {M.label}
    </span>
  );
}

function TypingDots() {
  return (
    <div className="mx-auto flex max-w-3xl gap-3">
      <span className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-brand-gradient text-white">
        <IconSpark width={16} height={16} />
      </span>
      <div className="flex items-center gap-1 rounded-2xl rounded-tl-md border border-line bg-bg-card px-4 py-4">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="h-2 w-2 rounded-full bg-ink-faint animate-pulse-dot"
            style={{ animationDelay: `${i * 0.15}s` }}
          />
        ))}
      </div>
    </div>
  );
}
