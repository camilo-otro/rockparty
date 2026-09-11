-- =============================================================================
-- Migration: profile-avatars Storage bucket + RLS (#96)
-- Date: 2026-09-11
-- =============================================================================
-- ADDITIVE. Safe to apply before or after the matching deploy — nothing reads
-- the bucket until the client offers the cropper.
--
-- Mirrors 20260903_band_avatars_bucket.sql (#75) exactly, which is the point of
-- the ticket: the cropper, the WebP pipeline and the upload/delete helpers are
-- already generic, so all profiles were missing was somewhere to put the file.
--
-- Path convention is {user_id}/{timestamp}.webp, so the first path segment is
-- the owner's uid. Versioned names + delete-on-replace keep one avatar per
-- person and the CDN cache clean.
--
-- The ownership check is SIMPLER than the band one: "the folder is my own uid"
-- needs no helper function, where bands needed is_band_manager(). No definer
-- function is involved, so none of the anon-executability concerns from #102
-- apply here.
--
-- Bucket-level file_size_limit + allowed_mime_types are a server-side backstop
-- to the client's guardrails, so a bypassed client cannot store junk.
-- =============================================================================

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-avatars', 'profile-avatars', true, 262144, array['image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Public read. Avatars already render for anonymous visitors on the flyer and
-- the public setlist, and the bucket being public still requires a SELECT policy
-- on storage.objects.
drop policy if exists "profile-avatars public read" on storage.objects;
create policy "profile-avatars public read" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'profile-avatars');

-- Writes: your own folder only. `(storage.foldername(name))[1]` is the uid the
-- path starts with, compared as text against auth.uid().
drop policy if exists "profile-avatars owner insert" on storage.objects;
create policy "profile-avatars owner insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'profile-avatars'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "profile-avatars owner update" on storage.objects;
create policy "profile-avatars owner update" on storage.objects
  for update to authenticated
  using (bucket_id = 'profile-avatars'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "profile-avatars owner delete" on storage.objects;
create policy "profile-avatars owner delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'profile-avatars'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;

-- =============================================================================
-- Note on what `profile.avatar_url` now holds: EITHER a Google CDN URL (the
-- signup default, and what "quitar la foto" falls back to) OR a URL in this
-- bucket. Deletion is keyed off the bucket marker in the URL, so a Google URL is
-- never a delete target — see objectPathFromUrl in src/lib/avatarStorage.ts,
-- which returns null for anything outside the bucket.
--
-- After applying: reconcile supabase/schema.sql. No type regeneration needed —
-- storage buckets are not in the generated public-schema types.
-- =============================================================================
