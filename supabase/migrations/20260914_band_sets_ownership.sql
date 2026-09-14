-- =============================================================================
-- Migration: who owns a set's contents (#110, stage 1b)
-- Date: 2026-09-14
-- =============================================================================
-- ADDITIVE. Safe to apply before or after the matching deploy — nothing calls
-- move_song_to_set until the client grows the controls, and the can_edit_set
-- change only ever NARROWS what is allowed.
--
-- Two things, from one refinement and one question.
--
-- -----------------------------------------------------------------------------
-- The rule: a set's CONTENTS belong to its owner, its POSITION to the organizer
-- -----------------------------------------------------------------------------
-- Stage 1 had can_edit_set() return true for a party admin on ANY set. That was
-- wrong, and the refinement is worth stating as a principle because it settles
-- several other questions at once:
--
--   The organizer decides WHEN a band plays. The band decides WHAT it plays,
--   and in what order.
--
-- An organizer moving Pulse from the top of the night to the bottom is running
-- the event. An organizer reordering the songs inside Pulse's set is overruling
-- a band about its own material, which is not the organizer's call — and the
-- inability to arrange your own set is one of the three problems this ticket
-- opened with.
--
-- So can_edit_set() stops being "admin OR the band" and becomes a straight
-- question of ownership:
--
--   band set (band_id not null)  ->  can_sign_up_band(band_id)   -- the band, only
--   open set (band_id null)      ->  is_party_admin(party_id)    -- the organizer
--
-- Note what does NOT change: `party_set` rows themselves are still party-admin
-- only (the "party_set: admins manage" policy from stage 1). That is the other
-- half of the split and it was already right — creating a band's block, moving
-- it in the running order, and removing it are all the organizer's, and
-- reorder_sets() is still gated on is_party_admin(). This migration narrows
-- authority over what is INSIDE a block, and touches nothing about the block.
--
-- Consequence worth naming: a party admin can no longer add a song to, remove a
-- song from, or reorder a band's set. Their remedy if a band goes silent is the
-- one they already had — delete the set, which cascades its songs. This
-- CONTRADICTS a line in docs/specs/band-sets.md that had moving a song into a
-- band set available to "party admins and that band's members"; the spec has
-- been corrected rather than the other way round, because injecting a song into
-- a band's set is deciding their setlist just as much as reordering it is.
--
-- -----------------------------------------------------------------------------
-- move_song_to_set: because neither reorder RPC can cross sets
-- -----------------------------------------------------------------------------
-- Found by asking "how does a band move a song between its OWN two sets?" — a
-- case the schema deliberately allows, since a band may play twice in a night.
-- reorder_sets and reorder_set_songs write ONLY "order"; this needs set_id.
--
-- The gate is can_edit_set on BOTH ends — you may move a song when you own
-- where it comes from and where it goes. With the ownership rule above, every
-- case falls out with no special-casing:
--
--   Pulse set 1 -> Pulse set 3       band  / band    allowed
--   band -> an open block            band  / admin   refused
--   band A -> band B's set           band  / band B  refused
--   admin -> into a band's set       admin / band    refused  (was allowed)
--   admin pulls out of a band's set  band  / admin   refused  (was allowed)
--   admin moves an open song over a
--     band block (the spec's
--     "skip over, never into")       admin / admin   allowed
--
-- That last row is the point: skip-over is not a separate mechanism, it is this
-- one with both ends open. And an admin can never land a song INSIDE a band's
-- block, which is the property the spec wanted and now gets from the type
-- system of the rule rather than from a special case.
--
-- -----------------------------------------------------------------------------
-- Gap 2: the GC only fired on DELETE
-- -----------------------------------------------------------------------------
-- gc_empty_open_set was an AFTER DELETE trigger, so an open set emptied by
-- MOVING its last song out — impossible before this migration, routine after
-- it — would have been left behind as an empty block forever. It now fires on
-- UPDATE OF set_id too.
--
-- Stage 2 note: the `performance` INSERT tightening must follow the same rule —
-- open set OR a member of the set's band, and NOT "or a party admin".
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Ownership: supersedes the can_edit_set() from 20260911_band_sets.sql
-- -----------------------------------------------------------------------------
-- The band, and only the band, for a band set. The organizer, and only the
-- organizer, for an open one. can_sign_up_band() (not is_band_manager()) stays
-- the test of WHICH band members: it is what sign_band_up already uses, and it
-- reads band.who_can_sign_up, a setting the band itself chose.
create or replace function public.can_edit_set(sid bigint)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.party_set s
    where s.id = sid
      and case
            when s.band_id is not null then public.can_sign_up_band(s.band_id)
            else public.is_party_admin(s.party_id)
          end
  );
$$;

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
-- src/lib/database.types.ts (one new function; can_edit_set and
-- gc_empty_open_set replaced).
--
-- NOT guarded here, and worth knowing: moving the song that currently holds
-- live_state = 'playing'. It cannot strand the show — advance_show re-queries
-- for the next 'queued' song each time — but it does change what comes next
-- mid-set. The spec only asked for a live guard on set REMOVAL, which is stage
-- 2 along with the NOT NULL and the INSERT policy.
-- =============================================================================
