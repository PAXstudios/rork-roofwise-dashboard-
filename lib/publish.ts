import type { Platform } from "./types";

export interface PublishResult {
  ok: boolean;
  engine: "live" | "demo";
  url?: string;
  error?: string;
}

// Access tokens are read from the environment. In a production deployment these
// would be per-user tokens obtained via OAuth and stored server-side; here a
// single set of env tokens enables live publishing for the connected account.
function token(platform: Platform): string | undefined {
  switch (platform) {
    case "linkedin":
      return process.env.LINKEDIN_ACCESS_TOKEN;
    case "x":
      return process.env.X_ACCESS_TOKEN;
    case "instagram":
      return process.env.INSTAGRAM_ACCESS_TOKEN;
    default:
      return undefined;
  }
}

export function canPublishLive(platform: Platform): boolean {
  return Boolean(token(platform));
}

// ── Live publishers ────────────────────────────────────────────

async function publishLinkedIn(text: string, accessToken: string): Promise<PublishResult> {
  // Requires the author URN; LINKEDIN_AUTHOR_URN like "urn:li:person:xxxx".
  const author = process.env.LINKEDIN_AUTHOR_URN;
  if (!author) return { ok: false, engine: "live", error: "Missing LINKEDIN_AUTHOR_URN" };
  const res = await fetch("https://api.linkedin.com/v2/ugcPosts", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      "X-Restli-Protocol-Version": "2.0.0",
    },
    body: JSON.stringify({
      author,
      lifecycleState: "PUBLISHED",
      specificContent: {
        "com.linkedin.ugc.ShareContent": {
          shareCommentary: { text },
          shareMediaCategory: "NONE",
        },
      },
      visibility: { "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC" },
    }),
  });
  if (!res.ok) return { ok: false, engine: "live", error: `LinkedIn ${res.status}` };
  const id = res.headers.get("x-restli-id") || "";
  return { ok: true, engine: "live", url: id ? `https://www.linkedin.com/feed/update/${id}` : undefined };
}

async function publishX(text: string, accessToken: string): Promise<PublishResult> {
  const res = await fetch("https://api.twitter.com/2/tweets", {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });
  if (!res.ok) return { ok: false, engine: "live", error: `X ${res.status}` };
  const data = (await res.json()) as { data?: { id?: string } };
  const id = data?.data?.id;
  return { ok: true, engine: "live", url: id ? `https://x.com/i/status/${id}` : undefined };
}

async function publishInstagram(text: string, accessToken: string): Promise<PublishResult> {
  // Instagram requires an image/video for feed posts; text-only isn't supported.
  // We surface a clear error so the UI can explain rather than silently fail.
  const igUser = process.env.INSTAGRAM_USER_ID;
  if (!igUser) return { ok: false, engine: "live", error: "Missing INSTAGRAM_USER_ID" };
  return {
    ok: false,
    engine: "live",
    error: "Instagram requires media (image/video) for a feed post — attach media to publish live.",
  };
}

// ── Public entry ───────────────────────────────────────────────

export async function publishPost(platform: Platform, text: string): Promise<PublishResult> {
  const t = token(platform);
  if (!t) {
    // Demo mode — simulate a successful publish with a plausible URL.
    const handleSlug = platform === "x" ? "i/status" : "posts";
    return {
      ok: true,
      engine: "demo",
      url: `https://${platform}.com/${handleSlug}/demo-${Math.random().toString(36).slice(2, 10)}`,
    };
  }
  try {
    if (platform === "linkedin") return await publishLinkedIn(text, t);
    if (platform === "x") return await publishX(text, t);
    if (platform === "instagram") return await publishInstagram(text, t);
    return { ok: false, engine: "live", error: `Publishing not supported for ${platform}` };
  } catch (err: any) {
    return { ok: false, engine: "live", error: err?.message || "Publish failed" };
  }
}
