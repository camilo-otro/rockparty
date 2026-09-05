-- =============================================================================
-- Migration: how a toque's organizers are presented (order + visibility)
-- Date: 2026-09-05
-- =============================================================================
-- The detail page only ever showed party.created_by; co-organizers existed in
-- party_admin but were invisible to readers. Surfacing them raises two questions
-- that are social, not technical — who is listed first, and who is listed at all.
--
-- Rules encoded here:
--   * the creator is pinned first and always visible (not represented in
--     party_admin, so nothing below can reorder or hide them)
--   * ordering among co-organizers is a party-admin decision
--   * visibility is personal: only that organizer can hide themselves
--
-- RLS is per-row, not per-column, so the split above is enforced by a BEFORE
-- UPDATE trigger on top of a permissive-union update policy.
-- =============================================================================

begin;

alter table public.party_admin
  add column if not exists display_order smallint,
  add column if not exists hidden boolean not null default false;

comment on column public.party_admin.display_order is
  'Position among a toque''s co-organizers on the detail page. Nulls sort last. Party admins set this.';
comment on column public.party_admin.hidden is
  'This organizer asked not to be listed publicly. Only they can set it.';

-- Is the current user an admin of this party (its creator, or a party_admin)?
-- SECURITY DEFINER so it can be called from party_admin's own policies without
-- re-entering RLS on that table.
create or replace function public.is_party_admin(pid bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
           select 1 from public.party p
           where p.id = pid and p.created_by = (select auth.uid())
         )
      or exists (
           select 1 from public.party_admin pa
           where pa.party_id = pid and pa.user_id = (select auth.uid())
         );
$$;

-- There was no UPDATE policy on party_admin at all, so these columns would be
-- unwritable. Allow the union of both actors; the trigger below decides which
-- COLUMN each of them may actually touch.
drop policy if exists "party_admin: reorder by admins, hide by self" on public.party_admin;
create policy "party_admin: reorder by admins, hide by self" on public.party_admin
  for update to authenticated
  using      (public.is_party_admin(party_id) or user_id = (select auth.uid()))
  with check (public.is_party_admin(party_id) or user_id = (select auth.uid()));

-- Seed a stable starting order for rows that predate the column: oldest first,
-- which is the order they were added in.
--
-- NB: this runs BEFORE the guard trigger below exists, deliberately. Running it
-- after would trip the trigger's own rule — a migration in the SQL editor has no
-- auth.uid(), so it can't be "a party admin" and every row would be rejected.
with ordered as (
  select party_id, user_id,
         (row_number() over (partition by party_id order by created_at, user_id) - 1)::smallint as n
  from public.party_admin
)
update public.party_admin pa
set display_order = o.n
from ordered o
where pa.party_id = o.party_id
  and pa.user_id  = o.user_id
  and pa.display_order is null;

create or replace function public.party_admin_presentation_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- No JWT => this isn't an end-user request (SQL editor, service_role, a later
  -- migration). RLS already limits real traffic to `authenticated`, so there is
  -- nothing for these per-user rules to protect here, and enforcing them would
  -- only lock maintenance out of its own table.
  if (select auth.uid()) is null then
    return new;
  end if;

  -- Identity is not editable through this path; removing an organizer is a
  -- DELETE (which has its own policy).
  if new.party_id is distinct from old.party_id or new.user_id is distinct from old.user_id then
    raise exception 'party_admin identity is not editable';
  end if;

  -- Visibility is personal, even for a party admin acting on someone else.
  if new.hidden is distinct from old.hidden and old.user_id <> (select auth.uid()) then
    raise exception 'only that organizer can change their own visibility';
  end if;

  -- Ordering is the party's call, not the individual's.
  if new.display_order is distinct from old.display_order and not public.is_party_admin(old.party_id) then
    raise exception 'only a party admin can reorder organizers';
  end if;

  return new;
end;
$$;

drop trigger if exists party_admin_presentation_guard on public.party_admin;
create trigger party_admin_presentation_guard
  before update on public.party_admin
  for each row execute function public.party_admin_presentation_guard();

commit;
