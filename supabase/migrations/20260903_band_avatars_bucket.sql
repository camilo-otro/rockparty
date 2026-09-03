-- =============================================================================
-- Migration: band-avatars Storage bucket + RLS (#75, epic #40)
-- Date: 2026-09-03
-- =============================================================================
-- Avatars are cropped/optimized client-side (Supabase image transforms are
-- Pro-only) to a 512x512 WebP <= ~150 KB, then uploaded here. Public read (plain
-- <img>); only a band's managers may write its folder. Path convention is
-- {band_id}/{timestamp}.webp, so the first path segment is the band id.
--
-- Bucket-level file_size_limit + allowed_mime_types are a server-side backstop to
-- the client 150 KB / WebP guardrails (so a bypassed client can't store junk).
-- See docs/specs/bands.md (Avatar handling).
-- =============================================================================

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('band-avatars', 'band-avatars', true, 262144, array['image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Public read (the bucket is public; storage.objects still needs a SELECT policy).
drop policy if exists "band-avatars public read" on storage.objects;
create policy "band-avatars public read" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'band-avatars');

-- Writes: only a band's managers may touch its {band_id}/... folder.
drop policy if exists "band-avatars manager insert" on storage.objects;
create policy "band-avatars manager insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'band-avatars'
              and public.is_band_manager((storage.foldername(name))[1]::bigint));

drop policy if exists "band-avatars manager update" on storage.objects;
create policy "band-avatars manager update" on storage.objects
  for update to authenticated
  using (bucket_id = 'band-avatars'
         and public.is_band_manager((storage.foldername(name))[1]::bigint));

drop policy if exists "band-avatars manager delete" on storage.objects;
create policy "band-avatars manager delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'band-avatars'
         and public.is_band_manager((storage.foldername(name))[1]::bigint));

commit;
