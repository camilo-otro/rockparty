-- =============================================================================
-- Migration: event logistics Stage 2 — assignment, notification, self-confirm
-- Date: 2026-09-08  (follows 20260908_event_logistics.sql)
-- =============================================================================
-- Spec: docs/specs/event-logistics.md, "Stage 2 — assigning it to people".
--
-- Stage 1 answered "what does this toque need and where is it coming from".
-- Stage 2 puts a NAME on it and lets that person confirm.
--
-- Two things drive the shape here:
--
-- 1. `notification` has SELECT/UPDATE/DELETE policies scoped to the recipient
--    and NO INSERT POLICY AT ALL — clients cannot create notifications, which is
--    correct (otherwise anyone could spam anyone). So the assignment notice has
--    to come from SECURITY DEFINER code. A trigger rather than an RPC, so an
--    assignment ALWAYS notifies no matter how the row was written.
--
-- 2. Confirmation must be an RPC, not a widened UPDATE policy. Scoping UPDATE to
--    `assigned_user = auth.uid()` would let an assignee rewrite quantity, notes,
--    or reassign the row to someone else — RLS cannot restrict WHICH COLUMNS an
--    update touches.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Tell someone they've been put down for something
-- ---------------------------------------------------------------------------
create or replace function public.notify_requirement_assigned()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_title text;
  v_item  text;
begin
  -- Only when a real, CHANGED assignee appears. Clearing the field (a decline,
  -- or the organizer reassigning away) must not notify anyone.
  if new.assigned_user is null then return new; end if;
  if tg_op = 'UPDATE' and old.assigned_user is not distinct from new.assigned_user then
    return new;
  end if;
  -- Assigning yourself is not news.
  if new.assigned_user = v_actor then return new; end if;

  select p.title into v_title from public.party p where p.id = new.party_id;
  select coalesce(e.name, r.name) into v_item
    from (select 1) _
    left join public.equipment e on e.id = new.equipment_id
    left join public.party_role r on r.id = new.role_id;

  insert into public.notification (recipient, type, payload)
  values (
    new.assigned_user,
    'requirement_assigned',
    jsonb_build_object(
      'party_id', new.party_id,
      'party_title', v_title,
      'requirement_id', new.id,
      'item', v_item,
      'kind', new.kind::text
    )
  );
  return new;
end;
$$;

drop trigger if exists requirement_assigned on public.party_requirement;
create trigger requirement_assigned
  after insert or update of assigned_user on public.party_requirement
  for each row execute function public.notify_requirement_assigned();

-- ---------------------------------------------------------------------------
-- 2. The assignee confirms — or declines
-- ---------------------------------------------------------------------------
-- Confirm touches ONLY confirmed_at. Decline hands the row back: it clears the
-- assignee and drops source to 'unassigned', so it re-enters the gap count
-- rather than sitting quietly declined where nobody looks. The organizer is
-- told, because a silent decline is worse than no assignment.
create or replace function public.confirm_requirement(p_id bigint, p_confirmed boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_req  public.party_requirement;
  v_title text;
  v_item  text;
  v_who   text;
begin
  if v_uid is null then
    raise exception 'must be signed in';
  end if;

  select * into v_req from public.party_requirement where id = p_id;
  if v_req.id is null or v_req.assigned_user is distinct from v_uid then
    -- Same message either way: no probing for which requirements exist.
    raise exception 'not your assignment';
  end if;

  if p_confirmed then
    update public.party_requirement set confirmed_at = now() where id = p_id;
    return;
  end if;

  -- Decline.
  select p.title into v_title from public.party p where p.id = v_req.party_id;
  select coalesce(e.name, r.name) into v_item
    from (select 1) _
    left join public.equipment e on e.id = v_req.equipment_id
    left join public.party_role r on r.id = v_req.role_id;
  select nickname into v_who from public.profile where id = v_uid;

  update public.party_requirement
     set assigned_user  = null,
         assigned_label = null,
         confirmed_at   = null,
         source         = 'unassigned'
   where id = p_id;

  insert into public.notification (recipient, type, payload)
  select pa.uid, 'requirement_declined',
         jsonb_build_object(
           'party_id', v_req.party_id,
           'party_title', v_title,
           'requirement_id', v_req.id,
           'item', v_item,
           'nickname', v_who
         )
  from (
    select p.created_by as uid from public.party p
     where p.id = v_req.party_id and p.created_by is not null
    union
    select a.user_id from public.party_admin a where a.party_id = v_req.party_id
  ) pa
  where pa.uid <> v_uid;
end;
$$;

-- `revoke ... from public` alone is NOT enough: Supabase's default privileges
-- grant EXECUTE to anon and authenticated BY NAME as well (see
-- 20260908_function_grants_tighten.sql). Revoke from all three, grant back.
revoke all on function public.confirm_requirement(bigint, boolean) from public, anon, authenticated;
grant execute on function public.confirm_requirement(bigint, boolean) to authenticated;

-- The trigger function is never called directly; Postgres does not check
-- EXECUTE when firing a trigger, so locking it down costs nothing.
revoke all on function public.notify_requirement_assigned() from public, anon, authenticated;

commit;
