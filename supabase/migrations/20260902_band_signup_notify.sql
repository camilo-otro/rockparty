-- =============================================================================
-- Migration: band signup — single notification (#73, epic #40)
-- Date: 2026-09-02
-- =============================================================================
-- A band signup inserts one performance_user row per member×instrument. Without
-- this, notify_signup would fire per row and spam the organizer. So: skip band
-- rows in notify_signup, and emit ONE 'band_signup_requested' notification from
-- sign_band_up when the band's rows land pending (organizer mode, non-admin
-- signer). Approve/decline notifications for bands are handled by the approval
-- RPC in #74.
-- =============================================================================

begin;

-- notify_signup: skip band-tagged rows (bands notify once, elsewhere).
create or replace function public.notify_signup()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_party bigint; v_party_title text; v_song_title text;
  v_mode public.performer_approval; v_proponent uuid;
begin
  if new.band_id is not null then
    return new;                              -- bands notify once (sign_band_up / approval RPC)
  end if;

  select perf.party, pt.title, s.title, pt.performer_approval, perf.suggested_by
    into v_party, v_party_title, v_song_title, v_mode, v_proponent
  from public.performance perf
  join public.party pt on pt.id = perf.party
  left join public.song s on s.id = perf.song
  where perf.id = new.performance_id;

  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notification (recipient, type, payload)
    select r.uid, 'signup_requested',
           jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                              'song_title', v_song_title, 'performance_id', new.performance_id)
    from (
      select pt.created_by as uid from public.party pt where pt.id = v_party and pt.created_by is not null
      union
      select pa.user_id from public.party_admin pa where pa.party_id = v_party
      union
      select v_proponent where v_mode = 'proponent' and v_proponent is not null
    ) r
    where r.uid is not null and r.uid <> new.user_id;
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status and old.status = 'pending' then
    if new.status = 'approved' then
      insert into public.notification (recipient, type, payload)
      values (new.user_id, 'signup_approved',
              jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                                 'song_title', v_song_title, 'performance_id', new.performance_id));
    elsif new.status = 'declined' then
      insert into public.notification (recipient, type, payload)
      values (new.user_id, 'signup_declined',
              jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                                 'song_title', v_song_title, 'performance_id', new.performance_id));
    end if;
  end if;
  return new;
end; $$;

-- sign_band_up: as before, plus ONE notification to the organizer when the
-- band's rows land pending (needs approval).
create or replace function public.sign_band_up(p_performance bigint, p_band bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_party bigint; v_party_title text; v_song_title text; v_band_name text;
  v_uid uuid := (select auth.uid());
begin
  if not public.can_sign_up_band(p_band) then
    raise exception 'not allowed to sign up this band';
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
