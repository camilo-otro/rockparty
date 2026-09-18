-- =============================================================================
-- Migration: a private venue's equipment stops being public (#113)
-- Date: 2026-09-18
-- =============================================================================
-- APPLY NOW, BEFORE the stage 2 drop. It only narrows a SELECT, so no client
-- breaks: everyone who can currently USE this data still sees it.
--
-- -----------------------------------------------------------------------------
-- The leak
-- -----------------------------------------------------------------------------
-- venue_equipment was `for select ... using (true)` to anon. The first pass took
-- the address, phone and contact name off private venues and left this behind,
-- which turns out to be the worst one. Read with the anon key — the one that
-- ships inside the JS bundle — for a private home:
--
--   GET /rest/v1/venue_equipment?venue_id=eq.<a home>&select=quantity,notes,equipment(name)
--
--     Sistema de sonido (PA)   x1   <named brand and model>
--     Consola de mezcla        x1   <named brand and model>
--     Micrófonos               x2   <named brand and model>
--     Batería (sin platillos)  x1   <named brand and model>
--     Amplificador de guitarra x1   <named brand and model>
--     Amplificador de bajo     x1   <named brand and model>
--     Teclado/Piano            x1   <named brand and model>
--
-- An itemised inventory of several thousand dollars of gear, by brand and model,
-- attached to a venue whose NAME and NEIGHBOURHOOD are public by design. The
-- address was one field; this is a shopping list with directions.
--
-- Models redacted above: this repo is public.
--
-- -----------------------------------------------------------------------------
-- Same rule as venue_contact, deliberately
-- -----------------------------------------------------------------------------
-- A public venue's backline is useful to advertise — a musician wants to know
-- whether to bring an amp. A private one's is nobody's business until you are
-- actually going, which is the exact set can_see_venue_contact already names:
-- the venue's admins, the organiser of a toque booked there, anyone who RSVP'd,
-- and anyone approved to play.
--
-- That is also precisely who needs it: logistics (#95/#97) sources requirements
-- from a venue, and every one of those people is inside the set.
--
-- The `exists` subquery on venue is read AS THE CALLER, so venue's own SELECT
-- policy applies again and a test venue falls through to can_see_venue_contact.
-- That direction is restrictive, never permissive, and it matches the existing
-- venue_contact policy — worth keeping the two identical so they cannot drift.
-- =============================================================================

begin;

drop policy if exists "allow select to all users" on public.venue_equipment;

create policy "venue_equipment: public venues, or people going" on public.venue_equipment
  for select to anon, authenticated
  using (
    exists (select 1 from public.venue v where v.id = venue_equipment.venue_id and v.private = false)
    or public.can_see_venue_contact(venue_equipment.venue_id)
  );

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration.
--
-- VERIFY as an ANONYMOUS caller:
--   /venue_equipment?select=venue_id,notes  -> no rows for any private venue,
--                                              unchanged for public ones
-- =============================================================================
