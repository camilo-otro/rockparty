-- =============================================================================
-- Migration: live mode — Stage 2 (#37), the messy-reality controls
-- Date: 2026-09-05
-- =============================================================================
-- Stage 1 covers a show that runs exactly to plan. Real ones don't: acts run
-- long, someone calls an encore, a band isn't ready, the admin fat-fingers Next.
-- These four make every action correctable without touching the DB by hand.
--
-- All SECURITY INVOKER — RLS stays the authorization boundary, exactly as in
-- Stage 1. Each is one RPC so the multi-row change is atomic and the
-- performance_one_playing_per_party invariant is never momentarily violated:
-- the current row is always cleared BEFORE another is set to 'playing'.
-- =============================================================================

begin;

-- Jump straight to any song — encores, running out of time, a band that's ready
-- early. Closes whatever is playing, then opens the target wherever it sits in
-- the running order (and whatever state it was in, so a played song can encore).
create or replace function public.jump_to_song(p_party bigint, p_performance bigint)
returns bigint
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can run the show';
  end if;

  if not exists (select 1 from public.performance where id = p_performance and party = p_party) then
    raise exception 'that song is not on this setlist';
  end if;

  -- Already the current song: nothing to do (and don't restart its clock).
  if exists (select 1 from public.performance
             where id = p_performance and live_state = 'playing') then
    return p_performance;
  end if;

  update public.performance
  set live_state = 'played', ended_at = now()
  where party = p_party and live_state = 'playing';

  update public.performance
  set live_state = 'playing', started_at = now(), ended_at = null
  where id = p_performance;

  return p_performance;
end;
$$;

-- Skip: this song isn't happening. Same shape as advance, but the current song
-- is recorded as 'skipped' rather than 'played' so history stays honest about
-- what the room actually heard.
create or replace function public.skip_song(p_party bigint)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_next bigint;
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can run the show';
  end if;

  update public.performance
  set live_state = 'skipped', ended_at = now()
  where party = p_party and live_state = 'playing';

  select id into v_next from public.performance
  where party = p_party and live_state = 'queued'
  order by "order" nulls last, id limit 1;

  if v_next is not null then
    update public.performance
    set live_state = 'playing', started_at = now(), ended_at = null
    where id = v_next;
  end if;

  return v_next;
end;
$$;

-- End the current song WITHOUT cueing the next — the break between acts, while
-- the next band sets up. The show stays live; nothing is playing.
create or replace function public.end_current_song(p_party bigint)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can run the show';
  end if;

  update public.performance
  set live_state = 'played', ended_at = now()
  where party = p_party and live_state = 'playing';
end;
$$;

-- Undo the last move. Puts the current song back to 'queued' and reopens the
-- most recently finished one, so a mis-tapped Next costs one tap to fix.
-- Also un-ends a show ended by mistake.
create or replace function public.undo_last_move(p_party bigint)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_prev bigint;
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can run the show';
  end if;

  -- The most recently finished song is the one to go back to.
  select id into v_prev from public.performance
  where party = p_party and live_state in ('played', 'skipped') and ended_at is not null
  order by ended_at desc, id desc limit 1;

  if v_prev is null then
    raise exception 'there is nothing to undo yet';
  end if;

  -- Clear the current song FIRST so the one-playing invariant never trips.
  update public.performance
  set live_state = 'queued', started_at = null, ended_at = null
  where party = p_party and live_state = 'playing';

  update public.performance
  set live_state = 'playing', ended_at = null
  where id = v_prev;

  -- Undoing straight after "end show" should put the show back on the air.
  update public.party set status = 'live'
  where id = p_party and status = 'completed';

  return v_prev;
end;
$$;

commit;
