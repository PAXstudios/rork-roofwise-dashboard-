"use client";

import type { ChatMode, VoiceProfile, Connection } from "./types";
import type { WireMessage } from "./ai";

interface StreamArgs {
  mode: ChatMode;
  messages: WireMessage[];
  voice: VoiceProfile | null;
  connections: Connection[];
  onMeta?: (engine: string) => void;
  onDelta: (text: string) => void;
  onDone: () => void;
  onError: (msg: string) => void;
  signal?: AbortSignal;
}

export async function streamChat({
  mode,
  messages,
  voice,
  connections,
  onMeta,
  onDelta,
  onDone,
  onError,
  signal,
}: StreamArgs) {
  try {
    const res = await fetch("/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode, messages, voice, connections }),
      signal,
    });
    if (!res.ok || !res.body) {
      onError(`Request failed (${res.status})`);
      return;
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split("\n\n");
      buffer = parts.pop() || "";
      for (const part of parts) {
        const line = part.trim();
        if (!line.startsWith("data:")) continue;
        const json = line.slice(5).trim();
        if (!json) continue;
        try {
          const evt = JSON.parse(json);
          if (evt.type === "meta") onMeta?.(evt.engine);
          else if (evt.type === "delta") onDelta(evt.text);
          else if (evt.type === "done") onDone();
          else if (evt.type === "error") onError(evt.message);
        } catch {
          /* ignore malformed */
        }
      }
    }
    onDone();
  } catch (err: any) {
    if (err?.name === "AbortError") return;
    onError(err?.message || "Network error");
  }
}
