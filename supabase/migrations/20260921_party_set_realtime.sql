-- =============================================================================
-- Migration: party_set joins the realtime publication (#115, #110)
-- Date: 2026-09-21
-- =============================================================================
-- ADDITIVE. Safe to apply before or after the client deploy — a publication only
-- decides what is BROADCAST; nothing subscribes to it until the client does, and
-- an existing subscriber is unaffected.
--
-- -----------------------------------------------------------------------------
-- Why
-- -----------------------------------------------------------------------------
-- The publication was: notification, party, performance, performance_user.
--
-- Since #110 the running order of a night is (party_set."order",
-- performance."order"). Moving a band's whole block writes ONLY party_set, so it
-- produced no realtime event at all — every open client kept the old running
-- order until it was reloaded by hand.
--
-- That was the reported symptom at the first live show on 2026-09-19: "the live
-- view did not get updated after the band set changes". The console could not
-- learn about a block move even in principle, because nothing was broadcasting
-- it. (The deeper half of that bug was the console ordering by the wrong column
-- entirely; that is a client fix and ships alongside this.)
--
-- RLS still applies to realtime, so a subscriber only receives rows it could
-- SELECT. party_set has no SELECT policy of its own beyond the table's — worth
-- remembering if party visibility ever narrows (#113 part B): a block move on a
-- private toque would then broadcast only to people who can see that toque.
--
-- REPLICA IDENTITY stays default (primary key). The client treats any event as
-- "re-read the setlist" rather than reading columns off the payload, so the old
-- values are not needed and full replica identity would only cost WAL volume.
-- =============================================================================

begin;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'party_set'
  ) then
    alter publication supabase_realtime add table public.party_set;
  end if;
end $$;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration.
--
-- VERIFY:
--   select tablename from pg_publication_tables where pubname='supabase_realtime';
--     -> party_set is listed alongside performance / performance_user / party
--
-- Then, with the live console open on one device, reorder a band's block from
-- another: the running order should follow without a reload.
-- =============================================================================
