-- ===========================================================================
-- 06 — Which facility, as an id rather than a sentence
--
-- Run after 01–05. Safe to run twice.
--
-- `facility_name` was free text, and free text is unjoinable: "Beaumeade",
-- "beaumeade?", "the Beaumeade one" and "big campus off Pacific" are four
-- reports about the same ground that could never be counted together. This
-- adds `facility_ids` — the campus slugs the picker produces — alongside it.
--
-- `facility_name` is NOT dropped. It stays as the human-readable string a
-- moderator reads, and it is the only thing the older reports have.
--
-- A campus id is a slug of the county's own facility name ("beaumeade",
-- "loudoun-tech-center"). It is deliberately derived from the name and nothing
-- else, so it survives a re-pull of the county data unchanged. Ids are not
-- validated against a list here: the county's records change, and a report
-- must not become unreadable because a parcel was renamed after it was filed.
--
-- Nothing here touches the privacy model. A campus id says which facility a
-- resident is talking about; it says nothing about the resident.
-- ===========================================================================

begin;

alter table public.reports
  add column if not exists facility_ids text[] not null default '{}';

-- Bound it in the same way every other free-form field is bounded, so a
-- crafted payload cannot post a megabyte of ids.
--
-- Bounding the joined length rather than each element: a CHECK constraint may
-- not contain a subquery, so `unnest` is unavailable here, and the total is
-- what actually needs limiting anyway. 20 ids at 80 characters is 1,679 with
-- separators — a report naming more than twenty campuses is not a report.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'reports_facility_ids_len'
  ) then
    alter table public.reports
      add constraint reports_facility_ids_len
      check (
        coalesce(array_length(facility_ids, 1), 0) <= 20
        and char_length(array_to_string(facility_ids, ',')) <= 1700
      );
  end if;
end $$;

comment on column public.reports.facility_ids is
  'Campus slugs this report names, from the county''s own facility names. Empty means the reporter said they were not sure, which is a valid answer.';

-- Reports about one campus, without a table scan per campus.
create index if not exists reports_facility_ids_idx
  on public.reports using gin (facility_ids);

-- ---------------------------------------------------------------------------
-- Republish the view.
--
-- CREATE OR REPLACE VIEW cannot add a column in the middle, and this one has
-- to keep its column order stable for the client. Dropping and recreating
-- takes the grants with it, so they are reapplied below — miss that and the
-- anon role loses its only read path.
-- ---------------------------------------------------------------------------

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
  facility_ids,
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

-- The view runs as its owner, so it can read the base table the anon role has
-- no SELECT policy on. That is the whole point of it.
alter view public.public_reports set (security_invoker = off);

grant select on public.public_reports to anon, authenticated;

commit;

-- ---------------------------------------------------------------------------
-- Check it: how many approved reports name each campus.
--
--   select unnest(facility_ids) as campus, count(*)
--   from public.public_reports
--   group by 1
--   order by 2 desc;
-- ---------------------------------------------------------------------------
