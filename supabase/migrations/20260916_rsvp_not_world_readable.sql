-- =============================================================================
-- Migration: who is attending a toque stops being world-readable
-- Date: 2026-09-16
-- =============================================================================
-- SAFE TO APPLY NOW, before any client deploy. Nothing the client reads today
-- falls outside the new rule — it only ever asks about a toque it is already
-- showing, which by definition passes can_see_party().
--
-- `party_rsvp` SELECT is `to anon, authenticated using (true)`: a complete
-- person-to-event mapping for every toque, to anyone with the anon key. Verified
-- against production as an anonymous caller:
--
--   GET /rest/v1/party_rsvp?select=party_id,user_id
--     [{"party_id":25,"user_id":"0671ee04-..."}, {"party_id":37, ...}]
--
-- On its own that is the thing #102 removed elsewhere — publishing who is
-- associated with what. Joined against a venue's address it is worse: a guest
-- list and a home address in two requests.
--
-- can_see_party() is the right gate and already exists. It is SECURITY INVOKER,
-- leaning on party's own SELECT policy, so an RSVP is visible exactly when the
-- toque is — and it will inherit whatever the private/unlisted work in
-- docs/specs/private-events.md adds later, with no further change here.
--
-- What still works after this:
--   * the flyer's "N asisten" count, read by anon on a confirmed toque
--   * "voy / no voy" on the party page, which reads the viewer's own row
--   * the home page's own-RSVP lookup
-- All three only ever touch a toque the caller can already see.
--
-- NOT changed here, and both are the same class — they are listed in the spec so
-- they are not forgotten:
--   * party_admin  SELECT using (true)  -> who organises what, to any signed-in user
--   * applause     SELECT using (true)  -> who applauded whom
-- =============================================================================

begin;

drop policy if exists "allow select to all users" on public.party_rsvp;
drop policy if exists "party_rsvp select: parent party visible" on public.party_rsvp;
create policy "party_rsvp select: parent party visible" on public.party_rsvp
  for select to anon, authenticated
  using (public.can_see_party(party_rsvp.party_id));

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration — only a
-- policy changed.
--
-- VERIFY as an ANONYMOUS caller over REST:
--   /party_rsvp?select=party_id,user_id
--     -> rows only for toques anon can already see (confirmed / live / completed
--        and not is_test); nothing for a draft or a test toque.
--   /party_rsvp?select=user_id&party_id=eq.<a real confirmed toque>
--     -> still returns, so the flyer's count is unaffected.
-- =============================================================================
