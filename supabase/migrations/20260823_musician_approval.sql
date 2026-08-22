-- =============================================================================
-- Migration: musician approval mode (#29) — DB foundation
-- Date: 2026-08-23  ·  spec: docs/specs/musician-approval.md
-- =============================================================================
-- - party.performer_approval: how signups get onto a song (default 'auto').
-- - performance_user.status: pending | approved | declined, OWNED BY A TRIGGER
--   (not client-writable). auto → approved (backward-compatible); manual modes →
--   pending unless the inserter is a party admin (or, in proponent mode, the
--   song's proponent); invite_only rejects a non-admin/proponent self-signup.
-- - RLS tightened: INSERT was `with check (true)` (anyone could sign up anyone) —
--   now self / admin / proponent; SELECT narrows pending+declined to the row's
--   user and the approvers. Capacity/oversubscription is deferred to #32.
-- =============================================================================

begin;

create type public.performer_approval as enum ('auto', 'organizer', 'proponent', 'invite_only');
create type public.signup_status as enum ('pending', 'approved', 'declined');

alter table public.party
  add column if not exists performer_approval public.performer_approval not null default 'auto';

-- Existing signups become 'approved' (they're already "on it"); new rows are set
-- by the trigger below.
alter table public.performance_user
  add column if not exists status public.signup_status not null default 'approved';

-- ---- status trigger (the crux) ----------------------------------------------
-- SECURITY INVOKER: the lookups run under the signing-up user's RLS, which is
-- fine — a toque they can act on is one they can see. auth is schema-qualified so
-- it resolves under search_path=''.
create or replace function public.set_signup_status()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_party      bigint;
  v_mode       public.performer_approval;
  v_proponent  uuid;
  v_is_admin   boolean;
  v_is_prop    boolean;
begin
  select perf.party, pt.performer_approval, perf.suggested_by
    into v_party, v_mode, v_proponent
  from public.performance perf
  join public.party pt on pt.id = perf.party
  where perf.id = new.performance_id;

  v_is_admin :=
    exists (select 1 from public.party pt where pt.id = v_party and pt.created_by = auth.uid())
    or exists (select 1 from public.party_admin pa where pa.party_id = v_party and pa.user_id = auth.uid());
  v_is_prop := (v_proponent is not null and v_proponent = auth.uid());

  if tg_op = 'INSERT' then
    if v_mode = 'invite_only' and not (v_is_admin or v_is_prop) then
      raise exception 'Las inscripciones a este toque son solo por invitación';
    end if;
    -- status is owned here; any client-supplied value is ignored
    if v_mode = 'auto' or v_is_admin or (v_mode = 'proponent' and v_is_prop) then
      new.status := 'approved';
    else
      new.status := 'pending';
    end if;
    return new;
  elsif tg_op = 'UPDATE' then
    if new.status is distinct from old.status
       and not (v_is_admin or (v_mode = 'proponent' and v_is_prop)) then
      raise exception 'No puedes cambiar el estado de esta inscripción';
    end if;
    return new;
  end if;
  return new;
end;
$$;

create trigger performance_user_set_status
  before insert or update on public.performance_user
  for each row execute function public.set_signup_status();

-- ---- RLS: replace the wide-open performance_user policies --------------------
drop policy if exists "allow insert to authenticated users" on public.performance_user;
drop policy if exists "Enable update for authenticated users only" on public.performance_user;
drop policy if exists "allow delete to own user" on public.performance_user;
drop policy if exists "allow select to all users" on public.performance_user;

-- Reusable predicate: the acting user administers the row's toque, or (in
-- proponent mode) proposed the row's song.
-- (inlined per policy since Postgres RLS can't share a subexpression)

create policy "signup select: approved public, else owner/approvers" on public.performance_user
  for select to anon, authenticated using (
    status = 'approved'
    or user_id = (select auth.uid())
    or exists (
      select 1 from public.performance perf join public.party pt on pt.id = perf.party
      where perf.id = performance_user.performance_id and (
        pt.created_by = (select auth.uid())
        or exists (select 1 from public.party_admin pa where pa.party_id = pt.id and pa.user_id = (select auth.uid()))
        or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
      )
    )
  );

create policy "signup insert: self, admin, or proponent" on public.performance_user
  for insert to authenticated with check (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.performance perf join public.party pt on pt.id = perf.party
      where perf.id = performance_user.performance_id and (
        pt.created_by = (select auth.uid())
        or exists (select 1 from public.party_admin pa where pa.party_id = pt.id and pa.user_id = (select auth.uid()))
        or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
      )
    )
  );

create policy "signup update: self, admin, or proponent" on public.performance_user
  for update to authenticated using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.performance perf join public.party pt on pt.id = perf.party
      where perf.id = performance_user.performance_id and (
        pt.created_by = (select auth.uid())
        or exists (select 1 from public.party_admin pa where pa.party_id = pt.id and pa.user_id = (select auth.uid()))
        or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
      )
    )
  );

create policy "signup delete: self, admin, or proponent" on public.performance_user
  for delete to authenticated using (
    user_id = (select auth.uid())
    or exists (
      select 1 from public.performance perf join public.party pt on pt.id = perf.party
      where perf.id = performance_user.performance_id and (
        pt.created_by = (select auth.uid())
        or exists (select 1 from public.party_admin pa where pa.party_id = pt.id and pa.user_id = (select auth.uid()))
        or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
      )
    )
  );

commit;
