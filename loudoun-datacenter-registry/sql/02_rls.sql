-- =============================================================================
-- Loudoun Data Center Watch — row-level security
--
-- Run after 01_schema.sql.
--
-- The threat model: the anon key is embedded in a static site, so treat it as
-- fully public. Anyone can obtain it and issue arbitrary PostgREST calls. These
-- policies are therefore the only thing standing between a stranger and the
-- reporters' contact details.
--
-- What anon can do:      insert one report at a time; read public_reports.
-- What anon cannot do:   select, update or delete anything in reports.
-- What a moderator can do: everything, once signed in with app_metadata.role
--                          set to 'admin'.
-- =============================================================================

alter table public.reports enable row level security;

-- Applies the policies to the table owner too. Without this, anything running
-- as the owner silently bypasses every rule below.
alter table public.reports force row level security;

-- ---- Who is a moderator? ----------------------------------------------------
--
-- The role is read from app_metadata, NOT user_metadata. user_metadata is
-- writable by the user themselves, so putting the role there would let anyone
-- who can sign up promote themselves to moderator. app_metadata can only be
-- written with the service_role key or from the Supabase dashboard.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb
      -> 'app_metadata' ->> 'role',
    ''
  ) = 'admin';
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- ---- Policies ---------------------------------------------------------------

drop policy if exists reports_anon_insert   on public.reports;
drop policy if exists reports_admin_all     on public.reports;
drop policy if exists reports_admin_select  on public.reports;

-- Anyone may file a report, and only ever as 'pending'. The insert trigger
-- already forces this; the WITH CHECK makes the intent explicit and survives
-- the trigger being changed.
create policy reports_anon_insert
  on public.reports
  for insert
  to anon, authenticated
  with check (status = 'pending');

-- Moderators get full access. There is deliberately no SELECT policy for anon:
-- with RLS on and no policy, a select returns zero rows rather than an error.
create policy reports_admin_all
  on public.reports
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ---- Grants -----------------------------------------------------------------
--
-- RLS filters rows; grants decide which statements are even allowed. Both are
-- needed — a missing grant is what stops `select * from reports` from being an
-- information-leak waiting on a policy mistake.

revoke all on public.reports from anon, authenticated;

grant insert on public.reports to anon, authenticated;
grant select, update, delete on public.reports to authenticated;

grant select on public.public_reports to anon, authenticated;

-- =============================================================================
-- Verification — run these after applying, and confirm each result.
-- =============================================================================
--
--   -- As anon (use the anon key from a REST client or the browser console):
--   select * from reports;          -- expect: 0 rows / permission denied
--   select * from public_reports;   -- expect: approved reports only
--   insert into reports (...) values (...);            -- expect: succeeds
--   insert into reports (..., status) values (..., 'approved');
--                                    -- expect: row is stored as 'pending'
--
--   -- Confirm no private column can reach a public client:
--   select column_name from information_schema.columns
--    where table_name = 'public_reports';
--   -- expect: no reporter_name, reporter_email, reporter_phone, address,
--   --         and no bare lat/lng sourced from the raw columns.
--
-- =============================================================================
