-- =============================================================================
-- Migration: private toques — visibility + invites (#113 part B, closes #114)
-- Date: 2026-09-21
-- =============================================================================
-- ADDITIVE, and safe to apply BEFORE the client deploy: every existing toque is
-- `public`, which is exactly today's behaviour, so nothing changes until someone
-- picks a different visibility in a UI that does not exist yet.
--
-- The ONE exception is the party_rsvp INSERT tightening at the end. That closes
-- #114 and takes effect immediately — see its own note.
--
-- -----------------------------------------------------------------------------
-- Three visibilities, two of which are the same to RLS
-- -----------------------------------------------------------------------------
--   public   — listed, browsable, anyone may RSVP. Today's behaviour.
--   unlisted — loadable by anyone with the link, but kept out of browse lists.
--   private  — invisible unless you are invited.
--
-- `unlisted` is deliberately NOT an RLS concept. RLS cannot know whether you
-- arrived with a link, so the database treats unlisted exactly like public and
-- the CLIENT leaves it out of the lists. That is honest about what it is: a
-- browsing convenience, not a boundary. `private` is the boundary.
--
-- Anyone relying on unlisted to hide something should read #114: it hides a
-- toque from lists while leaving the link — and so the RSVP — open to whoever
-- holds it.
--
-- -----------------------------------------------------------------------------
-- Why only `party`'s policy changes
-- -----------------------------------------------------------------------------
-- can_see_party() is SECURITY INVOKER by design: it answers "is this party row
-- visible TO THE CALLER" by selecting from party and letting RLS decide. So
-- every table already gated on it — performance, party_set, party_requirement,
-- applause, and party_rsvp's SELECT — inherits the visibility rule for free the
-- moment party's own policy learns it. That is the whole reason the spec calls
-- it the choke point.
--
-- This also depends on 20260921_party_policy_no_inline_subquery.sql having
-- landed first: adding a clause to a policy that still inlined a party_admin
-- subquery would have completed the recursion cycle described there.
-- =============================================================================

begin;

-- 1 ---------------------------------------------------------------------------
create type public.party_visibility as enum ('public', 'unlisted', 'private');

alter table public.party
  add column visibility public.party_visibility not null default 'public';

comment on column public.party.visibility is
  'public = listed and open; unlisted = loadable by link, hidden from lists by the CLIENT; private = invitees only, enforced by RLS. See docs/specs/private-events.md part B.';

-- 2 ---------------------------------------------------------------------------
-- A named invite. No token here on purpose: one shareable link per toque is a
-- separate concern and lands in its own migration, because putting a claim_token
-- on every row is the mistake band-claim-link.md records — every roster edit
-- mints new tokens and the organiser cannot tell them apart.
create table if not exists public.party_invite (
  party_id   bigint not null references public.party (id) on delete cascade,
  user_id    uuid   not null references public.profile (id) on delete cascade,
  invited_by uuid            references public.profile (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (party_id, user_id)
);

create index if not exists idx_party_invite_user on public.party_invite (user_id);

alter table public.party_invite enable row level security;

-- You see your own invite; organisers see the whole list because they manage it.
-- is_party_admin is DEFINER, so this does not read `party` under RLS and cannot
-- close a cycle with party's policy below.
create policy "party_invite: yours, or you run the toque" on public.party_invite
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_party_admin(party_id)
  );

create policy "party_invite: organisers invite" on public.party_invite
  for insert to authenticated
  with check (public.is_party_admin(party_id));

-- An organiser can withdraw an invite; a guest can remove themselves.
create policy "party_invite: organisers or the guest withdraw" on public.party_invite
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_party_admin(party_id)
  );

-- 3 ---------------------------------------------------------------------------
-- DEFINER, like every other guard here: a policy on `party` that read
-- party_invite under RLS would send party_invite's policy back through
-- is_party_admin -> party. Reading it with the owner's rights keeps that flat.
create or replace function public.is_party_invited(pid bigint)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.party_invite i
    where i.party_id = pid and i.user_id = (select auth.uid())
  );
$$;

-- Must be executable by anon: party's SELECT policy applies `to anon`, and a
-- policy calling a function the caller cannot execute raises permission denied
-- rather than evaluating false. For an anonymous caller auth.uid() is null, so
-- it simply answers false.
revoke all on function public.is_party_invited(bigint) from public;
grant execute on function public.is_party_invited(bigint) to anon, authenticated;

-- 4 ---------------------------------------------------------------------------
-- The visibility rule itself. Organisers and the venue's people keep seeing
-- their own toques at any visibility and in any status — unchanged. What is new
-- is the last clause: a toque in a public-facing status is visible to everyone
-- UNLESS it is private, in which case you need an invite.
drop policy if exists "select party: public statuses or owner/admins" on public.party;
create policy "select party: public statuses or owner/admins" on public.party
  for select to anon, authenticated
  using (
    (
      public.is_party_admin(id)
      or public.is_venue_admin(venue)
      or (
        status in ('confirmed', 'live', 'completed')
        and (visibility <> 'private' or public.is_party_invited(id))
      )
    )
    and (is_test = false or public.is_dev())
  );

-- 5 ---------------------------------------------------------------------------
-- #114. The RSVP insert had no condition on party_id at all, so any signed-in
-- user could RSVP to any toque — and can_see_venue_contact grants a private
-- venue's address to anyone who RSVP'd. The entitlement was self-granted: the
-- door was locked and the key hung outside it.
--
-- can_see_party is INVOKER, so this asks the caller's own view of the toque.
-- For a private one that now means holding an invite. No cycle: party's policy
-- does not read party_rsvp.
--
-- TAKES EFFECT IMMEDIATELY, unlike the rest of this migration. Today every toque
-- is public and visible, so in practice it refuses exactly what it should have
-- refused all along: an RSVP to something you cannot see.
drop policy if exists "rsvp insert self" on public.party_rsvp;
create policy "rsvp insert self, to a toque you can see" on public.party_rsvp
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.can_see_party(party_id)
  );

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (party.visibility, the party_visibility enum, the
-- party_invite table, is_party_invited).
--
-- VERIFY as an ANONYMOUS caller — nothing should have changed yet:
--   /party?select=id,status,visibility  -> the same toques, all `public`
--
-- and once a toque is flipped to private by hand:
--   as anon            -> it disappears
--   as its organiser   -> still there
--   as an invitee      -> there
--   as anyone else     -> gone, and POST /party_rsvp for it is refused
--
-- STILL TO COME, deliberately not here:
--   * one shareable invite link per toque, for people with no account yet
--     (peek_party_invite / claim_party_invite, mirroring #79)
--   * the client: a visibility choice on the create/edit form, invite
--     management, and filtering `unlisted` out of the browse lists
-- =============================================================================
