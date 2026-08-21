-- =============================================================================
-- Migration: performer profile instruments (#28, keystone)
-- Date: 2026-08-21
-- =============================================================================
-- Today an instrument only attaches to a performer per-song (performance_user).
-- This adds a profile-level list of instruments a performer plays, which unlocks
-- matching, gaps-to-fill (#32), and band rosters.
--
-- profile_instrument: junction of profile × instrument. A performer manages
-- their OWN rows (RLS: insert/delete only where profile_id = auth.uid());
-- everyone can read (needed to display instruments and to match/fill gaps).
-- =============================================================================

begin;

create table if not exists public.profile_instrument (
  profile_id    uuid   not null references public.profile (id) on delete cascade,
  instrument_id bigint not null references public.instrument (id),
  created_at    timestamptz not null default now(),
  primary key (profile_id, instrument_id)
);

-- FK covering index (profile_id is the leftmost PK column, so it's already
-- covered; instrument_id is not — advisor pattern).
create index if not exists idx_profile_instrument_instrument
  on public.profile_instrument (instrument_id);

alter table public.profile_instrument enable row level security;

-- Readable by everyone (matching / gaps / profile display).
create policy "allow select to all users" on public.profile_instrument
  for select to anon, authenticated using (true);

-- A performer manages only their own instruments. No UPDATE policy: the junction
-- is add/remove only, so updates stay denied.
create policy "allow insert to own profile" on public.profile_instrument
  for insert to authenticated with check (profile_id = (select auth.uid()));

create policy "allow delete to own profile" on public.profile_instrument
  for delete to authenticated using (profile_id = (select auth.uid()));

commit;
