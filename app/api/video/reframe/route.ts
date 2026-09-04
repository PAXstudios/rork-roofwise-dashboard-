import { NextRequest, NextResponse } from "next/server";
import { reframeVideo } from "@/lib/video";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

export async function POST(req: NextRequest) {
  let body: { videoUrl?: string; aspect?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  if (!body.aspect) {
    return NextResponse.json({ ok: false, error: "aspect required" }, { status: 400 });
  }
  const res = await reframeVideo(body.videoUrl || "", body.aspect);
  return NextResponse.json(res);
}
