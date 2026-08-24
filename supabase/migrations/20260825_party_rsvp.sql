-- =============================================================================
-- Migration: RSVP / attendance (#58)
-- Date: 2026-08-25
-- =============================================================================
-- Lets a user mark they're attending a toque — a third relationship to an event
-- alongside organizing and playing. A row = "going" (binary for v1; a status
-- column can be added later for maybe/not-going). Owner-managed, same shape as
-- profile_instrument / venue_equipment. Attendance is public (counts/lists on
-- public toques), so SELECT is open; users add/remove only their own row.
-- =============================================================================

begin;

create table if not exists public.party_rsvp (
  party_id   bigint not null references public.party (id) on delete cascade,
  user_id    uuid   not null references public.profile (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (party_id, user_id)
);
create index if not exists idx_party_rsvp_user on public.party_rsvp (user_id);

alter table public.party_rsvp enable row level security;
create policy "allow select to all users" on public.party_rsvp
  for select to anon, authenticated using (true);
create policy "rsvp insert self" on public.party_rsvp
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "rsvp delete self" on public.party_rsvp
  for delete to authenticated using (user_id = (select auth.uid()));

commit;
