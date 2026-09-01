-- =============================================================================
-- Migration: test-data visibility + dev role (#67)
-- Date: 2026-08-27
-- =============================================================================
-- Lets developers keep working with throwaway test toques/venues while real
-- users see only real data. Enforced in RLS (the app's ENTIRE security
-- boundary) — UI hiding alone would not stop a direct anon-key query.
--
-- Model:
--   * public.dev_user  — membership table of developer accounts. No INSERT/
--     UPDATE/DELETE policy, so a user CANNOT self-escalate; dev is granted only
--     via the SQL editor / service_role. A self-SELECT policy lets the client
--     learn its own dev status (to show the dev-only "test" toggle).
--   * public.is_dev()  — SECURITY DEFINER helper; true when the caller is a dev.
--   * party.is_test / venue.is_test — false = real (visible to everyone),
--     true = test (visible only to devs).
--   * party SELECT and venue SELECT gain "(is_test = false OR is_dev())".
--     Performances inherit automatically: performance SELECT calls
--     can_see_party(), which is SECURITY INVOKER and re-checks party RLS.
-- =============================================================================

begin;

-- 1. Dev membership -----------------------------------------------------------
create table if not exists public.dev_user (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.dev_user enable row level security;

-- A user may read ONLY their own membership row (drives the client toggle).
drop policy if exists "dev_user self read" on public.dev_user;
create policy "dev_user self read" on public.dev_user
  for select using (user_id = (select auth.uid()));
-- Intentionally NO insert/update/delete policy: dev status is granted only
-- out-of-band (SQL editor / service_role), never by the user themselves.

create or replace function public.is_dev()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.dev_user d where d.user_id = (select auth.uid())
  );
$$;

-- Seed the developers so they keep seeing test data after this runs.
insert into public.dev_user (user_id)
values
  ('0671ee04-4ab2-4f59-a6f6-e5cda28677d8'),  -- Cami
  ('ae82b725-ceb3-4642-bc7e-11236cc026a0'),  -- Yorch (Jorge, elchivo@gmail.com), designer
  ('2ba9d70f-00a0-49ee-ada6-12e26ae93da7')   -- Capibear, Cami's alternate testing account
on conflict (user_id) do nothing;

-- 2. is_test flags ------------------------------------------------------------
alter table public.party add column if not exists is_test boolean not null default false;
alter table public.venue add column if not exists is_test boolean not null default false;

-- 3. Visibility (RLS) ---------------------------------------------------------
-- venue: was world-readable; now hide test venues from non-devs.
alter policy "allow select to all users" on public.venue
  using (is_test = false or public.is_dev());

-- party: keep the existing owner/admin/public-status visibility, AND require
-- the toque to be non-test unless the caller is a dev.
alter policy "select party: public statuses or owner/admins" on public.party
  using (
    (
      (status = any (array['confirmed','live','completed']::party_status[]))
      or (created_by = (select auth.uid()))
      or (exists (select 1 from public.party_admin pa
                  where pa.party_id = party.id and pa.user_id = (select auth.uid())))
      or (exists (select 1 from public.venue v
                  where v.id = party.venue and v.created_by = (select auth.uid())))
      or (exists (select 1 from public.venue_admin va
                  where va.venue_id = party.venue and va.user_id = (select auth.uid())))
    )
    and (is_test = false or public.is_dev())
  );

-- 4. Backfill existing data ---------------------------------------------------
-- Everything currently in the DB is dev test data EXCEPT these real toques
-- (Serenata Rock, Happy Birthday Cami, Amistad y Amor por el Rock). Venues are
-- all real places, so none are flagged.
update public.party set is_test = true where id not in (5, 9, 10);

-- Remove a defunct test venue (A Fuego — closed; verified 0 toques/admins/
-- equipment). DESTRUCTIVE: permanently deletes venue id 5.
delete from public.venue where id = 5;

commit;
