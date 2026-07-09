import { cliRenderEnabled, hfCredentials } from "./video";

// Trains a face-faithful Higgsfield "Soul" character from uploaded photos and
// returns a reusable reference id. When the authenticated CLI is available
// (HIGGSFIELD_USE_CLI=1) it shells out to `higgsfield soul-id create`;
// otherwise it returns a simulated id so the character system is fully usable
// in demo mode. (Soul training requires a paid Higgsfield plan.)

export interface SoulResult {
  ok: boolean;
  soulId?: string;
  engine: "higgsfield" | "demo";
  error?: string;
}

export async function trainSoul(name: string, imagePaths: string[]): Promise<SoulResult> {
  if (!cliRenderEnabled() || imagePaths.length === 0) {
    return { ok: true, soulId: `demo-soul-${Math.random().toString(36).slice(2, 10)}`, engine: "demo" };
  }
  try {
    const { execFile } = await import("node:child_process");
    const { promisify } = await import("node:util");
    const run = promisify(execFile);
    const args = ["soul-id", "create", "--name", name, "--soul-2", "--json"];
    for (const p of imagePaths) args.push("--image", p);
    const { stdout } = await run("higgsfield", args, { maxBuffer: 1024 * 1024 * 8 });
    const id = extractId(stdout);
    if (!id) return { ok: false, engine: "higgsfield", error: "No reference id returned" };
    return { ok: true, soulId: id, engine: "higgsfield" };
  } catch (err: any) {
    return { ok: false, engine: "higgsfield", error: err?.stderr || err?.message || "Soul training failed" };
  }
}

// Generates a photoreal avatar portrait for a character. With a trained Soul
// id it renders the actual face (custom_reference); with API credentials but
// no Soul it renders a portrait matching the described vibe. Returns null in
// demo mode so callers fall back to the captured photo / illustrated face.
export async function generatePortrait(input: {
  name: string;
  vibe: string;
  soulId?: string;
}): Promise<{ url: string | null; engine: "higgsfield" | "demo"; error?: string }> {
  const creds = hfCredentials();
  if (!creds) return { url: null, engine: "demo" };
  try {
    const { createHiggsfieldClient } = await import("@higgsfield/client/v2");
    const client = createHiggsfieldClient({ credentials: creds });
    const soulInput =
      input.soulId && !input.soulId.startsWith("demo-")
        ? { custom_reference_id: input.soulId, custom_reference_strength: 0.85 }
        : {};
    const res = await client.subscribe("/v1/text2image/soul", {
      input: {
        prompt: `Portrait headshot of ${input.name}, ${input.vibe}. Warm natural light, soft background, looking at camera, friendly, photorealistic, social-media profile photo.`,
        width_and_height: "1024x1024",
        quality: "1080p",
        batch_size: 1,
        ...soulInput,
      },
      withPolling: true,
    });
    return { url: res.images?.[0]?.url || null, engine: "higgsfield" };
  } catch (err: any) {
    return { url: null, engine: "higgsfield", error: err?.message || "Portrait generation failed" };
  }
}

function extractId(stdout: string): string | null {
  try {
    const data = JSON.parse(stdout);
    const scan = (o: any): string | null => {
      if (!o) return null;
      if (typeof o === "object") {
        for (const k of Object.keys(o)) {
          if (/^(reference_id|id|soul_id)$/i.test(k) && typeof o[k] === "string") return o[k];
          const r = scan(o[k]);
          if (r) return r;
        }
      }
      return null;
    };
    return scan(data);
  } catch {
    const m = stdout.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
    return m ? m[0] : null;
  }
}
