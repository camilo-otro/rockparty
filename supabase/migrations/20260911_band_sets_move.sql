-- =============================================================================
-- Migration: moving a song between sets (#110, stage 1b)
-- Date: 2026-09-11
-- =============================================================================
-- ADDITIVE. Safe to apply before or after the matching deploy — nothing calls
-- this until the client grows the controls.
--
-- Fixes two gaps in 20260911_band_sets.sql, both found by asking "how does a
-- band move a song between its OWN two sets?".
--
-- -----------------------------------------------------------------------------
-- Gap 1: neither reorder RPC can move a song between sets
-- -----------------------------------------------------------------------------
-- reorder_sets and reorder_set_songs write ONLY "order", on purpose. But the
-- schema deliberately allows a band to play twice in a night (no unique
-- constraint on (party_id, band_id)), so "move this song from our first set to
-- our second" is an ordinary thing for a band to want — and it needs set_id
-- written, which neither RPC does.
--
-- The first instinct was to make cross-set moves party-admin-only, on the
-- grounds that admins already hold `performance` UPDATE. That is wrong: it
-- would send a band to the organizer to rearrange its own material, which is
-- the exact complaint this ticket exists to fix.
--
-- The rule is not about WHO the caller is, it is about WHICH TWO SETS they are
-- touching: you may move a song when you can edit BOTH ends. can_edit_set()
-- already answers that, and every case falls out of it with no special-casing:
--
--   Pulse set 1 -> Pulse set 3       band  / band        allowed
--   band -> an open block            band  / admin-only  refused
--   band A -> band B's set           band  / other band  refused
--   admin moves an open song over a
--     band block (the spec's
--     "skip over, never into")       admin / admin       allowed
--   admin -> into a band's set       admin / admin       allowed
--
-- The skip-over behaviour is therefore not a separate mechanism; it is this one
-- with both ends open.
--
-- -----------------------------------------------------------------------------
-- Gap 2: the GC only fired on DELETE
-- -----------------------------------------------------------------------------
-- gc_empty_open_set was an AFTER DELETE trigger, so an open set emptied by
-- MOVING its last song out — which was impossible before this migration and is
-- routine after it — would have been left behind as an empty block forever.
-- It now fires on UPDATE OF set_id too.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Gap 2 first, so the move RPC below can rely on it.
-- -----------------------------------------------------------------------------
-- OLD.set_id is the set being LEFT, on both paths: the row's old set on an
-- update, and its only set on a delete. Guarded by `is distinct from` on update
-- so an ordinary reorder (which never touches set_id) does no work.
create or replace function public.gc_empty_open_set()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.set_id is null then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.set_id is not distinct from old.set_id then
    return null;
  end if;
  delete from public.party_set s
  where s.id = old.set_id
    and s.band_id is null
    and not exists (select 1 from public.performance p where p.set_id = s.id);
  return null;
end;
$$;

drop trigger if exists trg_gc_empty_open_set on public.performance;
create trigger trg_gc_empty_open_set
  after delete or update of set_id on public.performance
  for each row execute function public.gc_empty_open_set();

-- -----------------------------------------------------------------------------
-- Move one song into another set
-- -----------------------------------------------------------------------------
-- p_position is 1-based and clamped; null appends. Both ends are renumbered to
-- a clean 1..n, so no "order" drifts, duplicates or gaps survive a move — the
-- same self-healing the client's renumber-everything reorder already relies on.
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
  -- one in.
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
  -- Both sets must belong to the same toque. Without this, a caller who admins
  -- two parties could drag a song from one night into another, leaving
  -- performance.party disagreeing with party_set.party_id.
  if v_target_party <> v_party then
    raise exception 'that set belongs to a different toque';
  end if;

  if v_source = p_set then
    -- Same set: this is a reorder, and reorder_set_songs is the tool for it.
    return;
  end if;

  -- Where it lands. Written out rather than as nested greatest/least, because
  -- those IGNORE nulls in Postgres — greatest(null, 1) is 1, so the clever
  -- version silently turned "append" into "prepend".
  select count(*) into v_count from public.performance where set_id = p_set;
  v_pos := coalesce(p_position, v_count + 1);
  if v_pos < 1 then v_pos := 1; end if;
  if v_pos > v_count + 1 then v_pos := v_count + 1; end if;

  update public.performance
  set set_id = p_set,
      -- v_pos, not v_pos - 1: the incoming row must TIE with the row currently
      -- at that position and win the tie-break below, which puts it before that
      -- row. Tying with v_pos - 1 instead would land it one slot early.
      "order" = v_pos::smallint,
      -- band_id follows the set: a song sitting in a band's block IS that
      -- band's, and leaving a stale band_id behind is what would make the
      -- setlist render a lineup for a song the band no longer plays.
      band_id = (select band_id from public.party_set where id = p_set)
  where id = p_performance;

  -- Renumber both ends to a clean 1..n. The value set above is only a sort key;
  -- this is what turns it into a position, with the tie broken toward the
  -- incoming song so it lands AT p_position rather than after the row that was
  -- already there.
  with ordered as (
    select id, row_number() over (
      order by "order" nulls last, case when id = p_performance then 0 else 1 end, id
    ) as ord
    from public.performance where set_id = p_set
  )
  update public.performance p
  set "order" = o.ord::smallint
  from ordered o where p.id = o.id;

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
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (one new function; gc_empty_open_set replaced).
--
-- NOT guarded here, and worth knowing: moving the song that currently holds
-- live_state = 'playing'. It cannot strand the show — advance_show re-queries
-- for the next 'queued' song each time — but it does change what comes next
-- mid-set. The spec only asked for a live guard on set REMOVAL, which is stage
-- 2 along with the NOT NULL and the INSERT policy.
-- =============================================================================
