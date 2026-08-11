-- =============================================================================
-- Loudoun Data Center Watch — Part Two schema
--
-- Run after 01_schema.sql, 02_rls.sql and 03_storage.sql.
--
-- Adds the four tables Part Two needs — facilities, watchlist, news_items,
-- meetings — and the function that computes the watchlist.
--
-- The privacy model is unchanged and this file is careful not to weaken it.
-- refresh_watchlist() is the only thing here that reads public.reports, it is
-- SECURITY DEFINER for exactly one reason (counting distinct households needs
-- reporter_email), and it writes nothing but counts. anon can read the output
-- tables and nothing else.
-- =============================================================================

-- ---- Distance ---------------------------------------------------------------
-- Haversine in plain SQL. PostGIS would be the obvious tool, but it is a large
-- dependency for one function and the earthdistance extension needs cube, which
-- some managed setups restrict. This is accurate to a few metres over county
-- distances, which is far below the 100-200 m jitter already in the data.

create or replace function public.meters_between(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision
language sql immutable parallel safe as $$
  select 6371008.8 * 2 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2))
    * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- ---- Facilities -------------------------------------------------------------
-- A mirror of the county GIS layers, refreshed server-side. Part One reads
-- facilities from a static GeoJSON in the browser and that still works; this
-- table exists so the watchlist can name a cluster after the facility at its
-- centre, and so change detection has something to diff against.

create table if not exists public.facilities (
  id            text primary key,              -- county PIN or application number
  name          text not null,
  operator      text,
  status        facility_status not null default 'unknown',
  locality      text,
  lat           double precision not null,
  lng           double precision not null,
  sq_ft         bigint,
  application   text,                          -- EPLAN-2023-0083, ZMAP-2018-0015
  source_layer  text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  retired_at    timestamptz                    -- set when it drops out of the county layer
);

create index if not exists facilities_latlng_idx on public.facilities (lat, lng);
create index if not exists facilities_status_idx on public.facilities (status)
  where retired_at is null;

-- ---- Watchlist --------------------------------------------------------------

create table if not exists public.watchlist (
  id               uuid primary key default gen_random_uuid(),
  kind             text not null check (kind in ('facility', 'area')),
  label            text not null check (char_length(label) between 2 and 160),
  locality         text,
  facility_id      text references public.facilities (id) on delete set null,

  -- Cluster centre. For a facility cluster this is the facility. For an area
  -- cluster it is the published (jittered) location of the anchor report, which
  -- is deliberate: no exact address is ever the centre of a published circle.
  lat              double precision not null,
  lng              double precision not null,
  radius_m         integer not null default 3219,   -- 2 miles

  report_count     integer not null check (report_count     >= 0),
  household_count  integer not null check (household_count  >= 0),
  categories       text[]  not null default '{}',
  top_severity     smallint,

  first_report_at  timestamptz,
  latest_report_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists watchlist_rank_idx on public.watchlist (report_count desc);

-- Thresholds live in one place so the rule can be changed without hunting.
-- 5 reports from 5 distinct households within 2 miles. Both halves matter:
-- one household filing five times is not a cluster.
create or replace function public.watchlist_config()
returns table (radius_m integer, min_reports integer, min_households integer)
language sql immutable as $$ select 3219, 5, 5 $$;

-- =============================================================================
-- refresh_watchlist()
--
-- SECURITY DEFINER because counting distinct households requires reading
-- reporter_email from public.reports, which no client role may do. Nothing it
-- writes contains an email, an exact coordinate, or any other private field.
--
-- Candidate centres are the reports themselves rather than a fixed grid: every
-- real cluster contains at least one report at its core, so scanning reports
-- finds the same clusters as a grid without inventing centres in empty fields.
-- Candidates are then taken strongest-first, and any candidate within one
-- radius of an already-accepted centre is dropped, so the output does not
-- contain five overlapping entries describing one cluster.
-- =============================================================================

create or replace function public.refresh_watchlist()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg          record;
  candidate    record;
  accepted     integer := 0;
  centres      jsonb   := '[]'::jsonb;
  centre       jsonb;
  is_duplicate     boolean;
  near_facility record;
begin
  select * into cfg from public.watchlist_config();

  create temp table _candidates on commit drop as
  select
      anchor.id                                as anchor_id,
      anchor.lat_public                        as lat,
      anchor.lng_public                        as lng,
      anchor.locality                          as locality,
      count(distinct near.id)                  as report_count,
      count(distinct lower(trim(near.reporter_email)))
        filter (where near.reporter_email is not null and trim(near.reporter_email) <> '')
                                               as household_count,
      array_agg(distinct cat)                  as categories,
      max(near.severity)                       as top_severity,
      min(near.created_at)                     as first_report_at,
      max(near.created_at)                     as latest_report_at
    from public.reports anchor
    join public.reports near
      on near.status = 'approved'
     and public.meters_between(anchor.lat_public, anchor.lng_public,
                               near.lat_public,   near.lng_public) <= cfg.radius_m
    cross join lateral unnest(near.categories) as cat
   where anchor.status = 'approved'
   group by anchor.id, anchor.lat_public, anchor.lng_public, anchor.locality
  having count(distinct near.id) >= cfg.min_reports;

  delete from public.watchlist;

  for candidate in
    select * from _candidates
     where household_count >= cfg.min_households
     order by report_count desc, latest_report_at desc, anchor_id
  loop
    -- Drop candidates that describe a cluster already accepted.
    is_duplicate := false;
    for centre in select * from jsonb_array_elements(centres) loop
      if public.meters_between(candidate.lat, candidate.lng,
                               (centre ->> 'lat')::double precision,
                               (centre ->> 'lng')::double precision) <= cfg.radius_m then
        is_duplicate := true;
        exit;
      end if;
    end loop;
    continue when is_duplicate;

    -- Name it after the facility at its centre when there is one.
    select f.id, f.name, f.locality
      into near_facility
      from public.facilities f
     where f.retired_at is null
       and public.meters_between(candidate.lat, candidate.lng, f.lat, f.lng) <= cfg.radius_m
     order by public.meters_between(candidate.lat, candidate.lng, f.lat, f.lng)
     limit 1;

    insert into public.watchlist (
      kind, label, locality, facility_id, lat, lng, radius_m,
      report_count, household_count, categories, top_severity,
      first_report_at, latest_report_at
    ) values (
      case when near_facility.id is null then 'area' else 'facility' end,
      coalesce(near_facility.name, 'Near ' || coalesce(candidate.locality, 'Loudoun County')),
      coalesce(candidate.locality, near_facility.locality),
      near_facility.id,
      candidate.lat, candidate.lng, cfg.radius_m,
      candidate.report_count, candidate.household_count,
      candidate.categories, candidate.top_severity,
      candidate.first_report_at, candidate.latest_report_at
    );

    centres  := centres || jsonb_build_object('lat', candidate.lat, 'lng', candidate.lng);
    accepted := accepted + 1;
  end loop;

  return accepted;
end;
$$;

revoke all on function public.refresh_watchlist() from public, anon;

-- ---- News -------------------------------------------------------------------
-- Written only by the Edge Function, using the service role. Headline, source,
-- date and link. No article body: the site links to journalism, it does not
-- republish it.

create table if not exists public.news_items (
  id             uuid primary key default gen_random_uuid(),
  title          text not null check (char_length(title) between 3 and 400),
  url            text not null check (url ~ '^https?://'),
  source         text not null check (char_length(source) <= 120),
  topic          text not null default 'loudoun',
  published_at   timestamptz not null,
  fetched_at     timestamptz not null default now(),
  hidden         boolean not null default false,
  -- Normalised title, used to collapse the same wire story across mastheads.
  dedupe_key     text generated always as (
                   regexp_replace(lower(title), '[^a-z0-9]+', '', 'g')
                 ) stored,
  unique (dedupe_key)
);

create index if not exists news_recent_idx
  on public.news_items (published_at desc) where hidden = false;

-- ---- Meetings ---------------------------------------------------------------

create table if not exists public.meetings (
  id               text primary key,            -- the county EID
  title            text not null,
  body             text,                        -- Board of Supervisors, Planning Commission...
  starts_at        timestamptz not null,
  location         text,
  detail_url       text,
  agenda_url       text,
  stream_url       text,
  data_center_flag boolean not null default false,
  public_comment   boolean,
  fetched_at       timestamptz not null default now()
);

create index if not exists meetings_upcoming_idx on public.meetings (starts_at);

-- ---- RLS --------------------------------------------------------------------
-- Everything here is published aggregate or public-record data, so anon may
-- read it. Nothing here is writable by anon; the Edge Functions write with the
-- service role, which bypasses RLS.

alter table public.facilities  enable row level security;
alter table public.watchlist   enable row level security;
alter table public.news_items  enable row level security;
alter table public.meetings    enable row level security;

drop policy if exists "facilities: public read" on public.facilities;
drop policy if exists "watchlist: public read"  on public.watchlist;
drop policy if exists "news: public read"       on public.news_items;
drop policy if exists "meetings: public read"   on public.meetings;

create policy "facilities: public read" on public.facilities
  for select to anon, authenticated using (retired_at is null);

create policy "watchlist: public read" on public.watchlist
  for select to anon, authenticated using (true);

create policy "news: public read" on public.news_items
  for select to anon, authenticated using (hidden = false);

create policy "meetings: public read" on public.meetings
  for select to anon, authenticated using (true);

grant select on public.facilities, public.watchlist, public.news_items, public.meetings
  to anon, authenticated;

-- ---- Scheduling -------------------------------------------------------------
-- With pg_cron enabled (Database → Extensions in the Supabase dashboard):
--
--   select cron.schedule('watchlist-refresh', '17 * * * *',
--                        $cron$ select public.refresh_watchlist() $cron$);
--
-- Also call refresh_watchlist() from the moderation UI right after a report is
-- approved, so the ticker reflects a decision immediately rather than up to an
-- hour later.
--
-- Without pg_cron, invoke it from the same scheduled Edge Function that
-- refreshes news and meetings.
