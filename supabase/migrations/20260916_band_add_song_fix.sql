-- =============================================================================
-- Migration: adding a song for a band failed after the first (#110)
-- Date: 2026-09-16
-- =============================================================================
-- Two fixes, one a real bug reported from the app and one a papercut it exposed.
--
-- 1. THE BUG. Adding a song for a band succeeded once and then refused with an
--    RLS error every time after. Root cause and the reasoning are in the policy
--    comment below; in short, stage 2's WITH CHECK required the target block to
--    be VISIBLE, and the block the BEFORE INSERT trigger creates in the same
--    statement is not visible to the statement's own snapshot.
--
-- 2. THE MESSAGES. Every exception #110 raises was in English, and they reach
--    people directly — reportError puts error.message straight in the toast.
--    The app is Spanish ("English code, Spanish UI"), so these are UI copy and
--    are now Spanish. Only the strings changed; no logic is touched, and the
--    bodies below were regenerated from the live definitions rather than
--    retyped.
--
--    'direction must be -1 or 1' stays English on purpose: it can only be raised
--    by a caller passing something the UI never sends, so it is a programming
--    error, not a message for a musician.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- The INSERT policy, rewritten so it cannot refuse the legitimate path
-- -----------------------------------------------------------------------------
-- Stage 2 phrased the rule positively: "a row is allowed if its block EXISTS and
-- is open or mine". That reads correctly and is wrong, because of a Postgres
-- detail worth writing down.
--
-- The client never sends set_id. The BEFORE INSERT trigger picks a block, and
-- when the night ends with a band's block it CREATES a new open one. The RLS
-- WITH CHECK then runs in the OUTER statement, whose snapshot was taken before
-- the trigger fired — so the block the trigger just inserted IS NOT VISIBLE to
-- it. The EXISTS finds nothing and the insert is refused.
--
-- The symptom was exact and confusing: adding a song for a band worked once and
-- then never again. The first one joins an EXISTING open block (visible, fine);
-- sign_band_up then moves it into a new band block at the end of the night; and
-- from then on the night ENDS with a band block, so every later add needs a
-- freshly created open block and hits the invisibility.
--
-- Inverting it fixes it without loosening what matters. Refuse only what is
-- DEMONSTRABLY someone else's band block:
--
--   allowed  <=>  there is no visible party_set row for this set_id that is a
--                 band block I am not in
--
-- A block the statement cannot see yields no row and is allowed — which is
-- exactly right for the trigger's own block, because the trigger only ever
-- creates OPEN blocks. There is no way to reach a band's block by omitting
-- set_id. Passing a band block's id explicitly still finds the row and is still
-- refused, which is the attack this policy exists to stop.
--
-- The lesson generalises past this policy: a policy that requires a row to be
-- VISIBLE fails open-loop against anything a BEFORE trigger creates in the same
-- statement. Phrase such a check as "refuse the bad", not "permit the good".
drop policy if exists "insert performance: open block, or that band" on public.performance;
drop policy if exists "insert performance: not into another band's block" on public.performance;
create policy "insert performance: not into another band's block" on public.performance
  for insert to authenticated
  with check (
    not exists (
      select 1 from public.party_set s
      where s.id = performance.set_id
        and s.band_id is not null
        and not public.can_sign_up_band(s.band_id)
    )
  );

create or replace function public.reorder_sets(p_party bigint, p_set_ids bigint[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_count int;
begin
  if not public.is_party_admin(p_party) then
    raise exception 'Solo un organizador puede cambiar el orden de la noche.';
  end if;
  select count(*) into v_count from public.party_set where party_id = p_party;
  if v_count <> coalesce(array_length(p_set_ids, 1), 0) then
    raise exception 'Se esperaban % bloques de este toque y llegaron %.',
      v_count, coalesce(array_length(p_set_ids, 1), 0);
  end if;
  if exists (
    select 1 from unnest(p_set_ids) as t(id)
    where not exists (select 1 from public.party_set s where s.id = t.id and s.party_id = p_party)
  ) then
    raise exception 'Uno de esos bloques no es de este toque.';
  end if;
  -- WITH ORDINALITY, not row_number() over () — only the former is guaranteed
  -- to reflect the array's own order.
  update public.party_set s
  set "order" = t.ord::smallint
  from unnest(p_set_ids) with ordinality as t(id, ord)
  where s.id = t.id;

  -- Moving a band's block out from between two open ones leaves them adjacent.
  perform public.normalize_party_sets(p_party);
end;
$$;

create or replace function public.reorder_set_songs(p_set bigint, p_performance_ids bigint[])
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_count int;
begin
  if not public.can_edit_set(p_set) then
    raise exception 'No puedes reordenar este bloque.';
  end if;
  select count(*) into v_count from public.performance where set_id = p_set;
  if v_count <> coalesce(array_length(p_performance_ids, 1), 0) then
    raise exception 'Se esperaban % canciones en este bloque y llegaron %.',
      v_count, coalesce(array_length(p_performance_ids, 1), 0);
  end if;
  if exists (
    select 1 from unnest(p_performance_ids) as t(id)
    where not exists (select 1 from public.performance p where p.id = t.id and p.set_id = p_set)
  ) then
    raise exception 'Una de esas canciones no está en este bloque.';
  end if;
  update public.performance p
  set "order" = t.ord::smallint
  from unnest(p_performance_ids) with ordinality as t(id, ord)
  where p.id = t.id;
end;
$$;

create or replace function public.nudge_song(p_performance bigint, p_dir int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_set bigint; v_party bigint; v_band bigint;
  v_order smallint; v_pos int; v_count int; v_target bigint;
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

  -- 1..n before any arithmetic; the backfill leaves legacy globals behind.
  with ordered as (
    select id, row_number() over (order by "order" nulls last, id) as ord
    from public.performance where set_id = v_set
  )
  update public.performance p set "order" = o.ord::smallint
  from ordered o where p.id = o.id;

  select "order" into v_pos from public.performance where id = p_performance;
  select count(*) into v_count from public.performance where set_id = v_set;

  if (p_dir = -1 and v_pos > 1) or (p_dir = 1 and v_pos < v_count) then
    update public.performance set "order" = v_pos::smallint
    where set_id = v_set and "order" = (v_pos + p_dir)::smallint;
    update public.performance set "order" = (v_pos + p_dir)::smallint
    where id = p_performance;
    return;
  end if;

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
    raise exception 'Esa canción no está en ningún setlist.';
  end if;
  if v_source is null or not public.can_edit_set(v_source) then
    raise exception 'No puedes sacar una canción de ese bloque.';
  end if;
  if not public.can_edit_set(p_set) then
    raise exception 'No puedes poner una canción en ese bloque.';
  end if;
  select party_id into v_target_party from public.party_set where id = p_set;
  if v_target_party is null then
    raise exception 'Ese bloque no existe.';
  end if;
  if v_target_party <> v_party then
    raise exception 'Ese bloque es de otro toque.';
  end if;
  if v_source = p_set then
    return;
  end if;

  select count(*) into v_count from public.performance where set_id = p_set;
  v_pos := coalesce(p_position, v_count + 1);
  if v_pos < 1 then v_pos := 1; end if;
  if v_pos > v_count + 1 then v_pos := v_count + 1; end if;

  with ordered as (
    select id, row_number() over (order by "order" nulls last, id) as ord
    from public.performance where set_id = p_set
  )
  update public.performance p set "order" = o.ord::smallint
  from ordered o where p.id = o.id;

  update public.performance
  set set_id = p_set,
      "order" = v_pos::smallint,
      band_id = (select band_id from public.party_set where id = p_set)
  where id = p_performance;

  with ordered as (
    select id, row_number() over (
      order by "order" nulls last, case when id = p_performance then 0 else 1 end, id
    ) as ord
    from public.performance where set_id = p_set
  )
  update public.performance p set "order" = o.ord::smallint
  from ordered o where p.id = o.id;

  with ordered as (
    select id, row_number() over (order by "order" nulls last, id) as ord
    from public.performance where set_id = v_source
  )
  update public.performance p set "order" = o.ord::smallint
  from ordered o where p.id = o.id;
end;
$$;

create or replace function public.block_live_set_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.party p
    join public.performance pf on pf.set_id = old.id
    where p.id = old.party_id and p.status = 'live' and pf.live_state = 'playing'
  ) then
    raise exception 'Ese bloque se está tocando ahora. Termina el show primero.';
  end if;
  return old;
end;
$$;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration — only a
-- policy expression and some message strings changed.
--
-- VERIFY as a signed-in band member, on a toque whose night ENDS with that
-- band's block (the state that used to fail):
--   add a song, then sign the band up -> must succeed, and the song must land
--   in the band's LAST block. Repeat it: the second and third must work too.
-- =============================================================================
