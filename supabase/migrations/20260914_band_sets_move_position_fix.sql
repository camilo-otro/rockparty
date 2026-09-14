-- =============================================================================
-- Migration: move_song_to_set lands at the position you asked for (#110)
-- Date: 2026-09-14
-- =============================================================================
-- ADDITIVE / corrective. Replaces the function body from
-- 20260914_band_sets_ownership.sql; nothing else changes. Nothing in the client
-- calls it yet, so this can be applied whenever.
--
-- -----------------------------------------------------------------------------
-- The bug, found by running it
-- -----------------------------------------------------------------------------
-- Two of my own decisions collided:
--
--   * 20260911_band_sets.sql deliberately does NOT renumber `performance."order"`
--     during the backfill. That is what let the migration ship before the client,
--     and it leaves the existing data holding its legacy GLOBAL positions — the
--     first open set of party 11 runs 0..13, its band set 14..15, the next open
--     set 16..20.
--   * move_song_to_set treated p_position as a 1-based position and then used it
--     directly as a sort key against those raw values.
--
-- Those are only the same number when a set happens to be numbered 1..n.
-- Measured against party 11:
--
--   move(perf 125 -> set 4, position 1)  landed it at position 2
--     set 4 starts at order 0, so the incoming row tied with the SECOND song
--     instead of the first.
--
--   move(perf X -> set 5, append)  would have landed it FIRST
--     append computes v_pos = count + 1 = 3, and set 5's legacy orders are
--     14 and 15, so 3 sorts before both. This is the same bug at its worst: the
--     append path is the one the UI will use most, and it would have silently
--     put the song at the top of the destination.
--
-- -----------------------------------------------------------------------------
-- The fix
-- -----------------------------------------------------------------------------
-- Normalise the destination to 1..n BEFORE inserting, so p_position and the sort
-- key are measured on the same scale. Then the existing tie-break does what it
-- was always meant to: the incoming row ties with whatever currently occupies
-- that position and wins, landing at it.
--
-- The lesson worth keeping: "the backfill does not renumber" is load-bearing for
-- the deploy ordering, so nothing downstream may assume "order" is 1..n. Any
-- future code that reads a position out of "order" has the same trap waiting.
-- =============================================================================

begin;

create or replace function public.move_song_to_set(
  p_performance bigint,
  p_set bigint,
  p_position int default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_source bigint;
  v_party  bigint;
  v_target_party bigint;
  v_count  int;
  v_pos    int;
begin
  select set_id, party into v_source, v_party
  from public.performance where id = p_performance;

  if not found then
    raise exception 'that song is not on any setlist';
  end if;

  -- Both ends, not just the destination. Without the source check a band could
  -- lift a song OUT of someone else's set, which is the same harm as dropping
  -- one in. can_edit_set is the ownership rule: the band for a band set, the
  -- organizer for an open one.
  if v_source is null or not public.can_edit_set(v_source) then
    raise exception 'you cannot take a song out of that set';
  end if;
  if not public.can_edit_set(p_set) then
    raise exception 'you cannot put a song into that set';
  end if;

  select party_id into v_target_party from public.party_set where id = p_set;
  if v_target_party is null then
    raise exception 'that set does not exist';
  end if;
  -- Both sets must belong to the same toque, or performance.party would end up
  -- disagreeing with party_set.party_id.
  if v_target_party <> v_party then
    raise exception 'that set belongs to a different toque';
  end if;

  if v_source = p_set then
    -- Same set: this is a reorder, and reorder_set_songs is the tool for it.
    return;
  end if;

  select count(*) into v_count from public.performance where set_id = p_set;
  v_pos := coalesce(p_position, v_count + 1);
  if v_pos < 1 then v_pos := 1; end if;
  if v_pos > v_count + 1 then v_pos := v_count + 1; end if;

  -- THE FIX. Put the destination on a 1..n scale first, so p_position and the
  -- sort key below mean the same thing. Without this the incoming row is
  -- compared against whatever legacy values the set happens to hold, which the
  -- backfill deliberately left alone.
  with ordered as (
    select id, row_number() over (order by "order" nulls last, id) as ord
    from public.performance where set_id = p_set
  )
  update public.performance p
  set "order" = o.ord::smallint
  from ordered o where p.id = o.id;

  update public.performance
  set set_id = p_set,
      -- Ties with the row now occupying v_pos; the tie-break below puts the
      -- incoming song first, i.e. AT v_pos.
      "order" = v_pos::smallint,
      -- band_id follows the set: a song sitting in a band's block IS that
      -- band's, and a stale band_id would render a lineup for a song the band
      -- no longer plays.
      band_id = (select band_id from public.party_set where id = p_set)
  where id = p_performance;

  with ordered as (
    select id, row_number() over (
      order by "order" nulls last, case when id = p_performance then 0 else 1 end, id
    ) as ord
    from public.performance where set_id = p_set
  )
  update public.performance p
  set "order" = o.ord::smallint
  from ordered o where p.id = o.id;

  -- The set it left, also normalised, so a later move into it behaves.
  with ordered as (
    select id, row_number() over (order by "order" nulls last, id) as ord
    from public.performance where set_id = v_source
  )
  update public.performance p
  set "order" = o.ord::smallint
  from ordered o where p.id = o.id;
end;
$$;

revoke all on function public.move_song_to_set(bigint, bigint, int)
  from public, anon, authenticated;
grant execute on function public.move_song_to_set(bigint, bigint, int) to authenticated;

commit;

-- =============================================================================
-- After applying: no schema.sql table/column change, but the function body there
-- needs the same edit. No type regeneration — the signature is unchanged.
-- =============================================================================
