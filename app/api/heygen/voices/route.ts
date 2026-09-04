import { NextRequest, NextResponse } from "next/server";
import { hasHeyGen, listVoices } from "@/lib/heygen";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

// Lists HeyGen voices for the voice picker — including any custom / cloned
// voices on the account. Supports ?language= and ?q= filters, ?limit=.
export async function GET(req: NextRequest) {
  if (!hasHeyGen()) {
    return NextResponse.json({ ok: false, configured: false, voices: [], languages: [] });
  }
  try {
    const all = await listVoices();
    const languages = Array.from(new Set(all.map((v) => v.language).filter(Boolean))).sort();

    const language = req.nextUrl.searchParams.get("language");
    const q = (req.nextUrl.searchParams.get("q") || "").toLowerCase().trim();
    const limit = Math.min(Number(req.nextUrl.searchParams.get("limit")) || 60, 200);

    let filtered = all;
    if (language) filtered = filtered.filter((v) => v.language === language);
    if (q) filtered = filtered.filter((v) => v.name.toLowerCase().includes(q));

    return NextResponse.json({
      ok: true,
      configured: true,
      total: all.length,
      languages,
      voices: filtered.slice(0, limit).map((v) => ({
        id: v.voice_id,
        name: v.name.trim(),
        language: v.language,
        gender: v.gender,
        preview: v.preview_audio,
        emotion: v.emotion_support,
      })),
    });
  } catch (err: any) {
    return NextResponse.json(
      { ok: false, configured: true, voices: [], languages: [], error: err?.message },
      { status: 502 }
    );
  }
}
