-- =============================================================================
-- Migration: party status / lifecycle model (roadmap Phase 0 keystone, #17)
-- Date: 2026-08-20 · spec: docs/specs/party-status.md
-- =============================================================================
-- Adds party.status and narrows the public read policies so drafts/pending/
-- cancelled toques (and their setlists) aren't world-visible. Backfills existing
-- parties to 'confirmed' (they were already public/real); new parties default to
-- 'draft' and are published explicitly by the organizer.
--
-- Deferred to their own features (enum values exist, transitions come later):
--   * pending_venue  -> venue approval flow (needs venue.requires_approval)
--   * live / completed -> live mode (start/end show)
-- The party UPDATE policy already limits changes to owner/party admins, so
-- publish/cancel are gated; venue-admin approval will extend it in Phase 1.
-- =============================================================================

begin;

-- 1. the lifecycle enum ------------------------------------------------------
create type public.party_status as enum
  ('draft', 'pending_venue', 'confirmed', 'live', 'completed', 'cancelled');

-- 2. columns -----------------------------------------------------------------
-- Add with default 'confirmed' so existing rows (real, public events) stay
-- visible, then switch the default to 'draft' for future inserts.
alter table public.party
  add column status public.party_status not null default 'confirmed';
alter table public.party
  alter column status set default 'draft';

alter table public.party
  add column status_changed_at timestamptz not null default now();
alter table public.party
  add column cancel_reason text;

-- (approved_by_venue is left in place but superseded by status; the venue
--  decision is represented by the pending_venue -> confirmed transition.)

-- 3. keep status_changed_at fresh -------------------------------------------
create or replace function public.set_status_changed_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status then
    new.status_changed_at = now();
  end if;
  return new;
end;
$$;

create trigger party_status_changed
  before update on public.party
  for each row execute function public.set_status_changed_at();

-- 4. visibility helper (security definer so the performance policy can check a
--    parent party without recursing through RLS) -----------------------------
create or replace function public.can_see_party(pid bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.party p
    where p.id = pid
      and (
        p.status in ('confirmed', 'live', 'completed')
        or p.created_by = (select auth.uid())
        or exists (select 1 from public.party_admin pa
                   where pa.party_id = p.id and pa.user_id = (select auth.uid()))
        or exists (select 1 from public.venue_admin va
                   where va.venue_id = p.venue and va.user_id = (select auth.uid()))
      )
  );
$$;

-- 5. narrow party SELECT (was: using (true), fully public) -------------------
drop policy if exists "allow select to all users" on public.party;
create policy "select party: public statuses or owner/admins" on public.party
  for select to anon, authenticated
  using (
    status in ('confirmed', 'live', 'completed')
    or created_by = (select auth.uid())
    or exists (select 1 from public.party_admin pa
               where pa.party_id = party.id and pa.user_id = (select auth.uid()))
    or exists (select 1 from public.venue_admin va
               where va.venue_id = party.venue and va.user_id = (select auth.uid()))
  );

-- 6. ripple: a hidden party's setlist must be hidden too ---------------------
drop policy if exists "allow select to all users" on public.performance;
create policy "select performance: parent party visible" on public.performance
  for select to anon, authenticated
  using (public.can_see_party(performance.party));

commit;

-- NOTE: performance_user SELECT is still `using (true)`; it gets its own
-- narrowing with the musician-approval feature (pending signups hidden), which
-- will also gate by parent-party visibility. Tracked there.
