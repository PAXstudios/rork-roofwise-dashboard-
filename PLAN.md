# Wire Supabase into the iOS app with Apple + Email login and lead sync

## What you'll get

A required sign-in screen on launch (Apple or email/password), a synced cloud copy of every lead, and a clean account section in Settings — all backed by Supabase.

### Features
- **Locked login screen on launch** — the app shows a welcome screen until the user signs in.
- **Sign in with Apple** — one-tap login using the Apple ID, no password needed.
- **Email + password** — classic sign-up and sign-in for users who prefer it, with "Forgot password" sending a reset email.
- **Persistent session** — once signed in, the app remembers the user across launches; no re-login needed.
- **Sign out** — a clear sign-out option in Settings, with a confirm step.
- **Account section in Settings** — shows the signed-in email, account creation date, and sign-out button.
- **Leads sync in the background** — every lead the user creates locally is pushed to the cloud automatically; on launch and pull-to-refresh, the app pulls down any leads not already on the device.
- **Offline-safe** — leads still work when offline; pending changes flush to the cloud as soon as a connection returns.
- **Per-user data** — each user only sees their own leads (enforced both in the app and on the server).

### Design
- **Welcome screen** — full-bleed background with the app accent gradient, app icon up top, big "Continue with Apple" button (black, system style), an "Or" divider, then email and password fields with a primary "Sign in" button. A small "Create account" link toggles the screen into sign-up mode. Sticky bottom area in the thumb zone, 64pt buttons, system fonts from the existing type ramp.
- **Loading + error states** — a soft inline spinner inside the button while signing in; errors render as a friendly red banner above the form ("Wrong password — try again or reset it").
- **Account row in Settings** — uses the existing card style with the user's email, a calendar icon for "Joined Jan 14, 2026", and a destructive red "Sign out" pill at the bottom.
- **Sync indicator** — a tiny cloud icon next to the leads list header that animates while syncing, turns into a checkmark when synced, and a warning dot if any leads failed to upload.

### Screens
- **Welcome / Sign-in** — the gate everyone hits on first launch and after sign-out; toggles between Sign In and Create Account modes.
- **Forgot password** — small screen with a single email field and "Send reset link" button.
- **Settings → Account** — shows current user, sign-out, and a "Delete account" option (with a strong confirm step).
- **Leads list (existing)** — gets a small sync status badge in the header and an automatic background refresh.

### Behind the scenes (no UI impact)
- A new server-side leads table that mirrors the on-device lead shape, scoped to the signed-in user.
- Row-level security so users can only read and write their own leads.
- The existing local lead store stays the source of truth in the UI; a background sync pushes pending changes up and pulls remote changes down on launch, on app-foreground, and on pull-to-refresh.

### What you'll need to do once on the Supabase dashboard
- Enable Apple as a sign-in provider and paste the bundle identifier + a Services ID (I'll surface the exact values when you're ready to test on device).
- Run a one-time SQL snippet to create the `leads` table and row-level security policies — I'll provide it ready to paste.

After approval I'll wire everything up, run the build, and confirm green before handing back.