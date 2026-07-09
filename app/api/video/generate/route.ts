import { NextRequest, NextResponse } from "next/server";
import { generateStoryboard, hasRenderProvider, type StoryboardInput } from "@/lib/video";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  let input: StoryboardInput;
  try {
    input = (await req.json()) as StoryboardInput;
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request" }, { status: 400 });
  }
  if (!input.prompt?.trim()) {
    return NextResponse.json({ ok: false, error: "A prompt is required" }, { status: 400 });
  }

  const board = await generateStoryboard(input);
  return NextResponse.json({
    ok: true,
    title: board.title,
    scenes: board.scenes,
    engine: board.engine,
    canRender: hasRenderProvider(input.kind),
  });
}
