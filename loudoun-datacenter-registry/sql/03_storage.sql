-- =============================================================================
-- Loudoun Data Center Watch — photo storage
--
-- Run after 02_rls.sql.
--
-- The bucket is private. Anonymous visitors can write into pending/ and nothing
-- else — they cannot list it, read it back, overwrite it or delete from it.
-- That matters: pending photos belong to reports nobody has reviewed yet, and
-- one submitter must not be able to browse another's.
--
-- Public pages display approved photos through short-lived signed URLs, which
-- the client requests via createSignedUrls(). Signed URLs work against a private
-- bucket precisely because the object itself is not publicly readable.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'report-photos',
  'report-photos',
  false,
  10485760,  -- 10 MB, matching MAX_PHOTO_BYTES in js/config.js
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---- Policies ---------------------------------------------------------------

drop policy if exists "report photos: anon upload to pending" on storage.objects;
drop policy if exists "report photos: admin read"             on storage.objects;
drop policy if exists "report photos: admin write"            on storage.objects;
drop policy if exists "report photos: admin delete"           on storage.objects;

-- Write-only for the public, and only under pending/. The client generates an
-- unguessable UUID prefix per submission, so paths cannot be enumerated.
create policy "report photos: anon upload to pending"
  on storage.objects
  for insert
  to anon, authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = 'pending'
  );

-- Moderators can do everything, including moving objects from pending/ to
-- approved/ when they publish a report.
create policy "report photos: admin read"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'report-photos' and public.is_admin());

create policy "report photos: admin write"
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'report-photos' and public.is_admin())
  with check (bucket_id = 'report-photos' and public.is_admin());

create policy "report photos: admin delete"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'report-photos' and public.is_admin());

-- =============================================================================
-- Note on signed URLs for public visitors
--
-- createSignedUrls() is executed by the Storage API, not by the caller's role,
-- so an anonymous visitor CAN be issued a signed link for an approved photo
-- even though they hold no select policy of their own. If you would rather not
-- rely on that, the alternative is a second public bucket holding only approved
-- images, with the moderator copying files across on approval. The single
-- private bucket is simpler and keeps unreviewed photos strictly out of reach,
-- which is the more important property.
-- =============================================================================

-- ---- Housekeeping -----------------------------------------------------------
-- Photos attached to rejected reports should not linger. Run periodically, or
-- schedule with pg_cron if the extension is enabled on your project.

create or replace function public.purge_rejected_photos(older_than interval default '90 days')
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer := 0;
begin
  with doomed as (
    select unnest(photo_paths) as path
      from public.reports
     where status = 'rejected'
       and coalesce(moderated_at, created_at) < now() - older_than
  )
  delete from storage.objects
   where bucket_id = 'report-photos'
     and name in (select path from doomed);

  get diagnostics removed = row_count;

  update public.reports
     set photo_paths = '{}'
   where status = 'rejected'
     and coalesce(moderated_at, created_at) < now() - older_than
     and cardinality(photo_paths) > 0;

  return removed;
end;
$$;

revoke all on function public.purge_rejected_photos(interval) from public, anon;
