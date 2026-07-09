import Anthropic from "@anthropic-ai/sdk";

export function getModel() {
  return process.env.CRE8TOR_MODEL || "claude-sonnet-5";
}

export function hasApiKey() {
  return Boolean(process.env.ANTHROPIC_API_KEY);
}

let client: Anthropic | null = null;
export function getClient() {
  if (!process.env.ANTHROPIC_API_KEY) return null;
  if (!client) {
    client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  }
  return client;
}

export interface WireMessage {
  role: "user" | "assistant";
  content: string;
}

// Claude's Messages API requires the history to begin with a user turn and to
// alternate roles. Interview mode seeds an assistant question first, so we
// normalize: drop leading assistant turns (folding them into the next user
// turn as context) and merge consecutive same-role turns.
export function normalizeMessages(messages: WireMessage[]): WireMessage[] {
  const cleaned = messages.filter((m) => m.content.trim().length > 0);

  // Collect any leading assistant turns as context to inject into first user turn.
  let lead = "";
  let i = 0;
  while (i < cleaned.length && cleaned[i].role === "assistant") {
    lead += (lead ? "\n\n" : "") + cleaned[i].content;
    i++;
  }
  const rest = cleaned.slice(i);
  if (rest.length === 0) {
    // Only assistant turns existed — turn them into a user prompt.
    return [{ role: "user", content: lead || "Let's begin." }];
  }
  if (lead) {
    rest[0] = {
      role: "user",
      content: `[Earlier, you said: "${lead}"]\n\n${rest[0].content}`,
    };
  }

  // Merge consecutive same-role turns.
  const merged: WireMessage[] = [];
  for (const m of rest) {
    const last = merged[merged.length - 1];
    if (last && last.role === m.role) last.content += "\n\n" + m.content;
    else merged.push({ ...m });
  }
  return merged;
}

// Stream text tokens from Claude. Yields plain text chunks.
export async function* streamCompletion(
  system: string,
  messages: WireMessage[]
): AsyncGenerator<string> {
  const c = getClient();
  if (!c) throw new Error("NO_API_KEY");

  const normalized = normalizeMessages(messages);
  const stream = await c.messages.stream({
    model: getModel(),
    max_tokens: 1500,
    system,
    messages: normalized.map((m) => ({ role: m.role, content: m.content })),
  });

  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "text_delta"
    ) {
      yield event.delta.text;
    }
  }
}
