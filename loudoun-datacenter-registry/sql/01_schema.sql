-- =============================================================================
-- Loudoun Data Center Watch — schema
--
-- Run this first, in the Supabase SQL editor, on a fresh project.
-- Then 02_rls.sql, then 03_storage.sql, then read 04_admin.sql.
--
-- Design notes worth reading before changing anything:
--
--   * The reporter's identity and exact location live in this table but are
--     never exposed to the anon role. The public_reports view is the only thing
--     anon can read, and it does not select those columns.
--
--   * lat_public / lng_public are derived by a trigger, not supplied by the
--     client. A client that sends its own values has them overwritten.
--
--   * status is forced to 'pending' on insert by the same trigger, so a crafted
--     payload cannot publish itself even before the RLS policy is considered.
--     Belt and braces on purpose: this is the one table anonymous strangers can
--     write to.
-- =============================================================================

create extension if not exists "pgcrypto";

-- ---- Types ------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_type where typname = 'facility_status') then
    create type facility_status as enum
      ('operational', 'under_construction', 'proposed', 'unknown');
  end if;

  if not exists (select 1 from pg_type where typname = 'report_status') then
    create type report_status as enum ('pending', 'approved', 'rejected');
  end if;
end
$$;

-- ---- Table ------------------------------------------------------------------

create table if not exists public.reports (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),

  -- Reporter contact. All optional, and never published. See public_reports.
  reporter_name     text        check (char_length(reporter_name)  <= 200),
  reporter_email    text        check (char_length(reporter_email) <= 320),
  reporter_phone    text        check (char_length(reporter_phone) <= 50),
  contact_ok        boolean     not null default false,

  -- Where. `address` and the raw lat/lng are private; the _public pair is what
  -- the map plots.
  locality          text        not null check (char_length(locality) between 2 and 80),
  zip               text        check (zip ~ '^[0-9]{5}$'),
  address           text        check (char_length(address) <= 300),

  lat               double precision not null check (lat between 38.8  and 39.4),
  lng               double precision not null check (lng between -78.05 and -77.2),
  lat_public        double precision not null,
  lng_public        double precision not null,

  -- Which facility, as far as the reporter knows. All optional.
  facility_name     text        check (char_length(facility_name)     <= 200),
  facility_operator text        check (char_length(facility_operator) <= 200),
  facility_status   facility_status not null default 'unknown',

  -- The issue itself.
  categories        text[] not null
                      check (cardinality(categories) between 1 and 10),
  severity          smallint not null check (severity between 1 and 5),
  occurred_at       date     check (occurred_at <= (now() + interval '1 day')::date),
  description       text     not null
                      check (char_length(description) between 20 and 5000),
  other_notes       text     check (char_length(other_notes) <= 2000),

  photo_paths       text[] not null default '{}'
                      check (cardinality(photo_paths) <= 5),

  -- Moderation.
  status            report_status not null default 'pending',
  moderation_note   text          check (char_length(moderation_note) <= 2000),
  moderated_at      timestamptz,
  moderated_by      uuid references auth.users (id) on delete set null
);

comment on table  public.reports is
  'Resident-submitted accounts of data center impacts. Unverified. Anon may insert; only public_reports is readable by anon.';
comment on column public.reports.lat is
  'Exact coordinate as submitted. PRIVATE — never expose. Used only to derive lat_public and to spot duplicates.';
comment on column public.reports.lat_public is
  'Coordinate offset 100-200m in a random direction. This is what the map plots.';

-- ---- Category allow-list ----------------------------------------------------
-- Kept as a CHECK rather than a lookup table: the list is short, changes rarely,
-- and it must stay in step with CATEGORIES in js/schema.js.

alter table public.reports
  drop constraint if exists reports_categories_known;

alter table public.reports
  add constraint reports_categories_known check (
    categories <@ array[
      'noise', 'air_quality', 'water', 'power', 'health',
      'property', 'light', 'traffic', 'wildlife', 'other'
    ]::text[]
  );

-- ---- Indexes ----------------------------------------------------------------

create index if not exists reports_status_created_idx
  on public.reports (status, created_at desc);

create index if not exists reports_locality_idx
  on public.reports (locality) where status = 'approved';

create index if not exists reports_categories_idx
  on public.reports using gin (categories);

-- =============================================================================
-- Trigger: derive the published coordinates, and force new rows to 'pending'.
-- =============================================================================

create or replace function public.reports_before_insert()
returns trigger
language plpgsql
as $$
declare
  distance_m double precision;
  bearing    double precision;
begin
  -- A random offset of 100-200 m, so a pin can never be walked back to a house.
  distance_m := 100 + random() * 100;
  bearing    := random() * 2 * pi();

  new.lat_public := round((new.lat + (distance_m * cos(bearing)) / 111320.0)::numeric, 6);
  new.lng_public := round(
    (new.lng + (distance_m * sin(bearing))
      / greatest(111320.0 * cos(radians(new.lat)), 1.0))::numeric, 6);

  -- Nothing self-publishes, whatever the client sent.
  new.status          := 'pending';
  new.moderation_note := null;
  new.moderated_at    := null;
  new.moderated_by    := null;
  new.created_at      := now();

  return new;
end;
$$;

drop trigger if exists reports_before_insert on public.reports;
create trigger reports_before_insert
  before insert on public.reports
  for each row execute function public.reports_before_insert();

-- Re-jitter if a moderator ever corrects the location, so the offset is never
-- derivable by comparing an edited row against its published pin.
-- Who is making this change? Read straight from the JWT rather than calling
-- auth.uid(): this trigger runs as the caller, and depending on the caller
-- holding USAGE on the auth schema makes the update fail with "permission
-- denied for schema auth" on any project where that grant is absent.
create or replace function public.current_actor()
returns uuid
language plpgsql
stable
as $$
declare
  claim text;
begin
  claim := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub';
  if claim is null then
    return null;
  end if;
  return claim::uuid;
exception
  when others then
    -- No claims set (e.g. a direct psql session), or 'sub' isn't a uuid.
    return null;
end;
$$;

create or replace function public.reports_before_update()
returns trigger
language plpgsql
as $$
declare
  distance_m double precision;
  bearing    double precision;
begin
  if new.lat is distinct from old.lat or new.lng is distinct from old.lng then
    distance_m := 100 + random() * 100;
    bearing    := random() * 2 * pi();

    new.lat_public := round((new.lat + (distance_m * cos(bearing)) / 111320.0)::numeric, 6);
    new.lng_public := round(
      (new.lng + (distance_m * sin(bearing))
        / greatest(111320.0 * cos(radians(new.lat)), 1.0))::numeric, 6);
  end if;

  if new.status is distinct from old.status then
    new.moderated_at := now();
    new.moderated_by := public.current_actor();
  end if;

  return new;
end;
$$;

drop trigger if exists reports_before_update on public.reports;
create trigger reports_before_update
  before update on public.reports
  for each row execute function public.reports_before_update();

-- =============================================================================
-- The public view. This is the ONLY thing the anon role can read.
--
-- security_invoker is left off (the default) so the view runs as its owner and
-- can read the base table despite RLS — which is exactly why it must not select
-- reporter_name, reporter_email, reporter_phone, address, lat or lng.
-- =============================================================================

drop view if exists public.public_reports;

create view public.public_reports as
select
  id,
  created_at,
  locality,
  zip,
  lat_public  as lat,      -- deliberately aliased: no raw coordinate escapes
  lng_public  as lng,
  facility_name,
  facility_operator,
  facility_status,
  categories,
  severity,
  occurred_at,
  description,
  other_notes,
  photo_paths
from public.reports
where status = 'approved';

comment on view public.public_reports is
  'Publishable columns of approved reports only. Contact details, street address and exact coordinates are excluded by construction.';
