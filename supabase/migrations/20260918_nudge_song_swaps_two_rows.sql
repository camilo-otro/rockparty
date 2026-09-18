-- =============================================================================
-- Migration: nudge_song moves two rows, not the whole set (#110, #59)
-- Date: 2026-09-18
-- =============================================================================
-- ADDITIVE. Replaces one function body; safe to apply before or after a client
-- deploy, since the signature and the observable behaviour are unchanged.
--
-- -----------------------------------------------------------------------------
-- Why
-- -----------------------------------------------------------------------------
-- Every call renumbered the ENTIRE set to 1..n before doing any arithmetic:
--
--   with ordered as (select id, row_number() over (order by "order" nulls last, id) ...)
--   update public.performance p set "order" = o.ord ...
--
-- So shifting one song by one place rewrote every row in its block. Postgres
-- emits one realtime change event PER ROW, and the party page reloads its whole
-- setlist on each event, so one tap on a ten-song set produced ~12 events and
-- ~12 full reloads in every connected client. That noise is what made a
-- reordering race show up in the wild: a reload begun before a tap could land
-- after it and repaint the old order.
--
-- The renumbering was defensive — the #110 backfill deliberately left legacy
-- values behind. But measuring what it was defending against:
--
--   set 1   0..8         set 19  2..13      (legacy global numbering)
--   set 2   0..22        set 24  1,3,4,5    (a deleted song)
--   set 7   0..9         set 8   10..14
--
-- Seven of twelve sets were "dirty", and every single one was STRICTLY
-- INCREASING with no duplicates and no nulls. Offsets and gaps, nothing else.
-- Relative order was already correct everywhere.
--
-- A swap does not need 1..n. It needs relative order. So this finds the
-- neighbour in the direction of travel and exchanges the two values: two rows,
-- two events, and it works unchanged on a 0-based or gappy set.
--
-- -----------------------------------------------------------------------------
-- What still needs renumbering, and when
-- -----------------------------------------------------------------------------
-- ("order", id) is only a usable sort key while every row has a DISTINCT NON-NULL
-- order. A null cannot be compared, and two rows sharing a value would swap to
-- no visible effect. So the renumbering is kept, but behind a check — a set pays
-- for it at most once, because afterwards it is 1..n forever.
--
-- Safe to swap in two statements: there is no unique index on (set_id, "order"),
-- only the plain btree idx_performance_set, so the intermediate state where both
-- rows briefly hold the same value violates nothing.
-- =============================================================================

begin;

create or replace function public.nudge_song(p_performance bigint, p_dir integer)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_set bigint; v_party bigint; v_band bigint;
  v_order smallint; v_pos smallint; v_count int; v_target bigint;
  v_non_null int; v_distinct int;
  v_neighbor bigint; v_neighbor_pos smallint;
begin
  if p_dir not in (-1, 1) then
    raise exception 'direction must be -1 or 1';
  end if;
  select set_id, party into v_set, v_party from public.performance where id = p_performance;
  if not found or v_set is null then
    raise exception 'Esa canción no está en un setlist.';
  end if;
  if not public.can_edit_set(v_set) then
    raise exception 'No puedes reordenar este bloque.';
  end if;

  -- Renumber ONLY when ("order", id) is not a usable key: a null cannot be
  -- compared, and a duplicate would swap to no visible effect. A set pays this
  -- once and is 1..n from then on. Offsets and gaps are left alone — they sort
  -- perfectly well and rewriting them would cost the very events this avoids.
  select count(*), count("order"), count(distinct "order")
  into v_count, v_non_null, v_distinct
  from public.performance where set_id = v_set;

  if v_non_null <> v_count or v_distinct <> v_count then
    with ordered as (
      select id, row_number() over (order by "order" nulls last, id) as ord
      from public.performance where set_id = v_set
    )
    update public.performance p set "order" = o.ord::smallint
    from ordered o where p.id = o.id and p."order" is distinct from o.ord::smallint;
  end if;

  select "order" into v_pos from public.performance where id = p_performance;

  -- The adjacent song in the direction of travel, by RELATIVE position. The id
  -- tiebreak matches every other ordering in this schema, so "next" here is the
  -- same "next" the setlist renders.
  if p_dir = -1 then
    select id, "order" into v_neighbor, v_neighbor_pos
    from public.performance
    where set_id = v_set and ("order", id) < (v_pos, p_performance)
    order by "order" desc, id desc limit 1;
  else
    select id, "order" into v_neighbor, v_neighbor_pos
    from public.performance
    where set_id = v_set and ("order", id) > (v_pos, p_performance)
    order by "order" asc, id asc limit 1;
  end if;

  -- A neighbour inside the block: exchange the two values and stop. Two rows.
  --
  -- "No neighbour" is also how we now know the song sits at the edge of its
  -- block. That is not a nicety: the old code decided the edge arithmetically
  -- (v_pos > 1, v_pos < count) which was only ever safe BECAUSE it had just
  -- renumbered everything to 1..n. Stop renumbering and that test starts lying
  -- on any offset set — on orders 2..13 the first song reads as having room
  -- above it. Asking for the neighbour is correct whatever the numbering.
  if v_neighbor is not null then
    update public.performance set "order" = v_pos where id = v_neighbor;
    update public.performance set "order" = v_neighbor_pos where id = p_performance;
    return;
  end if;

  -- ---------------------------------------------------------------------------
  -- Past the edge of the block: unchanged from here down (#110).
  -- ---------------------------------------------------------------------------
  select band_id, "order" into v_band, v_order from public.party_set where id = v_set;
  if v_band is not null then
    return;
  end if;

  if p_dir = 1 then
    select id into v_target from public.party_set
    where party_id = v_party and band_id is null and "order" > v_order
    order by "order" limit 1;
  else
    select id into v_target from public.party_set
    where party_id = v_party and band_id is null and "order" < v_order
    order by "order" desc limit 1;
  end if;

  -- No open block that way: the night starts or ends with a band's block. Start
  -- a new open block beyond it, so a song can always reach either end of the
  -- night and the arrow is dead only at the true extremes.
  if v_target is null then
    if not public.is_party_admin(v_party) then
      return;
    end if;
    if p_dir = 1 then
      insert into public.party_set (party_id, band_id, "order")
      select v_party, null, (coalesce(max("order"), 0) + 1)::smallint
      from public.party_set where party_id = v_party
      returning id into v_target;
    else
      insert into public.party_set (party_id, band_id, "order")
      values (v_party, null, 0)
      returning id into v_target;
    end if;
  end if;

  perform public.move_song_to_set(p_performance, v_target, case when p_dir = 1 then 1 else null end);
  perform public.normalize_party_sets(v_party);
end;
$$;

revoke all on function public.nudge_song(bigint, integer) from public, anon;
grant execute on function public.nudge_song(bigint, integer) to authenticated;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration (the
-- signature is unchanged).
--
-- VERIFY, on a set with a legacy offset (party 11, set 19 is 2..13):
--   * nudge a middle song -> exactly TWO rows change "order", and the set keeps
--     its offset rather than being rewritten to 1..n
--   * nudge the FIRST song up -> it leaves the block (or stays put at the true
--     start of the night); it must not silently no-op
--   * nudge the last song of a band's block down -> still refused, still stays
-- =============================================================================
