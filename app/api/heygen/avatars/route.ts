import { NextResponse } from "next/server";
import { hasHeyGen, listAvatars } from "@/lib/heygen";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Lists HeyGen stock avatars (real human presenters) for the character library.
export async function GET() {
  if (!hasHeyGen()) {
    return NextResponse.json({ ok: false, configured: false, avatars: [] });
  }
  try {
    const avatars = await listAvatars(60);
    return NextResponse.json({
      ok: true,
      configured: true,
      avatars: avatars.map((a) => ({
        id: a.avatar_id,
        name: a.avatar_name,
        gender: a.gender,
        preview: a.preview_image_url,
        previewVideo: a.preview_video_url,
        premium: a.premium,
      })),
    });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, configured: true, avatars: [], error: err?.message || "HeyGen error" },
      { status: 502 }
    );
  }
}
