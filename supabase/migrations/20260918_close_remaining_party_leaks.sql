-- =============================================================================
-- Migration: the last three `using (true)` reads on party data (#113)
-- Date: 2026-09-18
-- =============================================================================
-- APPLY BEFORE THE CLIENT DEPLOY that goes with it. Narrowing party_rsvp breaks
-- the attendee COUNT until the client switches to party_rsvp_count() below, so
-- the two want to land together — apply this, then deploy.
--
-- Everything else here is safe in either order.
--
-- -----------------------------------------------------------------------------
-- 1. party_admin — `hidden` was a promise RLS did not keep
-- -----------------------------------------------------------------------------
-- The edit page lets an organiser take themselves off the public list: the
-- toast says "Ya no apareces como organizador" and the row greys out with "No
-- aparece en la página". But the policy was `using (true)`, so the row still
-- came back over the API — the app hid them, the database did not. That is the
-- "UI hiding is not security" shape this codebase keeps running into.
--
-- Now: you always see your own row, fellow organisers see everyone (they need
-- the full list to manage it), and everybody else sees only the ones that have
-- not opted out, on a toque they can see at all.
--
-- is_party_admin is SECURITY DEFINER, so calling it in a policy ON party_admin
-- does not recurse.
--
-- -----------------------------------------------------------------------------
-- 2. applause — scoped to toques you can see
-- -----------------------------------------------------------------------------
-- Was readable across every party including test ones. The performer tallies on
-- a profile page keep working: real toques are visible to everyone, so only
-- test-party applause drops out for non-devs, which is the intent of #67.
--
-- -----------------------------------------------------------------------------
-- 3. party_rsvp — the guest list
-- -----------------------------------------------------------------------------
-- This is the half of the original #113 finding that was still open. The spec
-- put it plainly: `party_rsvp` joined against a venue address is "a home address
-- and a guest list in two requests". The address closed on 2026-09-16; this is
-- the guest list.
--
-- The app never actually displays a roster — every client query is either a
-- count or filtered to your own row — so nothing on screen is lost. What goes
-- away is the ABILITY to enumerate who is going to somebody's house party by
-- asking the API directly.
--
-- Rows are now yours, or the organisers'. The public count moves to a function.
-- =============================================================================

begin;

-- 1 ---------------------------------------------------------------------------
drop policy if exists "Enable read access for authenticated users" on public.party_admin;
create policy "party_admin: yours, your co-organisers', or not hidden" on public.party_admin
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_party_admin(party_id)
    or (hidden = false and public.can_see_party(party_id))
  );

-- 2 ---------------------------------------------------------------------------
drop policy if exists "applause: read" on public.applause;
create policy "applause: toques you can see" on public.applause
  for select to authenticated
  using (public.can_see_party(party_id));

-- 3 ---------------------------------------------------------------------------
drop policy if exists "party_rsvp select: parent party visible" on public.party_rsvp;
create policy "party_rsvp: your own, or you run the toque" on public.party_rsvp
  for select to anon, authenticated
  using (
    user_id = (select auth.uid())
    or public.is_party_admin(party_id)
  );

-- The attendee count stays public, the names do not.
--
-- NOTE the visibility test is spelled out rather than calling can_see_party.
-- can_see_party is deliberately SECURITY INVOKER — it works by asking whether a
-- party row is visible to the CALLER — so inside a DEFINER function it would run
-- as the owner and answer "yes" for everything, including test toques. is_dev()
-- is itself DEFINER and reads auth.uid(), so it behaves correctly in here.
--
-- That duplicates `party`'s own SELECT predicate. If that policy changes, this
-- has to change with it.
create or replace function public.party_rsvp_count(p_party bigint)
returns integer language sql stable security definer set search_path = '' as $$
  select case
    when exists (
      select 1 from public.party p
      where p.id = p_party and (p.is_test = false or public.is_dev())
    )
    then (select count(*)::int from public.party_rsvp r where r.party_id = p_party)
    else 0
  end;
$$;

revoke all on function public.party_rsvp_count(bigint) from public;
grant execute on function public.party_rsvp_count(bigint) to anon, authenticated;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (party_rsvp_count joins Functions).
--
-- VERIFY as a signed-in NON-organiser of a toque that has RSVPs:
--   /party_rsvp?party_id=eq.<id>&select=user_id   -> only your own row, if any
--   rpc/party_rsvp_count  {"p_party": <id>}       -> the true total
--
-- and as an ANONYMOUS caller:
--   /party_rsvp?select=user_id                    -> []
--   rpc/party_rsvp_count on a test toque          -> 0
-- =============================================================================
