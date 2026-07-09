import { NextRequest, NextResponse } from "next/server";
import type { Platform } from "@/lib/types";

export const runtime = "nodejs";

// A single endpoint that models the OAuth handshake for each platform.
// If real client credentials are present in the environment it returns the
// provider's authorize URL; otherwise it returns a simulated success so the
// product is fully usable in demo mode.

const AUTHORIZE: Record<Platform, string> = {
  linkedin: "https://www.linkedin.com/oauth/v2/authorization",
  instagram: "https://api.instagram.com/oauth/authorize",
  x: "https://twitter.com/i/oauth2/authorize",
  tiktok: "https://www.tiktok.com/v2/auth/authorize/",
  youtube: "https://accounts.google.com/o/oauth2/v2/auth",
};

function credsFor(platform: Platform): string | undefined {
  switch (platform) {
    case "linkedin":
      return process.env.LINKEDIN_CLIENT_ID;
    case "instagram":
      return process.env.INSTAGRAM_APP_ID;
    case "x":
      return process.env.X_CLIENT_ID;
    default:
      return undefined;
  }
}

export async function POST(req: NextRequest) {
  const { platform } = (await req.json()) as { platform: Platform };
  if (!platform || !AUTHORIZE[platform]) {
    return NextResponse.json({ ok: false, error: "Unknown platform" }, { status: 400 });
  }

  const clientId = credsFor(platform);
  const redirect = `${process.env.NEXT_PUBLIC_APP_URL || ""}/api/connect/callback`;

  if (clientId) {
    const url = new URL(AUTHORIZE[platform]);
    url.searchParams.set("client_id", clientId);
    url.searchParams.set("redirect_uri", redirect);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("scope", "openid profile r_liteprofile w_member_social");
    url.searchParams.set("state", platform);
    return NextResponse.json({ ok: true, mode: "oauth", authorizeUrl: url.toString() });
  }

  // Demo handshake — simulate a connected account.
  return NextResponse.json({
    ok: true,
    mode: "demo",
    handle: `@your_${platform}`,
    message: `Connected to ${platform} (demo). Add ${platform.toUpperCase()} credentials to .env.local for a live connection.`,
  });
}
