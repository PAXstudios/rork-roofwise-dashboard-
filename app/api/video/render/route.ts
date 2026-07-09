import { NextRequest, NextResponse } from "next/server";
import { renderVideo, renderViaHiggsfieldCli, cliRenderEnabled } from "@/lib/video";
import type { VideoKind, VideoScene } from "@/lib/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
// Rendering multiple clips can take minutes; allow a long budget.
export const maxDuration = 300;

// Submits a storyboard to Higgsfield for real MP4 clips (one per scene). Without
// HF_CREDENTIALS this returns { clips: [] } and the client keeps using the
// in-browser preview player.
export async function POST(req: NextRequest) {
  let body: { kind?: VideoKind; scenes?: VideoScene[]; aspect?: string; maxScenes?: number };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  if (!body.kind || !Array.isArray(body.scenes) || body.scenes.length === 0) {
    return NextResponse.json({ ok: false, error: "kind and scenes required" }, { status: 400 });
  }

  const result = cliRenderEnabled()
    ? await renderViaHiggsfieldCli(body.scenes, {
        aspect: body.aspect,
        maxScenes: body.maxScenes,
      })
    : await renderVideo(body.kind, body.scenes, {
        aspect: body.aspect,
        maxScenes: body.maxScenes,
      });

  return NextResponse.json({
    ok: result.clips.length > 0,
    clips: result.clips,
    engine: result.engine,
    provider: result.engine === "higgsfield" ? "higgsfield" : undefined,
    error: result.error,
  });
}
