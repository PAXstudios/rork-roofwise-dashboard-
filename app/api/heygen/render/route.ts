import { NextRequest, NextResponse } from "next/server";
import { hasHeyGen, generateUgcVideo } from "@/lib/heygen";
import type { VideoScene } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

// Submits a UGC render to HeyGen: the storyboard's voiceover lines become the
// avatar's spoken script. Returns a video id to poll via /api/heygen/status.
export async function POST(req: NextRequest) {
  if (!hasHeyGen()) {
    return NextResponse.json({ ok: false, configured: false, error: "HEYGEN_API_KEY not set" });
  }
  let body: {
    scenes?: VideoScene[];
    script?: string;
    aspect?: string;
    avatarId?: string;
    talkingPhotoId?: string;
    voiceId?: string;
    gender?: string | null;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }

  const script =
    body.script?.trim() ||
    (body.scenes || [])
      .map((s) => s.voiceover?.trim())
      .filter(Boolean)
      .join(" ");
  if (!script) {
    return NextResponse.json({ ok: false, error: "No script to speak" }, { status: 400 });
  }
  if (!body.avatarId && !body.talkingPhotoId) {
    return NextResponse.json(
      { ok: false, error: "Pick a HeyGen character (avatarId or talkingPhotoId)" },
      { status: 400 }
    );
  }

  try {
    const { videoId } = await generateUgcVideo({
      script,
      aspect: body.aspect || "9:16",
      avatarId: body.avatarId,
      talkingPhotoId: body.talkingPhotoId,
      voiceId: body.voiceId,
      gender: body.gender,
    });
    return NextResponse.json({ ok: true, videoId });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, error: err?.message || "HeyGen render failed" },
      { status: 502 }
    );
  }
}
