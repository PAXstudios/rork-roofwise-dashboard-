"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";
import type {
  User,
  VoiceProfile,
  Connection,
  Draft,
  Conversation,
  ChatMessage,
  ChatMode,
  Platform,
  DraftStatus,
  VideoProject,
  Character,
  EditProject,
} from "./types";
import {
  seedConnections,
  seedDrafts,
  seedVideos,
  seedCharacters,
  DEMO_ACCENTS,
} from "./seed";

function uid(prefix = "id") {
  // Avoid Math.random for hydration stability where it matters; here it's only
  // called from event handlers (client-only) so it's safe.
  return `${prefix}-${Math.random().toString(36).slice(2, 10)}`;
}

export const emptyVoice: VoiceProfile = {
  bio: "",
  niche: "",
  audience: "",
  tone: { formal: 35, playful: 55, bold: 60, technical: 40 },
  favoriteWords: [],
  avoidWords: [],
  emojiUsage: "light",
  samples: [],
  goals: [],
  trained: false,
};

interface AppState {
  hydrated: boolean;
  user: User | null;
  voice: VoiceProfile;
  connections: Connection[];
  drafts: Draft[];
  conversations: Conversation[];
  activeConversationId: string | null;
  videos: VideoProject[];
  characters: Character[];
  editProjects: EditProject[];

  // auth
  signup: (name: string, email: string) => void;
  login: (email: string) => void;
  logout: () => void;
  completeOnboarding: () => void;

  // voice
  updateVoice: (patch: Partial<VoiceProfile>) => void;
  trainVoice: () => void;

  // connections
  toggleConnection: (platform: Platform, handle?: string) => void;

  // drafts
  addDraft: (d: Partial<Draft> & { body: string; platform: Platform }) => Draft;
  updateDraft: (id: string, patch: Partial<Draft>) => void;
  deleteDraft: (id: string) => void;
  setDraftStatus: (id: string, status: DraftStatus, scheduledAt?: number) => void;
  markPublished: (
    id: string,
    info: { publishedUrl?: string; engine: "live" | "demo"; metrics?: Draft["metrics"] }
  ) => void;

  // videos
  addVideo: (v: VideoProject) => void;
  updateVideo: (id: string, patch: Partial<VideoProject>) => void;
  deleteVideo: (id: string) => void;

  // characters
  addCharacter: (c: Character) => void;
  updateCharacter: (id: string, patch: Partial<Character>) => void;
  deleteCharacter: (id: string) => void;

  // video editor projects
  addEditProject: (e: EditProject) => void;
  updateEditProject: (id: string, patch: Partial<EditProject>) => void;
  deleteEditProject: (id: string) => void;

  // conversations
  newConversation: (mode: ChatMode) => string;
  setActiveConversation: (id: string | null) => void;
  addMessage: (conversationId: string, msg: Omit<ChatMessage, "id" | "createdAt">) => string;
  appendToMessage: (conversationId: string, messageId: string, chunk: string) => void;
  renameConversation: (id: string, title: string) => void;
  deleteConversation: (id: string) => void;
  resetDemo: () => void;
}

export const useStore = create<AppState>()(
  persist(
    (set, get) => ({
      hydrated: false,
      user: null,
      voice: emptyVoice,
      connections: seedConnections,
      drafts: seedDrafts,
      conversations: [],
      activeConversationId: null,
      videos: seedVideos,
      characters: seedCharacters,
      editProjects: [],

      signup: (name, email) => {
        const accent = DEMO_ACCENTS[name.length % DEMO_ACCENTS.length];
        set({
          user: {
            id: uid("user"),
            name,
            email,
            avatarColor: accent,
            plan: "trial",
            createdAt: Date.now(),
            onboarded: false,
          },
        });
      },
      login: (email) => {
        const existing = get().user;
        if (existing && existing.email === email) return;
        const name = email.split("@")[0].replace(/[._]/g, " ");
        set({
          user: {
            id: uid("user"),
            name: name.replace(/\b\w/g, (c) => c.toUpperCase()),
            email,
            avatarColor: DEMO_ACCENTS[email.length % DEMO_ACCENTS.length],
            plan: "creator",
            createdAt: Date.now(),
            onboarded: get().voice.trained,
          },
        });
      },
      logout: () => set({ user: null, activeConversationId: null }),
      completeOnboarding: () =>
        set((s) => (s.user ? { user: { ...s.user, onboarded: true } } : {})),

      updateVoice: (patch) => set((s) => ({ voice: { ...s.voice, ...patch } })),
      trainVoice: () => set((s) => ({ voice: { ...s.voice, trained: true } })),

      toggleConnection: (platform, handle) =>
        set((s) => ({
          connections: s.connections.map((c) =>
            c.platform === platform
              ? c.connected
                ? { ...c, connected: false, connectedAt: undefined }
                : {
                    ...c,
                    connected: true,
                    handle: handle || c.handle || `@your_${platform}`,
                    followers: c.followers ?? Math.floor(1000 + Math.random() * 40000),
                    connectedAt: Date.now(),
                  }
              : c
          ),
        })),

      addDraft: (d) => {
        const now = Date.now();
        const draft: Draft = {
          id: uid("draft"),
          title: d.title || d.body.split("\n")[0].slice(0, 60) || "Untitled",
          body: d.body,
          platform: d.platform,
          status: d.status || "draft",
          createdAt: now,
          updatedAt: now,
          scheduledAt: d.scheduledAt,
          tags: d.tags || [],
        };
        set((s) => ({ drafts: [draft, ...s.drafts] }));
        return draft;
      },
      updateDraft: (id, patch) =>
        set((s) => ({
          drafts: s.drafts.map((d) =>
            d.id === id ? { ...d, ...patch, updatedAt: Date.now() } : d
          ),
        })),
      deleteDraft: (id) =>
        set((s) => ({ drafts: s.drafts.filter((d) => d.id !== id) })),
      setDraftStatus: (id, status, scheduledAt) =>
        set((s) => ({
          drafts: s.drafts.map((d) =>
            d.id === id ? { ...d, status, scheduledAt, updatedAt: Date.now() } : d
          ),
        })),
      markPublished: (id, info) =>
        set((s) => ({
          drafts: s.drafts.map((d) =>
            d.id === id
              ? {
                  ...d,
                  status: "published",
                  publishedAt: Date.now(),
                  publishedUrl: info.publishedUrl,
                  publishEngine: info.engine,
                  metrics: info.metrics ?? d.metrics,
                  updatedAt: Date.now(),
                }
              : d
          ),
        })),

      addVideo: (v) => set((s) => ({ videos: [v, ...s.videos] })),
      updateVideo: (id, patch) =>
        set((s) => ({
          videos: s.videos.map((v) =>
            v.id === id ? { ...v, ...patch, updatedAt: Date.now() } : v
          ),
        })),
      deleteVideo: (id) =>
        set((s) => ({ videos: s.videos.filter((v) => v.id !== id) })),

      addCharacter: (c) => set((s) => ({ characters: [c, ...s.characters] })),
      updateCharacter: (id, patch) =>
        set((s) => ({
          characters: s.characters.map((c) => (c.id === id ? { ...c, ...patch } : c)),
        })),
      deleteCharacter: (id) =>
        set((s) => ({ characters: s.characters.filter((c) => c.id !== id) })),

      addEditProject: (e) => set((s) => ({ editProjects: [e, ...s.editProjects] })),
      updateEditProject: (id, patch) =>
        set((s) => ({
          editProjects: s.editProjects.map((e) =>
            e.id === id ? { ...e, ...patch, updatedAt: Date.now() } : e
          ),
        })),
      deleteEditProject: (id) =>
        set((s) => ({ editProjects: s.editProjects.filter((e) => e.id !== id) })),

      newConversation: (mode) => {
        const id = uid("conv");
        const titles: Record<ChatMode, string> = {
          voice: "Write in my voice",
          analyze: "Analyze my posts",
          interview: "Interview me",
          chat: "New chat",
        };
        const conv: Conversation = {
          id,
          title: titles[mode],
          mode,
          messages: [],
          createdAt: Date.now(),
          updatedAt: Date.now(),
        };
        set((s) => ({
          conversations: [conv, ...s.conversations],
          activeConversationId: id,
        }));
        return id;
      },
      setActiveConversation: (id) => set({ activeConversationId: id }),
      addMessage: (conversationId, msg) => {
        const id = uid("msg");
        set((s) => ({
          conversations: s.conversations.map((c) =>
            c.id === conversationId
              ? {
                  ...c,
                  updatedAt: Date.now(),
                  title:
                    c.messages.length === 0 && msg.role === "user"
                      ? msg.content.slice(0, 40)
                      : c.title,
                  messages: [
                    ...c.messages,
                    { ...msg, id, createdAt: Date.now() },
                  ],
                }
              : c
          ),
        }));
        return id;
      },
      appendToMessage: (conversationId, messageId, chunk) =>
        set((s) => ({
          conversations: s.conversations.map((c) =>
            c.id === conversationId
              ? {
                  ...c,
                  messages: c.messages.map((m) =>
                    m.id === messageId ? { ...m, content: m.content + chunk } : m
                  ),
                }
              : c
          ),
        })),
      renameConversation: (id, title) =>
        set((s) => ({
          conversations: s.conversations.map((c) =>
            c.id === id ? { ...c, title } : c
          ),
        })),
      deleteConversation: (id) =>
        set((s) => ({
          conversations: s.conversations.filter((c) => c.id !== id),
          activeConversationId:
            s.activeConversationId === id ? null : s.activeConversationId,
        })),

      resetDemo: () =>
        set({
          voice: emptyVoice,
          connections: seedConnections,
          drafts: seedDrafts,
          conversations: [],
          activeConversationId: null,
          videos: seedVideos,
          characters: seedCharacters,
          editProjects: [],
        }),
    }),
    {
      name: "cre8tor-store",
      onRehydrateStorage: () => (state) => {
        if (state) state.hydrated = true;
      },
    }
  )
);
