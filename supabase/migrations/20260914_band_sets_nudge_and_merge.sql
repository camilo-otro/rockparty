-- =============================================================================
-- Migration: blocks merge, and a song can hop over one (#110)
-- Date: 2026-09-14
-- =============================================================================
-- ADDITIVE. Two behaviours the spec called for that neither the schema nor the
-- UI actually delivered.
--
-- -----------------------------------------------------------------------------
-- 1. Adjacent open blocks merge
-- -----------------------------------------------------------------------------
-- Two open blocks side by side are not a thing the model should be able to
-- express: an open block IS "the loose songs here", so two of them in a row is
-- one block that happens to be stored twice. It shows up as a stray gap in the
-- setlist and, worse, as two separate `+` targets that mean the same place.
--
-- It happens whenever something between them goes away — an organizer deleting a
-- band's block is the main way, and `reorder_sets` can produce it directly by
-- moving a band's block out from between two open ones.
--
-- normalize_party_sets() folds each run of adjacent open blocks into its first
-- member and renumbers the night 1..n. It is called at the end of every
-- operation that can create the situation, and by a trigger on party_set delete.
--
-- -----------------------------------------------------------------------------
-- 2. A song hops OVER a band's block, never into it
-- -----------------------------------------------------------------------------
-- From the spec:
--
--   "With [Open A] [Pulse] [Open B], a song at the bottom of Open A pressing
--    DOWN lands at the TOP of Open B — after Pulse, not inside it. If no open
--    set follows, one is created."
--
-- move_song_to_set could already express this, but nothing could *drive* it: the
-- UI only knew how to swap two songs inside one set, so the arrows went dead at
-- a block boundary and the move was simply unavailable.
--
-- nudge_song() is what the arrows call now. One entry point, so the rule about
-- where a song may land lives in one place instead of being reconstructed in the
-- client:
--
--   * inside the block            -> swap with the neighbour
--   * at the edge of an OPEN block -> skip the next band block entirely and land
--                                     at the near end of the next open one
--   * nothing open that way, down  -> create a new open block at the end
--   * nothing open that way, up    -> already at the top; do nothing
--   * at the edge of a BAND block  -> do nothing. A band's songs stay in the
--                                     band's block; pushing one out into the
--                                     organizer's open list is not the band's
--                                     call, and the ownership rule would refuse
--                                     it anyway.
--
-- Permission is unchanged and still comes from can_edit_set at both ends, so a
-- band can nudge within its own set and an organizer can move loose songs
-- across the night, and neither can reach into the other's block.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- normalize_party_sets
-- -----------------------------------------------------------------------------
create or replace function public.normalize_party_sets(p_party bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_prev_id   bigint  := null;
  v_prev_open boolean := false;
  v_offset    int;
begin
  for r in
    select id, band_id from public.party_set where party_id = p_party order by "order", id
  loop
    if v_prev_open and r.band_id is null then
      -- Append this block's songs to the previous open block, keeping their
      -- relative order, then drop the now-empty block. row_number() rather than
      -- the raw "order", because the backfill deliberately leaves legacy values.
      select coalesce(max("order"), 0) into v_offset
      from public.performance where set_id = v_prev_id;

      with ordered as (
        select id, row_number() over (order by "order" nulls last, id) as ord
        from public.performance where set_id = r.id
      )
      update public.performance p
      set set_id = v_prev_id, "order" = (v_offset + o.ord)::smallint
      from ordered o where p.id = o.id;

      -- Usually already gone: the GC trigger on performance fires as the rows
      -- above change set_id. This covers an open block that was empty already.
      delete from public.party_set where id = r.id;
    else
      v_prev_id := r.id;
      v_prev_open := r.band_id is null;
    end if;
  end loop;

  with ordered as (
    select id, row_number() over (order by "order", id) as ord
    from public.party_set where party_id = p_party
  )
  update public.party_set s set "order" = o.ord::smallint
  from ordered o where s.id = o.id;
end;
$$;

-- Deleting a band's block can leave the open blocks either side of it adjacent.
create or replace function public.merge_open_sets_after_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Only for a delete somebody actually asked for. Depth > 1 means we are
  -- already inside another trigger — the performance GC, or normalize's own
  -- deletes — where re-entering would recurse.
  if pg_trigger_depth() > 1 then
    return null;
  end if;
  perform public.normalize_party_sets(old.party_id);
  return null;
end;
$$;

drop trigger if exists trg_merge_open_sets on public.party_set;
create trigger trg_merge_open_sets
  after delete on public.party_set
  for each row execute function public.merge_open_sets_after_delete();

-- -----------------------------------------------------------------------------
-- nudge_song — what the up/down arrows call
-- -----------------------------------------------------------------------------
create or replace function public.nudge_song(p_performance bigint, p_dir int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_set    bigint;
  v_party  bigint;
  v_band   bigint;
  v_order  smallint;
  v_pos    int;
  v_count  int;
  v_target bigint;
begin
  if p_dir not in (-1, 1) then
    raise exception 'direction must be -1 or 1';
  end if;

  select set_id, party into v_set, v_party
  from public.performance where id = p_performance;
  if not found or v_set is null then
    raise exception 'that song is not on a setlist';
  end if;
  if not public.can_edit_set(v_set) then
    raise exception 'you cannot rearrange this set';
  end if;

  -- Positions on a 1..n scale before any arithmetic, for the same reason
  -- move_song_to_set normalises: the backfill leaves legacy globals behind.
  with ordered as (
    select id, row_number() over (order by "order" nulls last, id) as ord
    from public.performance where set_id = v_set
  )
  update public.performance p set "order" = o.ord::smallint
  from ordered o where p.id = o.id;

  select "order" into v_pos from public.performance where id = p_performance;
  select count(*) into v_count from public.performance where set_id = v_set;

  -- The ordinary case: swap with the neighbour inside this block.
  if (p_dir = -1 and v_pos > 1) or (p_dir = 1 and v_pos < v_count) then
    update public.performance
    set "order" = v_pos::smallint
    where set_id = v_set and "order" = (v_pos + p_dir)::smallint;
    update public.performance
    set "order" = (v_pos + p_dir)::smallint
    where id = p_performance;
    return;
  end if;

  -- At the edge. A band's song stays in the band's block.
  select band_id, "order" into v_band, v_order from public.party_set where id = v_set;
  if v_band is not null then
    return;
  end if;

  -- The nearest OPEN block that way. Band blocks in between are skipped whole,
  -- which is the point: a single button cannot ask "over or into?", so the
  -- movement that would drop a stranger's song inside a band's set does not
  -- exist at all.
  if p_dir = 1 then
    select id into v_target from public.party_set
    where party_id = v_party and band_id is null and "order" > v_order
    order by "order" limit 1;
  else
    select id into v_target from public.party_set
    where party_id = v_party and band_id is null and "order" < v_order
    order by "order" desc limit 1;
  end if;

  if v_target is null then
    -- Nothing open above: this song is already at the top of the night.
    if p_dir = -1 then
      return;
    end if;
    -- Nothing open below, i.e. the night ends with a band's block. Start a new
    -- open block after it. Creating a block is the organizer's.
    if not public.is_party_admin(v_party) then
      return;
    end if;
    insert into public.party_set (party_id, band_id, "order")
    select v_party, null, (coalesce(max("order"), 0) + 1)::smallint
    from public.party_set where party_id = v_party
    returning id into v_target;
  end if;

  -- Down lands at the TOP of the next block, up lands at the BOTTOM of the
  -- previous one — i.e. the song keeps travelling in the direction pressed.
  perform public.move_song_to_set(p_performance, v_target, case when p_dir = 1 then 1 else null end);
  perform public.normalize_party_sets(v_party);
end;
$$;

-- reorder_sets can leave two open blocks adjacent by moving a band's out from
-- between them, so it tidies up after itself.
create or replace function public.reorder_sets(p_party bigint, p_set_ids bigint[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_count int;
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can reorder the running order';
  end if;

  select count(*) into v_count from public.party_set where party_id = p_party;
  if v_count <> coalesce(array_length(p_set_ids, 1), 0) then
    raise exception 'expected % set ids for this toque, got %',
      v_count, coalesce(array_length(p_set_ids, 1), 0);
  end if;

  if exists (
    select 1 from unnest(p_set_ids) as t(id)
    where not exists (
      select 1 from public.party_set s where s.id = t.id and s.party_id = p_party
    )
  ) then
    raise exception 'one of those sets does not belong to this toque';
  end if;

  update public.party_set s
  set "order" = t.ord::smallint
  from unnest(p_set_ids) with ordinality as t(id, ord)
  where s.id = t.id;

  perform public.normalize_party_sets(p_party);
end;
$$;

revoke all on function public.nudge_song(bigint, int) from public, anon, authenticated;
grant execute on function public.nudge_song(bigint, int) to authenticated;
revoke all on function public.normalize_party_sets(bigint) from public, anon, authenticated;
revoke all on function public.merge_open_sets_after_delete() from public, anon, authenticated;
revoke all on function public.reorder_sets(bigint, bigint[]) from public, anon, authenticated;
grant execute on function public.reorder_sets(bigint, bigint[]) to authenticated;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (nudge_song is new; reorder_sets is unchanged in
-- signature).
--
-- Note normalize_party_sets is EXECUTABLE BY NOBODY on purpose — it is a helper
-- the definer functions call, never something a client should be able to run on
-- an arbitrary party.
-- =============================================================================
