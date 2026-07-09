import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

// OAuth redirect target. In demo mode this is never reached; when real client
// credentials are configured, the provider redirects here with ?code&state.
// We bounce the user back into the app; a production build would exchange the
// code for tokens here before persisting the connection server-side.
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const state = searchParams.get("state") || "";
  const error = searchParams.get("error");
  const base = process.env.NEXT_PUBLIC_APP_URL || new URL(req.url).origin;

  const target = new URL("/dashboard/connections", base);
  if (error) target.searchParams.set("connect_error", error);
  else if (state) target.searchParams.set("connected", state);

  return NextResponse.redirect(target);
}
