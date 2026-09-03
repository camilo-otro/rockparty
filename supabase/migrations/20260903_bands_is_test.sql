-- =============================================================================
-- Migration: bands test-data visibility (#76, epic #40 / mirrors #67)
-- Date: 2026-09-03
-- =============================================================================
-- Bands are user-created public content. Without this, a dev's test band (and
-- its roster) is visible to real users — the same leak #67 closed for
-- party/venue. Add band.is_test and hide test bands (and their member /
-- instrument rows) from everyone except devs.
--
-- Mirrors #67: the column defaults false (real data); the create form's
-- dev-only "Datos de prueba" toggle sets it true for devs. is_dev() reveals
-- test rows to the team. Band-owned performances are NOT gated here — they
-- already inherit their toque's is_test via can_see_party() (a test band is
-- only ever signed up to a test toque in practice).
-- =============================================================================

begin;

alter table public.band add column if not exists is_test boolean not null default false;

-- can_see_band: band visibility, used by the member/instrument SELECT policies.
-- SECURITY INVOKER — runs as the caller and leans on band's own SELECT policy
-- (single source of truth). No recursion: band's policy references only is_test
-- and is_dev(), never band_member. Mirrors can_see_party().
create or replace function public.can_see_band(bid bigint)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (select 1 from public.band b where b.id = bid);
$$;

-- band: test bands hidden from everyone except devs (mirrors party/venue).
drop policy if exists "band select all" on public.band;
create policy "band select visible" on public.band
  for select to anon, authenticated using (is_test = false or public.is_dev());

-- band_member / band_member_instrument: a hidden test band's roster stays
-- hidden too (don't leak members of a band the caller can't see).
drop policy if exists "band_member select all" on public.band_member;
create policy "band_member select visible" on public.band_member
  for select to anon, authenticated using (public.can_see_band(band_id));

drop policy if exists "bmi select all" on public.band_member_instrument;
create policy "bmi select visible" on public.band_member_instrument
  for select to anon, authenticated using (public.can_see_band(band_id));

commit;
