import { NextRequest, NextResponse } from "next/server";
import { hasHeyGen, getVideoStatus } from "@/lib/heygen";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(req: NextRequest) {
  if (!hasHeyGen()) {
    return NextResponse.json({ ok: false, error: "HEYGEN_API_KEY not set" });
  }
  const videoId = req.nextUrl.searchParams.get("video_id");
  if (!videoId) {
    return NextResponse.json({ ok: false, error: "video_id required" }, { status: 400 });
  }
  try {
    const status = await getVideoStatus(videoId);
    return NextResponse.json({ ok: true, ...status });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, error: err?.message || "Status check failed" },
      { status: 502 }
    );
  }
}
