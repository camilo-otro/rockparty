-- =============================================================================
-- Migration: one shareable invite link per toque (#113 part B)
-- Date: 2026-09-21
-- =============================================================================
-- ADDITIVE. No existing behaviour changes; nothing has a link until an organiser
-- asks for one.
--
-- -----------------------------------------------------------------------------
-- The half that named invites cannot reach
-- -----------------------------------------------------------------------------
-- party_invite names a `user_id`, so it only works for someone who already has
-- an account. The scene runs on WhatsApp: an invite that requires the recipient
-- to sign up before you can even send it will not get used.
--
-- So: one link per toque. Opening it shows a thin preview, signing in claims it,
-- and claiming writes the same party_invite row an organiser would have written
-- by hand. After that the guest is in the named case forever — the link was only
-- the doorway.
--
-- This mirrors band claim links (#79) on purpose, down to the function names.
-- peek_band_claim / claim_band_member already solve this exact problem for band
-- rosters, and a second vocabulary for the same idea would be worse than a
-- slightly generic one.
--
-- -----------------------------------------------------------------------------
-- Why a table and not a column on `party`
-- -----------------------------------------------------------------------------
-- A token on `party` would sit on a table anyone can SELECT, so it would need
-- the column-grant dance from profile.email and band_pending_member.claim_token
-- — drop the table-level grant, re-grant every OTHER column by name. `party` has
-- eighteen columns and gains more; that list is a standing liability, and a
-- column added later leaks until somebody notices.
--
-- Its own table keeps `party`'s simple grant intact and makes the rule one line:
-- only organisers can read this at all.
--
-- -----------------------------------------------------------------------------
-- ONE token per toque, not one per invite
-- -----------------------------------------------------------------------------
-- band_pending_member puts a token on every row, and band-claim-link.md records
-- what that costs: every roster edit mints new links and the manager cannot tell
-- them apart. A toque has one link, it is regenerable, and that matches how it
-- actually gets shared — pasted once into a group chat.
--
-- The cost, which the UI states plainly: the link is a BEARER credential.
-- Whoever holds it can claim an invite. Regenerating is the remedy.
-- =============================================================================

begin;

create table if not exists public.party_invite_link (
  party_id   bigint primary key references public.party (id) on delete cascade,
  token      uuid not null default gen_random_uuid(),
  created_by uuid references public.profile (id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists idx_party_invite_link_token
  on public.party_invite_link (token);

alter table public.party_invite_link enable row level security;

-- Organisers only, and only through here — the RPCs below are DEFINER and take
-- the token as an argument, so nobody else ever needs to read this table.
create policy "party_invite_link: organisers only" on public.party_invite_link
  for select to authenticated
  using (public.is_party_admin(party_id));

-- -----------------------------------------------------------------------------
-- peek: what a stranger sees BEFORE deciding to sign in
-- -----------------------------------------------------------------------------
-- Deliberately thin. A private toque is usually somebody's house, so this
-- returns the venue's NAME and AREA and never touches venue_contact. Getting
-- this wrong would make the invite link the leak it exists to prevent.
--
-- Returns nothing for an unknown token, exactly as peek_band_claim does — the
-- page cannot tell "wrong link" from "revoked link", and neither can a guesser.
create or replace function public.peek_party_invite(p_token uuid)
returns table (
  party_id    bigint,
  title       text,
  party_date  date,
  venue_name  text,
  venue_area  text,
  is_test     boolean
)
language sql stable security definer set search_path = '' as $$
  select p.id, p.title, p.date, v.name, v.area, p.is_test
  from public.party_invite_link l
  join public.party p on p.id = l.party_id
  left join public.venue v on v.id = p.venue
  where l.token = p_token;
$$;

revoke all on function public.peek_party_invite(uuid) from public;
grant execute on function public.peek_party_invite(uuid) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- claim: the doorway
-- -----------------------------------------------------------------------------
-- Writes exactly the row an organiser would have written by hand, crediting
-- whoever made the link. Idempotent, so re-opening a link you already claimed
-- lands you on the toque instead of erroring.
create or replace function public.claim_party_invite(p_token uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_party bigint;
  v_by    uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Debes iniciar sesión para aceptar la invitación.';
  end if;

  select l.party_id, l.created_by into v_party, v_by
  from public.party_invite_link l
  where l.token = p_token;

  if v_party is null then
    raise exception 'Esta invitación ya no es válida.';
  end if;

  insert into public.party_invite (party_id, user_id, invited_by)
  values (v_party, (select auth.uid()), v_by)
  on conflict (party_id, user_id) do nothing;

  return v_party;
end;
$$;

revoke all on function public.claim_party_invite(uuid) from public, anon;
grant execute on function public.claim_party_invite(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- the organiser's control: get the link, or replace one that got out
-- -----------------------------------------------------------------------------
-- One function for both, because "show me the link" on a toque that has none has
-- to mint one anyway. p_regenerate is the "this leaked" button; the old token
-- stops working the moment it returns.
create or replace function public.party_invite_link_token(p_party bigint, p_regenerate boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_token uuid;
begin
  if not public.is_party_admin(p_party) then
    raise exception 'Solo quienes organizan el toque pueden compartir el enlace.';
  end if;

  if p_regenerate then
    insert into public.party_invite_link (party_id, created_by)
    values (p_party, (select auth.uid()))
    on conflict (party_id) do update
      set token = gen_random_uuid(), created_by = (select auth.uid()), created_at = now()
    returning token into v_token;
  else
    insert into public.party_invite_link (party_id, created_by)
    values (p_party, (select auth.uid()))
    on conflict (party_id) do update
      -- A no-op update, so RETURNING gives back the existing row rather than
      -- nothing. `do nothing` would return no row and this would answer null.
      set party_id = public.party_invite_link.party_id
    returning token into v_token;
  end if;

  return v_token;
end;
$$;

revoke all on function public.party_invite_link_token(bigint, boolean) from public, anon;
grant execute on function public.party_invite_link_token(bigint, boolean) to authenticated;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (party_invite_link + three functions).
--
-- VERIFY as an ANONYMOUS caller:
--   rpc/peek_party_invite  {"p_token": "<a real token>"}  -> title, date, venue
--                                                            NAME and AREA only
--   rpc/peek_party_invite  {"p_token": "<random uuid>"}   -> []
--   rpc/claim_party_invite {"p_token": "<a real token>"}  -> refused, not signed in
--   /party_invite_link?select=token                       -> [] (organisers only,
--                                                            and only authenticated)
--
-- and as an organiser: party_invite_link_token twice returns the SAME token,
-- then with p_regenerate true returns a different one and the old stops peeking.
-- =============================================================================
