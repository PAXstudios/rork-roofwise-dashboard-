import { NextRequest, NextResponse } from "next/server";
import { demoTranscript, transcribeReal } from "@/lib/transcribe";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  let body: { durationSec?: number; fileUrl?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  const duration = Math.max(6, Math.min(180, Math.round(body.durationSec || 30)));

  const real = body.fileUrl ? await transcribeReal(body.fileUrl) : null;
  const segments = real ?? demoTranscript(duration);
  return NextResponse.json({
    ok: true,
    engine: real ? "whisper" : "demo",
    segments,
  });
}
