import { NextRequest } from "next/server";
import { hasApiKey, streamCompletion, type WireMessage } from "@/lib/ai";
import { voiceSystemPrompt, modeIntro, analyzeContext } from "@/lib/prompts";
import { demoReply } from "@/lib/demoEngine";
import type { ChatMode, VoiceProfile, Connection } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface Body {
  mode: ChatMode;
  messages: WireMessage[];
  voice: VoiceProfile | null;
  connections: Connection[];
}

function sse(obj: unknown) {
  return `data: ${JSON.stringify(obj)}\n\n`;
}

export async function POST(req: NextRequest) {
  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  const { mode, messages, voice, connections } = body;

  // Assemble the system prompt from voice profile + mode + (for analyze) data
  let system = voiceSystemPrompt(voice);
  system += `\n\n${modeIntro(mode)}`;
  if (mode === "analyze") {
    system += `\n\n${analyzeContext(connections || [])}`;
  }

  const encoder = new TextEncoder();
  const usingReal = hasApiKey();

  const stream = new ReadableStream({
    async start(controller) {
      controller.enqueue(encoder.encode(sse({ type: "meta", engine: usingReal ? "claude" : "demo" })));
      try {
        if (usingReal) {
          for await (const chunk of streamCompletion(system, messages)) {
            controller.enqueue(encoder.encode(sse({ type: "delta", text: chunk })));
          }
        } else {
          // Demo mode — stream a rich canned response word-by-word.
          const lastUser = [...messages].reverse().find((m) => m.role === "user");
          const assistantTurns = messages.filter((m) => m.role === "assistant").length;
          const text = demoReply(mode, lastUser?.content || "", assistantTurns);
          const tokens = text.split(/(\s+)/);
          for (const t of tokens) {
            controller.enqueue(encoder.encode(sse({ type: "delta", text: t })));
            // tiny delay to simulate streaming
            await new Promise((r) => setTimeout(r, 12));
          }
        }
        controller.enqueue(encoder.encode(sse({ type: "done" })));
      } catch (err: any) {
        controller.enqueue(
          encoder.encode(sse({ type: "error", message: err?.message || "Generation failed" }))
        );
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
