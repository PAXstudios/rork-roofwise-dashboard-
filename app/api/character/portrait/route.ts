import { NextRequest, NextResponse } from "next/server";
import { generatePortrait } from "@/lib/character";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 180;

// Generates a photoreal avatar portrait for a character via Higgsfield.
// Demo mode returns { url: null } and the client keeps the captured photo
// or the illustrated face.
export async function POST(req: NextRequest) {
  let body: { name?: string; vibe?: string; soulId?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  const res = await generatePortrait({
    name: (body.name || "Creator").slice(0, 40),
    vibe: (body.vibe || "confident, friendly creator").slice(0, 200),
    soulId: body.soulId,
  });
  return NextResponse.json({ ok: true, ...res });
}
