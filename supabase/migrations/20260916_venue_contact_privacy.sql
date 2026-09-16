-- =============================================================================
-- Migration: a venue's exact address stops being public (stage 1)
-- Date: 2026-09-16
-- =============================================================================
-- SAFE TO APPLY NOW, BEFORE any client deploy — and it should be, because the
-- leak is live.
--
-- -----------------------------------------------------------------------------
-- What is exposed right now
-- -----------------------------------------------------------------------------
-- `venue` SELECT is `to anon, authenticated using ((is_test = false) or
-- is_dev())`, so every column of every real venue is readable by anyone with the
-- anon key — which ships inside the JS bundle. Measured against production:
--
--   GET /rest/v1/venue?select=name,address,whatsapp,contact_name&venue_type=eq.4
--     Cami's House   <full street address>   <mobile number>   Cami Soto
--     Donde Naty     <street>                         Naty
--
-- Two real homes and a real phone number, to callers with no account. Joined
-- against `party_rsvp` — which is `using (true)` — that is a home address and a
-- guest list in two requests.
--
-- -----------------------------------------------------------------------------
-- Why a separate table and not a policy
-- -----------------------------------------------------------------------------
-- RLS controls WHICH ROWS a caller sees, never which COLUMNS. Hiding the venue
-- row instead would take the venue's NAME with it, and the name is how a toque
-- identifies where it is — a public jam at somebody's house still needs to say
-- "Cami's House" on the flyer. The sensitive columns therefore have to live
-- somewhere with its own policy. Same wall that pushed every narrow write in
-- this app into a SECURITY DEFINER RPC (#95, #99, #100).
--
-- -----------------------------------------------------------------------------
-- Why the old columns are NOT dropped here
-- -----------------------------------------------------------------------------
-- Thirteen client files read `address`, `whatsapp` or `contact_name` off
-- `venue`. Dropping them now is the backwards ordering CLAUDE.md warns about —
-- it would break the live client instantly.
--
-- So this migration copies the data across, and then NULLs the three columns on
-- `venue` FOR PRIVATE VENUES ONLY. That closes the actual exposure immediately
-- while leaving public venues exactly as they are, so the live client keeps
-- working everywhere except the two home venues, which show a blank address
-- until the client is taught to read venue_contact. No data is lost — it is all
-- in venue_contact.
--
-- Stage 2, AFTER that client deploy: drop address / whatsapp / contact_name from
-- `venue` entirely.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- The public half
-- -----------------------------------------------------------------------------
-- `area` is the coarse, always-public location. The data already works this way
-- by hand — public venues carry a neighbourhood ("Usaquen", "Chapinero",
-- "Cedritos") while homes carry a street address — so this makes an existing
-- convention enforceable rather than inventing one.
alter table public.venue
  add column if not exists area text,
  add column if not exists private boolean not null default false;

comment on column public.venue.area is
  'Coarse public location (neighbourhood). Always readable. The exact address lives in venue_contact.';
comment on column public.venue.private is
  'True when this venue is somebody''s home or otherwise not a public address.';

-- Existing public venues already hold a neighbourhood in `address`; carry it
-- over so nothing loses its public location.
update public.venue set area = address
where area is null and venue_type is distinct from 4;

-- "Club Privado" is the closest thing the type list has to "a home". It is only
-- a seed for the flag — from here on `private` is what governs, not the type.
update public.venue set private = true where venue_type = 4;

-- -----------------------------------------------------------------------------
-- The private half
-- -----------------------------------------------------------------------------
create table if not exists public.venue_contact (
  venue_id     bigint primary key references public.venue (id) on delete cascade,
  address      text,
  whatsapp     text,
  contact_name text,
  created_at   timestamptz not null default now()
);

insert into public.venue_contact (venue_id, address, whatsapp, contact_name)
select id, address, whatsapp, contact_name from public.venue
on conflict (venue_id) do nothing;

alter table public.venue_contact enable row level security;

-- Who has a reason to know exactly where this is. A DEFINER function because the
-- tables it reads (party, party_rsvp, performance_user) are themselves behind
-- RLS, and reading them from inside a policy would evaluate as the CALLER and
-- silently under-report — the recurring lesson in CLAUDE.md.
create or replace function public.can_see_venue_contact(vid bigint)
returns boolean language sql stable security definer set search_path = '' as $$
  select
    -- the people who run the place
    public.is_venue_admin(vid)
    -- the organiser of a toque booked there
    or exists (
      select 1 from public.party p
      where p.venue = vid and public.is_party_admin(p.id)
    )
    -- anyone who said they are going
    or exists (
      select 1 from public.party p
      join public.party_rsvp r on r.party_id = p.id
      where p.venue = vid and r.user_id = (select auth.uid())
    )
    -- anyone actually playing there
    or exists (
      select 1 from public.party p
      join public.performance pf on pf.party = p.id
      join public.performance_user pu on pu.performance_id = pf.id
      where p.venue = vid
        and pu.user_id = (select auth.uid())
        and pu.status = 'approved'
    );
$$;

-- A public venue's address stays public — that is most venues, and a bar's
-- address on a flyer is the point. Only a private one narrows.
drop policy if exists "venue_contact: public venues, or people going" on public.venue_contact;
create policy "venue_contact: public venues, or people going" on public.venue_contact
  for select to anon, authenticated
  using (
    exists (select 1 from public.venue v where v.id = venue_contact.venue_id and v.private = false)
    or public.can_see_venue_contact(venue_contact.venue_id)
  );

drop policy if exists "venue_contact: venue admins write" on public.venue_contact;
create policy "venue_contact: venue admins write" on public.venue_contact
  for all to authenticated
  using (public.is_venue_admin(venue_contact.venue_id))
  with check (public.is_venue_admin(venue_contact.venue_id));

-- EXECUTABLE BY ANON on purpose: the policy above applies `to anon`, and a
-- definer function the caller cannot execute raises permission-denied instead of
-- returning false (#102).
revoke all on function public.can_see_venue_contact(bigint) from public;
grant execute on function public.can_see_venue_contact(bigint) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Close the exposure now
-- -----------------------------------------------------------------------------
-- The values are safely in venue_contact above. Blanking them here on PRIVATE
-- venues only is what actually stops the anonymous read, without touching the
-- public venues the live client still reads normally.
update public.venue
set address = null, whatsapp = null, contact_name = null
where private = true;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (new table, two new venue columns, one function).
--
-- VERIFY as an ANONYMOUS caller over REST — never the SQL editor:
--   /venue?select=name,address,whatsapp,contact_name&private=eq.true
--     -> names only; address, whatsapp and contact_name all null
--   /venue_contact?select=venue_id,address
--     -> only rows for venues where private = false
--
-- NEXT, in order:
--   1. client: read address/whatsapp/contact_name from venue_contact, and show
--      `area` where the exact address is not available (13 files touch these).
--   2. migration stage 2: drop address, whatsapp, contact_name from `venue`.
--   3. separately, party_rsvp SELECT is `using (true)` — a guest list for every
--      toque, to anyone. See docs/specs/private-events.md.
-- =============================================================================
