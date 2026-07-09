import { NextRequest, NextResponse } from "next/server";
import { publishPost } from "@/lib/publish";
import type { Platform } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Deterministic-ish demo metrics seeded from the text so a published post gets
// plausible early numbers immediately.
function demoMetrics(text: string) {
  let h = 0;
  for (let i = 0; i < text.length; i++) h = (h * 31 + text.charCodeAt(i)) >>> 0;
  const impressions = 800 + (h % 4200);
  return {
    impressions,
    likes: Math.floor(impressions * 0.04),
    comments: Math.floor(impressions * 0.008),
  };
}

export async function POST(req: NextRequest) {
  let body: { platform?: Platform; text?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  const { platform, text } = body;
  if (!platform || !text?.trim()) {
    return NextResponse.json({ ok: false, error: "platform and text are required" }, { status: 400 });
  }

  const result = await publishPost(platform, text);
  return NextResponse.json({
    ...result,
    metrics: result.ok ? demoMetrics(text) : undefined,
  });
}
