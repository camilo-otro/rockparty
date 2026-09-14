-- =============================================================================
-- Migration: signing a band up puts the song in the band's set (#110)
-- Date: 2026-09-14
-- =============================================================================
-- ADDITIVE / corrective. Replaces sign_band_up(); no schema or policy change.
--
-- -----------------------------------------------------------------------------
-- The gap
-- -----------------------------------------------------------------------------
-- Band sets had no creation path for new data. The nine that exist were derived
-- by 20260911_band_sets.sql's backfill from historical contiguous runs, while
-- sign_band_up wrote `performance.band_id` and never touched `set_id`.
--
-- Found in live test data: capibear signed band 3 up for three songs on party
-- 41, and all three sat in OPEN set 12 while carrying band_id = 3.
--
--   perf 238 House of Gold   band 3  ->  set 12 (open)
--   perf 239 Shy Away        band 3  ->  set 12 (open)
--   perf 240 Next Semester   band 3  ->  set 12 (open)
--
-- Two things break there, and both are the thing this ticket exists to fix:
--
--   * The BAND cannot reorder its own songs. can_edit_set on an open set is the
--     ORGANIZER, so a band that signs up has to ask the organizer to arrange the
--     songs it just committed to play.
--   * Once the setlist groups by set, those songs render as loose open rows.
--     The #74 grouping (consecutive band_id) shows them as a block today, so
--     shipping the set-based UI would REGRESS the display for every band that
--     signs up after the backfill.
--
-- -----------------------------------------------------------------------------
-- The decision
-- -----------------------------------------------------------------------------
-- sign_band_up now joins the band's set on that party, creating one at the end
-- of the night when the band has none. A band's songs are its block; that is the
-- premise of the whole feature, and nothing else was going to create the block.
--
-- The trade, taken deliberately: a band can now insert a block into someone
-- else's running order by signing up, and the song jumps from wherever it sat
-- into that block. The organizer's counterweight is unchanged — party_set writes
-- are admin-only, so they can move the block or delete it (which cascades its
-- songs, as already decided).
--
-- Note this is the one place a party_set row is created by someone who is not a
-- party admin. It is safe only because sign_band_up is SECURITY DEFINER and has
-- already checked can_sign_up_band() at the top.
-- =============================================================================

begin;

create or replace function public.sign_band_up(p_performance bigint, p_band bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_party bigint; v_party_title text; v_song_title text; v_band_name text;
  v_uid uuid := (select auth.uid());
  v_set bigint; v_old_set bigint;
begin
  if not public.can_sign_up_band(p_band) then
    raise exception 'not allowed to sign up this band';
  end if;

  -- A test band may not play a real event (would leak its lineup on a public
  -- setlist). The reverse — a real band on a test toque — is fine (#76).
  if exists (
    select 1 from public.band b
    join public.performance perf on perf.id = p_performance
    join public.party pt on pt.id = perf.party
    where b.id = p_band and b.is_test = true and pt.is_test = false
  ) then
    raise exception 'a test band cannot sign up for a real event';
  end if;

  update public.performance
    set band_id = p_band
    where id = p_performance and (band_id is null or band_id = p_band);
  if not found then
    raise exception 'song not available for this band';
  end if;

  insert into public.performance_user (performance_id, user_id, instrument_id, band_id)
  select p_performance, bmi.user_id, bmi.instrument_id, p_band
  from public.band_member_instrument bmi
  where bmi.band_id = p_band
  on conflict (performance_id, instrument_id, user_id) do nothing;

  select perf.party, pt.title, s.title, b.name
    into v_party, v_party_title, v_song_title, v_band_name
  from public.performance perf
  join public.party pt on pt.id = perf.party
  left join public.song s on s.id = perf.song
  join public.band b on b.id = p_band
  where perf.id = p_performance;

  -- #110: a band's songs ARE its block, so signing up puts the song in the
  -- band's set — creating one at the end of the night if the band has none yet.
  --
  -- Without this, band sets had no creation path for new data: the ones that
  -- exist were derived by the backfill from history, while sign_band_up wrote
  -- band_id and left set_id alone. The song then sat in an OPEN set, which means
  -- the BAND could not reorder its own song (the open set belongs to the
  -- organizer) and the setlist would render it as a loose row rather than part
  -- of the block. Both are the problem this ticket exists to fix.
  --
  -- The trade this makes, deliberately: a band can now put a block into someone
  -- else's running order by signing up, and the song jumps from wherever it sat
  -- into the band's block. The organizer's counterweight is the one they already
  -- have — party_set writes are admin-only, so they can move or delete the block.
  --
  -- Last set, not first, when a band already plays twice: the newest song joins
  -- the most recent block, and the band can move it with move_song_to_set.
  select set_id into v_old_set from public.performance where id = p_performance;

  select id into v_set
  from public.party_set
  where party_id = v_party and band_id = p_band
  order by "order" desc, id desc
  limit 1;

  if v_set is null then
    insert into public.party_set (party_id, band_id, "order")
    select v_party, p_band, (coalesce(max("order"), 0) + 1)::smallint
    from public.party_set where party_id = v_party
    returning id into v_set;
  end if;

  if v_old_set is distinct from v_set then
    -- Normalise the destination to 1..n before appending. The backfill
    -- deliberately does not renumber "order", so a set may hold legacy globals
    -- and a raw count+1 can sort BEFORE them — the same trap that made
    -- move_song_to_set's append land first.
    with ordered as (
      select id, row_number() over (order by "order" nulls last, id) as ord
      from public.performance where set_id = v_set
    )
    update public.performance p set "order" = o.ord::smallint
    from ordered o where p.id = o.id;

    update public.performance
    set set_id = v_set,
        "order" = ((select count(*) from public.performance where set_id = v_set) + 1)::smallint
    where id = p_performance;
    -- An open set emptied by that move is collected by trg_gc_empty_open_set,
    -- which fires on update of set_id.
  end if;

  if exists (
    select 1 from public.performance_user pu
    where pu.performance_id = p_performance and pu.band_id = p_band and pu.status = 'pending'
  ) then
    insert into public.notification (recipient, type, payload)
    select r.uid, 'band_signup_requested',
           jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                              'band_id', p_band, 'band_name', v_band_name,
                              'song_title', v_song_title, 'performance_id', p_performance)
    from (
      select pt.created_by as uid from public.party pt where pt.id = v_party and pt.created_by is not null
      union
      select pa.user_id from public.party_admin pa where pa.party_id = v_party
    ) r
    where r.uid is not null and r.uid <> v_uid;
  end if;
end; $$;

commit;

-- =============================================================================
-- After applying: schema.sql is updated to match. No type regeneration — the
-- signature is unchanged.
--
-- Existing stranded rows are NOT migrated here, because the only ones are in
-- test party 41 and moving them would rewrite a running order while the feature
-- is still being tested. Re-running sign_band_up for those songs fixes them, or
-- they can be moved by hand.
-- =============================================================================
