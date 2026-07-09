import { NextRequest, NextResponse } from "next/server";
import { scoreVideo } from "@/lib/score";
import type { VideoScene } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 120;

export async function POST(req: NextRequest) {
  let body: { scenes?: VideoScene[]; videoUrl?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  const score = await scoreVideo({ scenes: body.scenes, videoUrl: body.videoUrl });
  return NextResponse.json({ ok: true, score });
}
