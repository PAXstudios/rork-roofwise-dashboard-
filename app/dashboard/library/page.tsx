"use client";

import { useMemo, useState } from "react";
import { useStore } from "@/lib/store";
import type { Draft, DraftStatus, Platform } from "@/lib/types";
import { useHydrated, timeAgo, compact } from "@/lib/hooks";
import { PlatformBadge, PLATFORM_META } from "@/components/platform";
import {
  IconPlus,
  IconPen,
  IconCopy,
  IconTrash,
  IconCheck,
  IconX,
  IconLayers,
} from "@/components/Icons";

type Filter = "all" | DraftStatus;

const FILTERS: { key: Filter; label: string }[] = [
  { key: "all", label: "All" },
  { key: "idea", label: "Ideas" },
  { key: "draft", label: "Drafts" },
  { key: "scheduled", label: "Scheduled" },
  { key: "published", label: "Published" },
];

const STATUS_STYLE: Record<DraftStatus, string> = {
  idea: "border-accent/30 bg-accent/10 text-accent",
  draft: "border-brand-400/30 bg-brand-500/10 text-brand-300",
  scheduled: "border-amber-400/30 bg-amber-400/10 text-amber-300",
  published: "border-emerald-400/30 bg-emerald-400/10 text-emerald-300",
};

const STATUS_LABEL: Record<DraftStatus, string> = {
  idea: "Idea",
  draft: "Draft",
  scheduled: "Scheduled",
  published: "Published",
};

const STATUS_FLOW: DraftStatus[] = ["idea", "draft", "scheduled", "published"];
const PLATFORMS: Platform[] = ["linkedin", "instagram", "x", "tiktok", "youtube"];

export default function LibraryPage() {
  const hydrated = useHydrated();
  const drafts = useStore((s) => s.drafts);
  const addDraft = useStore((s) => s.addDraft);
  const updateDraft = useStore((s) => s.updateDraft);
  const deleteDraft = useStore((s) => s.deleteDraft);
  const setDraftStatus = useStore((s) => s.setDraftStatus);

  const [filter, setFilter] = useState<Filter>("all");
  const [editingId, setEditingId] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const counts = useMemo(() => {
    const c: Record<Filter, number> = {
      all: drafts.length,
      idea: 0,
      draft: 0,
      scheduled: 0,
      published: 0,
    };
    drafts.forEach((d) => (c[d.status] += 1));
    return c;
  }, [drafts]);

  const visible = useMemo(
    () =>
      filter === "all" ? drafts : drafts.filter((d) => d.status === filter),
    [drafts, filter]
  );

  const editing = drafts.find((d) => d.id === editingId) || null;

  function handleNew() {
    const d = addDraft({ body: "", platform: "linkedin", status: "draft" });
    setEditingId(d.id);
  }

  async function copyBody(d: Draft) {
    try {
      await navigator.clipboard.writeText(d.body);
      setCopiedId(d.id);
      setTimeout(() => setCopiedId((c) => (c === d.id ? null : c)), 1500);
    } catch {
      /* clipboard unavailable */
    }
  }

  function cycleStatus(d: Draft) {
    const next =
      STATUS_FLOW[(STATUS_FLOW.indexOf(d.status) + 1) % STATUS_FLOW.length];
    const scheduledAt =
      next === "scheduled"
        ? d.scheduledAt || Date.now() + 86_400_000
        : d.scheduledAt;
    setDraftStatus(d.id, next, scheduledAt);
  }

  if (!hydrated) {
    return (
      <div className="space-y-6">
        <div className="h-10 w-40 shimmer rounded-xl bg-white/[0.04]" />
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="h-52 shimmer rounded-2xl border border-line bg-white/[0.02]"
            />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
            Library
          </h1>
          <p className="mt-1 text-sm text-ink-soft">
            Every idea, draft, and post you&apos;ve shipped with cre8tor.
          </p>
        </div>
        <button className="btn-primary" onClick={handleNew}>
          <IconPlus width={16} height={16} />
          New draft
        </button>
      </header>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((f) => {
          const active = filter === f.key;
          return (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`inline-flex items-center gap-2 rounded-full border px-4 py-1.5 text-sm font-medium transition ${
                active
                  ? "border-brand-400/40 bg-brand-500/15 text-ink"
                  : "border-line-strong bg-white/[0.02] text-ink-soft hover:text-ink"
              }`}
            >
              {f.label}
              <span
                className={`rounded-full px-1.5 text-xs ${
                  active ? "bg-brand-500/30 text-brand-100" : "bg-white/[0.06] text-ink-faint"
                }`}
              >
                {counts[f.key]}
              </span>
            </button>
          );
        })}
      </div>

      {visible.length === 0 ? (
        <div className="card flex flex-col items-center justify-center gap-3 px-6 py-16 text-center">
          <span className="grid h-12 w-12 place-items-center rounded-2xl bg-brand-500/10 text-brand-300">
            <IconLayers width={22} height={22} />
          </span>
          <h3 className="text-lg font-semibold">Nothing here yet</h3>
          <p className="max-w-sm text-sm text-ink-soft">
            {filter === "all"
              ? "Start a new draft and it will show up in your library."
              : `You have no ${filter} items. Move a draft here or create something new.`}
          </p>
          <button className="btn-ghost mt-1" onClick={handleNew}>
            <IconPlus width={16} height={16} />
            New draft
          </button>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {visible.map((d) => (
            <DraftCard
              key={d.id}
              draft={d}
              copied={copiedId === d.id}
              onEdit={() => setEditingId(d.id)}
              onCopy={() => copyBody(d)}
              onCycle={() => cycleStatus(d)}
              onDelete={() => {
                if (confirm("Delete this draft? This cannot be undone.")) {
                  deleteDraft(d.id);
                }
              }}
            />
          ))}
        </div>
      )}

      {editing && (
        <DraftEditor
          draft={editing}
          onClose={() => setEditingId(null)}
          onSave={(patch) => {
            updateDraft(editing.id, patch);
            setEditingId(null);
          }}
        />
      )}
    </div>
  );
}

function DraftCard({
  draft,
  copied,
  onEdit,
  onCopy,
  onCycle,
  onDelete,
}: {
  draft: Draft;
  copied: boolean;
  onEdit: () => void;
  onCopy: () => void;
  onCycle: () => void;
  onDelete: () => void;
}) {
  return (
    <article className="card flex flex-col gap-3 p-4 transition hover:border-line-strong">
      <div className="flex items-center justify-between gap-2">
        <PlatformBadge platform={draft.platform} size={16} />
        <button
          onClick={onCycle}
          title="Advance status"
          className={`rounded-full border px-2.5 py-0.5 text-xs font-medium ${STATUS_STYLE[draft.status]}`}
        >
          {STATUS_LABEL[draft.status]}
        </button>
      </div>

      <div>
        <h3 className="line-clamp-1 font-semibold">
          {draft.title || "Untitled"}
        </h3>
        <p className="mt-1 line-clamp-3 whitespace-pre-wrap text-sm text-ink-soft">
          {draft.body || "No content yet — click edit to start writing."}
        </p>
      </div>

      {draft.tags.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {draft.tags.map((t) => (
            <span key={t} className="chip">
              #{t}
            </span>
          ))}
        </div>
      )}

      {draft.status === "published" && draft.metrics && (
        <div className="flex gap-4 rounded-xl border border-line bg-white/[0.02] px-3 py-2 text-xs text-ink-soft">
          <span>
            <span className="font-semibold text-ink">
              {compact(draft.metrics.impressions)}
            </span>{" "}
            impressions
          </span>
          <span>
            <span className="font-semibold text-ink">
              {compact(draft.metrics.likes)}
            </span>{" "}
            likes
          </span>
        </div>
      )}

      <div className="mt-auto flex items-center justify-between border-t border-line pt-3">
        <span className="text-xs text-ink-faint">
          {draft.status === "scheduled" && draft.scheduledAt
            ? `Scheduled ${new Date(draft.scheduledAt).toLocaleDateString(undefined, { month: "short", day: "numeric" })}`
            : `Updated ${timeAgo(draft.updatedAt)}`}
        </span>
        <div className="flex items-center gap-1">
          <IconBtn label="Edit" onClick={onEdit}>
            <IconPen width={15} height={15} />
          </IconBtn>
          <IconBtn label={copied ? "Copied" : "Copy body"} onClick={onCopy}>
            {copied ? (
              <IconCheck width={15} height={15} className="text-emerald-400" />
            ) : (
              <IconCopy width={15} height={15} />
            )}
          </IconBtn>
          <IconBtn label="Delete" onClick={onDelete} danger>
            <IconTrash width={15} height={15} />
          </IconBtn>
        </div>
      </div>
    </article>
  );
}

function IconBtn({
  children,
  label,
  onClick,
  danger,
}: {
  children: React.ReactNode;
  label: string;
  onClick: () => void;
  danger?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      className={`grid h-8 w-8 place-items-center rounded-lg border border-line-strong bg-white/[0.02] text-ink-soft transition hover:bg-white/[0.06] ${
        danger ? "hover:border-red-500/40 hover:text-red-400" : "hover:text-ink"
      }`}
    >
      {children}
    </button>
  );
}

function DraftEditor({
  draft,
  onClose,
  onSave,
}: {
  draft: Draft;
  onClose: () => void;
  onSave: (patch: Partial<Draft>) => void;
}) {
  const [title, setTitle] = useState(draft.title);
  const [body, setBody] = useState(draft.body);
  const [platform, setPlatform] = useState<Platform>(draft.platform);
  const [tags, setTags] = useState(draft.tags.join(", "));

  function save() {
    onSave({
      title: title.trim() || body.split("\n")[0].slice(0, 60) || "Untitled",
      body,
      platform,
      tags: tags
        .split(",")
        .map((t) => t.trim().replace(/^#/, ""))
        .filter(Boolean),
    });
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-0 backdrop-blur-sm sm:items-center sm:p-6"
      onClick={onClose}
    >
      <div
        className="card flex max-h-[92vh] w-full max-w-2xl flex-col overflow-hidden rounded-t-3xl sm:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-line px-5 py-4">
          <h2 className="text-lg font-semibold">Edit draft</h2>
          <button
            onClick={onClose}
            aria-label="Close"
            className="grid h-8 w-8 place-items-center rounded-lg text-ink-soft transition hover:bg-white/[0.06] hover:text-ink"
          >
            <IconX width={18} height={18} />
          </button>
        </div>

        <div className="space-y-4 overflow-y-auto px-5 py-5">
          <div>
            <label className="label">Title</label>
            <input
              className="input"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Give it a working title"
            />
          </div>

          <div>
            <label className="label">Platform</label>
            <div className="flex flex-wrap gap-2">
              {PLATFORMS.map((p) => {
                const active = platform === p;
                return (
                  <button
                    key={p}
                    onClick={() => setPlatform(p)}
                    className={`inline-flex items-center gap-2 rounded-xl border px-3 py-2 text-sm transition ${
                      active
                        ? "border-brand-400/50 bg-brand-500/10 text-ink"
                        : "border-line-strong bg-white/[0.02] text-ink-soft hover:text-ink"
                    }`}
                  >
                    <PlatformBadge platform={p} size={14} />
                    {PLATFORM_META[p].label}
                  </button>
                );
              })}
            </div>
          </div>

          <div>
            <label className="label">Body</label>
            <textarea
              className="input min-h-[180px] resize-y leading-relaxed"
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="Write your post…"
            />
            <p className="mt-1 text-xs text-ink-faint">
              {body.length} characters
            </p>
          </div>

          <div>
            <label className="label">Tags</label>
            <input
              className="input"
              value={tags}
              onChange={(e) => setTags(e.target.value)}
              placeholder="growth, hooks, systems"
            />
            <p className="mt-1 text-xs text-ink-faint">Comma separated.</p>
          </div>
        </div>

        <div className="flex items-center justify-end gap-2 border-t border-line px-5 py-4">
          <button className="btn-ghost" onClick={onClose}>
            Cancel
          </button>
          <button className="btn-primary" onClick={save}>
            <IconCheck width={16} height={16} />
            Save draft
          </button>
        </div>
      </div>
    </div>
  );
}
