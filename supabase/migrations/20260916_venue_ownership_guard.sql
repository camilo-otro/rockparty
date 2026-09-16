-- =============================================================================
-- Migration: a venue always has an owner, and can be removed (#113)
-- Date: 2026-09-16
-- =============================================================================
-- ADDITIVE. Safe to apply before or after any client deploy.
--
-- -----------------------------------------------------------------------------
-- The gap
-- -----------------------------------------------------------------------------
-- `venue.created_by` is nullable and nothing fills it in, and `venue` has no
-- DELETE policy at all. A venue created without a `created_by` and without a
-- `venue_admin` row is therefore UNMANAGEABLE, permanently:
--
--   is_venue_admin(v) is false for everyone, so
--     * nobody can UPDATE it          (the update policy is is_venue_admin)
--     * nobody can see its contact    (can_see_venue_contact starts there)
--     * nobody can delete it          (no DELETE policy exists)
--
-- Found the hard way: two rows created while testing #113 landed exactly there
-- and could not be cleaned up from the client. The app's own VenueForm always
-- sets created_by, so this was latent rather than live — but "latent" only holds
-- until something inserts a venue another way, and the result is unrecoverable
-- without a migration like this one.
--
-- -----------------------------------------------------------------------------
-- Why a trigger and not a column default
-- -----------------------------------------------------------------------------
-- A DEFAULT only applies when the column is OMITTED. A client sending
-- `created_by: null` explicitly — which is easy to do by spreading a form object
-- — skips it entirely. A BEFORE INSERT trigger catches both.
-- =============================================================================

begin;

-- 1 ---------------------------------------------------------------------------
-- Replaces venue_default_private() from 20260916_venue_privacy_self_sustaining,
-- which did only half of this. One BEFORE INSERT function, so there is one place
-- to look for "what gets filled in when a venue is created".
create or replace function public.venue_defaults()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Whoever inserts it owns it. Without this the row can become unmanageable,
  -- and nothing can recover it from the client.
  if new.created_by is null then
    new.created_by := (select auth.uid());
  end if;

  -- type 4 is "Club / Residencia privada" — it MEANS a private address, so this
  -- reads the type rather than guessing. Does not cover a house filed under
  -- "Espacio al Aire Libre"; VenueForm's explicit toggle will.
  if new.venue_type = 4 then
    new.private := true;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_venue_default_private on public.venue;
drop trigger if exists trg_venue_defaults on public.venue;
create trigger trg_venue_defaults
  before insert on public.venue
  for each row execute function public.venue_defaults();

drop function if exists public.venue_default_private();
revoke all on function public.venue_defaults() from public, anon, authenticated;

-- 2 ---------------------------------------------------------------------------
-- A venue could never be deleted by anyone. venue_admin, venue_contact and
-- venue_equipment all cascade, so removing a venue is self-contained — except
-- for `party.venue`, which is ON DELETE NO ACTION and would fail at the foreign
-- key with a raw Postgres error.
--
-- So the policy allows the venue's admins, and a trigger refuses the one case
-- that would otherwise be an unreadable error, in the app's language. Same shape
-- as #110's live-show guard: a policy that refuses returns 0 rows and PostgREST
-- answers 200/204, which the client reads as success.
drop policy if exists "venue delete: admins, if nothing is booked" on public.venue;
create policy "venue delete: admins, if nothing is booked" on public.venue
  for delete to authenticated
  using (public.is_venue_admin(id));

create or replace function public.block_venue_delete_with_parties()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_n int;
begin
  select count(*) into v_n from public.party p where p.venue = old.id;
  if v_n > 0 then
    raise exception 'Este local tiene % toque(s) asociados. Bórralos o muévelos antes de eliminarlo.', v_n;
  end if;
  return old;
end;
$$;

drop trigger if exists trg_block_venue_delete_with_parties on public.venue;
create trigger trg_block_venue_delete_with_parties
  before delete on public.venue
  for each row execute function public.block_venue_delete_with_parties();

revoke all on function public.block_venue_delete_with_parties() from public, anon, authenticated;

-- 3 ---------------------------------------------------------------------------
-- Clean up the two orphans this gap produced while testing #113. Narrow on
-- purpose — is_test, the exact names, and no created_by — so it cannot touch
-- anything real, and is a no-op if they are already gone.
delete from public.venue
where is_test = true
  and created_by is null
  and name in ('ZZ prueba privacidad', 'ZZ prueba bar');

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration.
--
-- VERIFY as a signed-in user:
--   * create a venue without sending created_by -> it comes back owned by you,
--     and you can then read its contact and edit it
--   * delete a venue with no toques -> succeeds
--   * delete one with toques -> refused, in Spanish, with the count
-- =============================================================================
