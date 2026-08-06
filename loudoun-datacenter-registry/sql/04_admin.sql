-- =============================================================================
-- Loudoun Data Center Watch — making yourself a moderator
--
-- Read this; most of it is instructions rather than SQL to run blindly.
--
-- is_admin() (see 02_rls.sql) checks app_metadata.role = 'admin' on the signed-in
-- user's JWT. app_metadata cannot be written by the user themselves, which is
-- the whole point — if the role lived in user_metadata, anyone who could sign up
-- could promote themselves and read every reporter's contact details.
-- =============================================================================


-- ---- Step 1: create the account ---------------------------------------------
--
-- Supabase dashboard → Authentication → Users → Add user.
-- Use a real address and a strong, unique password. Turn OFF public sign-ups
-- (Authentication → Providers → Email → "Enable sign ups") once your moderator
-- accounts exist; this site has no need for self-service registration.


-- ---- Step 2: grant the role -------------------------------------------------
--
-- Option A — Dashboard (easiest):
--   Authentication → Users → select the user → "User Metadata" panel →
--   edit **App Metadata** (not User Metadata) and set:
--       { "role": "admin" }
--
-- Option B — Admin API, from a trusted machine only. Never put the
-- service_role key in js/config.js or anywhere else the browser can see it:
--
--   curl -X PUT "https://<PROJECT>.supabase.co/auth/v1/admin/users/<USER_ID>" \
--     -H "apikey: <SERVICE_ROLE_KEY>" \
--     -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
--     -H "Content-Type: application/json" \
--     -d '{"app_metadata": {"role": "admin"}}'
--
-- Option C — direct SQL. Works, but the dashboard and API are preferred because
-- they go through GoTrue rather than writing to its table underneath it:

--   update auth.users
--      set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
--                              || '{"role":"admin"}'::jsonb
--    where email = 'you@example.org';


-- ---- Step 3: sign out and back in -------------------------------------------
--
-- The role is read from the JWT, and JWTs are issued at sign-in. An existing
-- session will keep the old claims until it refreshes, so sign out of
-- admin.html and sign back in before testing.


-- ---- Step 4: verify ---------------------------------------------------------
--
-- Signed in as the moderator, in the browser console on admin.html:
--
--   await LDCW.Store.isAdmin()          // expect: true
--   await LDCW.Store.listPending()      // expect: an array, not an error
--
-- Signed out, or signed in as a non-admin:
--
--   await LDCW.Store.listPending()      // expect: [] — RLS filters everything
--
-- The empty array rather than an error is correct: with RLS enabled and no
-- matching policy, Postgres returns no rows.


-- =============================================================================
-- Useful moderator queries
-- =============================================================================

-- How big is the queue, and how old is the oldest thing in it?
--
--   select status, count(*), min(created_at) as oldest
--     from public.reports
--    group by status
--    order by status;


-- Possible duplicates: several reports from one place in a short window. Worth
-- a look before approving — could be one household filing twice, or could be a
-- street that all noticed the same event, which is the opposite of a problem.
--
--   select date_trunc('day', created_at) as day,
--          locality, zip, count(*)
--     from public.reports
--    where status = 'pending'
--    group by 1, 2, 3
--   having count(*) > 2
--    order by 1 desc;


-- Approve one report.
--
--   update public.reports
--      set status = 'approved'
--    where id = '<uuid>';


-- Reject one, with a reason recorded for your own reference. The reason is
-- never shown publicly.
--
--   update public.reports
--      set status = 'rejected',
--          moderation_note = 'Second-hand account; asked reporter to resubmit.'
--    where id = '<uuid>';


-- Honour a deletion request while keeping the published report — strips the
-- identifying columns only.
--
--   update public.reports
--      set reporter_name = null,
--          reporter_email = null,
--          reporter_phone = null,
--          address = null,
--          contact_ok = false
--    where id = '<uuid>';


-- Honour a full deletion request.
--
--   delete from public.reports where id = '<uuid>';
--   -- then remove the objects listed in that row's photo_paths from storage.


-- Tidy up photos attached to long-rejected reports (see 03_storage.sql).
--
--   select public.purge_rejected_photos('90 days');
