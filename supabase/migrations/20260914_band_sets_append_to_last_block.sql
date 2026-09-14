-- =============================================================================
-- Migration: a loose song joins the LAST BLOCK, not the last open set (#110)
-- Date: 2026-09-14
-- =============================================================================
-- ADDITIVE / corrective. Replaces assign_performance_set() from
-- 20260911_band_sets.sql. No schema change, no policy change.
--
-- -----------------------------------------------------------------------------
-- The bug, found by running it
-- -----------------------------------------------------------------------------
-- docs/specs/band-sets.md is specific about where "Agregar canción" puts a song:
--
--   "The main Agregar canción at the bottom of the night adds an open song at
--    the end. If the last block is an open set it joins it; if the last block is
--    a BAND set, a new open set is created after it."
--
-- The trigger implemented something subtly different — "the highest-ordered OPEN
-- set" — which is the same thing only while no band set sits last.
--
-- Measured against test party 11, ordered [open@1] [open@2] [band@3]: a new
-- loose song landed in the open set at order 2, i.e. in the MIDDLE of the night,
-- ahead of the band. The button at the bottom of the setlist would have appeared
-- to insert songs somewhere else entirely.
--
-- This is exactly the shape the feature creates: the moment an organizer drags a
-- band's block to the end of the night — the headline use case of #110 — every
-- subsequent song added to that toque goes in front of it.
--
-- The fix is to ask for the last BLOCK and look at what it is, rather than
-- filtering to open sets up front.
-- =============================================================================

begin;

create or replace function public.assign_performance_set()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_set  bigint;
  v_band bigint;
begin
  if new.set_id is not null or new.party is null then
    return new;
  end if;

  -- The last block, whatever kind it is. `id desc` only breaks a tie between
  -- two sets that somehow share an order.
  select id, band_id into v_set, v_band
  from public.party_set
  where party_id = new.party
  order by "order" desc, id desc
  limit 1;

  -- Either there are no sets at all, or the night currently ends with a band's
  -- block — and a loose song may not join a band's set. Start a new open block
  -- after it.
  if v_set is null or v_band is not null then
    insert into public.party_set (party_id, band_id, "order")
    select new.party, null, (coalesce(max("order"), 0) + 1)::smallint
    from public.party_set where party_id = new.party
    returning id into v_set;
  end if;

  new.set_id := v_set;
  return new;
end;
$$;

revoke all on function public.assign_performance_set() from public, anon, authenticated;

commit;

-- =============================================================================
-- After applying: schema.sql needs the same function body. No type
-- regeneration — nothing about the signature or the tables changed.
--
-- Note this also closes a hole the old version left open: with a band set last,
-- the old trigger would attach a stranger's song to an OPEN set that sits before
-- the band, which is harmless; but had there been no open set at all it created
-- one correctly. The failure was only ever about POSITION, never about a song
-- landing inside a band's block — assign_performance_set has never selected a
-- band set.
-- =============================================================================
