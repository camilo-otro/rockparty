-- =============================================================================
-- Migration: block test bands from signing up for real events (#76 follow-up)
-- Date: 2026-09-03
-- =============================================================================
-- #76 hid test bands (and their rosters) from real users at the band level, but
-- sign_band_up never compared the band's is_test to the party's. So a dev could
-- sign a test band up to a REAL (public) toque: the band name stays hidden
-- (can_see_band), but the performance_user lineup rows — real profiles — surface
-- on that public setlist. Close the leak in the RPC (the security boundary; the
-- UI dropdown also hides the option, but that's convenience, not enforcement).
--
-- Only the test-band -> real-event direction is blocked. A real band on a test
-- toque is harmless (test toques are dev-only visible) and stays allowed.
--
-- This recreates the current (notify) sign_band_up verbatim + the guard.
-- =============================================================================

begin;

create or replace function public.sign_band_up(p_performance bigint, p_band bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_party bigint; v_party_title text; v_song_title text; v_band_name text;
  v_uid uuid := (select auth.uid());
begin
  if not public.can_sign_up_band(p_band) then
    raise exception 'not allowed to sign up this band';
  end if;

  -- A test band may not play a real event (would leak its lineup on a public
  -- setlist). The reverse — a real band on a test toque — is fine.
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
