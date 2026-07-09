import { NextRequest, NextResponse } from "next/server";
import { trainSoul } from "@/lib/character";
import { cliRenderEnabled } from "@/lib/video";
import { hasHeyGen, uploadTalkingPhoto } from "@/lib/heygen";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

// Accepts { name, images: dataURL[] }. Preferred path: with HEYGEN_API_KEY the
// best capture becomes a HeyGen "talking photo" — a real presenting avatar of
// the user's face. Higgsfield Soul training runs via CLI when enabled. Demo
// mode returns a simulated id.
export async function POST(req: NextRequest) {
  let body: { name?: string; images?: string[] };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  const name = (body.name || "My character").slice(0, 40);
  const images = body.images || [];

  // HeyGen talking photo — turns the captured face into a speaking UGC avatar.
  if (hasHeyGen() && images.length) {
    try {
      const { talkingPhotoId } = await uploadTalkingPhoto(images[0]);
      return NextResponse.json({
        ok: true,
        engine: "heygen",
        talkingPhotoId,
        soulId: undefined,
      });
    } catch (err: any) {
      // fall through to the other engines, but surface the reason
      console.error("HeyGen talking photo failed:", err?.message);
    }
  }

  let paths: string[] = [];
  const tmp: string[] = [];
  if (cliRenderEnabled() && images.length) {
    try {
      const fs = await import("node:fs/promises");
      const os = await import("node:os");
      const path = await import("node:path");
      for (let i = 0; i < Math.min(images.length, 20); i++) {
        const m = images[i].match(/^data:(image\/\w+);base64,(.+)$/);
        if (!m) continue;
        const ext = m[1].split("/")[1] || "png";
        const file = path.join(os.tmpdir(), `soul-${Date.now()}-${i}.${ext}`);
        await fs.writeFile(file, Buffer.from(m[2], "base64"));
        tmp.push(file);
        paths.push(file);
      }
    } catch {
      paths = [];
    }
  }

  const result = await trainSoul(name, paths);

  // best-effort cleanup
  try {
    const fs = await import("node:fs/promises");
    await Promise.all(tmp.map((f) => fs.unlink(f).catch(() => {})));
  } catch {
    /* ignore */
  }

  return NextResponse.json(result);
}
