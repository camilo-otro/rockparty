-- =============================================================================
-- Migration: claim links for placeholder band members (#79)
-- Date: 2026-09-08
-- =============================================================================
-- #78 lets a manager put someone on the roster who has no account
-- (band_pending_member.display_name). This is the second half: a link that lets
-- that person sign up and BECOME the real member, inheriting the instruments the
-- manager already recorded.
--
-- The link is the credential AND the consent: no email is stored, nothing is
-- sent by us, and possession of the link is what proves the manager meant to
-- invite this person. Anyone holding it can join as that placeholder. What
-- bounds that: 122 bits of entropy, single-use (enforced by delete-returning,
-- not by application logic), revocable, and it grants exactly one band
-- membership as 'member' — never manager, never any admin right.
--
-- PREREQUISITE, already shipped in 12e055c: the band edit page must DIFF the
-- placeholder roster rather than delete-and-reinsert it. Re-inserting mints a
-- new token, so with the old save every roster edit would have silently killed
-- every outstanding link.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The token
-- ---------------------------------------------------------------------------
-- gen_random_uuid() is 122 bits from a function Postgres already has — no
-- bespoke token generation to get wrong. Existing rows get one via the default.
alter table public.band_pending_member
  add column if not exists claim_token uuid not null default gen_random_uuid();

create unique index if not exists band_pending_member_claim_token_key
  on public.band_pending_member (claim_token);

-- ---------------------------------------------------------------------------
-- 2. Keep the token out of client reads
-- ---------------------------------------------------------------------------
-- THIS IS THE SECURITY CRUX. band_pending_member rows are readable by anyone who
-- can see the band ("band_pending select visible" uses can_see_band), so without
-- this every visitor could read every claim token and join as anyone.
--
-- Note a plain `revoke select (claim_token)` would be a NO-OP: Supabase grants
-- table-level SELECT, and in Postgres a table-level grant covers every column
-- regardless of column-level revokes. Drop the table grant, re-grant per column.
-- Same approach and same reasoning as 20260821_profile_email_privacy.sql.
--
-- Safe for the app: every existing read uses an explicit column list
-- (`select('id, display_name, instrument_ids')` in bands/[id] and
-- bands/[id]/edit), so there is no `select('*')` to break. After this,
-- `select=*` returns every column but the token and `select=claim_token` 403s.
revoke select on public.band_pending_member from anon, authenticated;

grant select (id, band_id, display_name, instrument_ids, created_at)
  on public.band_pending_member to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Manager reads the token (they can no longer select it directly)
-- ---------------------------------------------------------------------------
create or replace function public.band_claim_link(p_pending_id bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_band  bigint;
  v_token uuid;
begin
  select band_id, claim_token into v_band, v_token
    from public.band_pending_member
   where id = p_pending_id;

  if v_band is null then
    raise exception 'no such placeholder';
  end if;

  if not public.is_band_manager(v_band) then
    raise exception 'only a band manager can read a claim link';
  end if;

  return v_token;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Invalidate a link that went to the wrong person
-- ---------------------------------------------------------------------------
create or replace function public.regenerate_band_claim(p_pending_id bigint)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_band  bigint;
  v_token uuid;
begin
  select band_id into v_band from public.band_pending_member where id = p_pending_id;

  if v_band is null then
    raise exception 'no such placeholder';
  end if;

  if not public.is_band_manager(v_band) then
    raise exception 'only a band manager can regenerate a claim link';
  end if;

  update public.band_pending_member
     set claim_token = gen_random_uuid()
   where id = p_pending_id
  returning claim_token into v_token;

  return v_token;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Preview: what is this link for?
-- ---------------------------------------------------------------------------
-- Lets the claim page render "Te agregaron a Pulse como Bajo" BEFORE anything is
-- written, including for someone not yet signed in — so they know what they are
-- signing up for. Reveals a band name and a display name to whoever holds the
-- token, which is the point of having sent it to them.
--
-- Returns no rows for an unknown OR already-claimed token, so the page cannot
-- distinguish the two and neither can anyone probing.
create or replace function public.peek_band_claim(p_token uuid)
returns table (band_id bigint, band_name text, display_name text, instruments text[])
language sql
stable
security definer
set search_path = ''
as $$
  select b.id,
         b.name,
         p.display_name,
         coalesce(array_agg(i.name order by i.name) filter (where i.name is not null), '{}')
  from public.band_pending_member p
  join public.band b on b.id = p.band_id
  left join public.instrument i on i.id = any (p.instrument_ids)
  where p.claim_token = p_token
  group by b.id, b.name, p.display_name;
$$;

-- ---------------------------------------------------------------------------
-- 6. The claim itself
-- ---------------------------------------------------------------------------
create or replace function public.claim_band_member(p_token uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_pending public.band_pending_member;
  v_is_test boolean;
begin
  if v_uid is null then
    raise exception 'must be signed in to claim';
  end if;

  -- THE DELETE IS THE CLAIM. Atomic, so two people racing the same link produce
  -- exactly one winner and one clean failure — single-use enforced by the
  -- database rather than by application logic. If anything below raises, the
  -- whole transaction rolls back and the placeholder is still there, so a failed
  -- claim leaves no wreckage.
  delete from public.band_pending_member
   where claim_token = p_token
  returning * into v_pending;

  if v_pending.id is null then
    raise exception 'this claim link is no longer valid';
  end if;

  -- A real user must not be pulled into a test band (#67/#76). SECURITY DEFINER
  -- bypasses RLS, so can_see_band() is NOT running here — this check has to be
  -- explicit or the test-data boundary leaks through the claim path.
  select is_test into v_is_test from public.band where id = v_pending.band_id;
  if v_is_test and not public.is_dev() then
    raise exception 'this claim link is no longer valid';
  end if;

  -- Already a member (claimed a second placeholder, or joined in the meantime):
  -- merge rather than fail. The instruments are the part worth keeping.
  insert into public.band_member (band_id, user_id, role)
  values (v_pending.band_id, v_uid, 'member')
  on conflict (band_id, user_id) do nothing;

  insert into public.band_member_instrument (band_id, user_id, instrument_id)
  select v_pending.band_id, v_uid, unnest(v_pending.instrument_ids)
  on conflict do nothing;

  -- Tell the managers someone joined (existing notification table + bell, #63).
  -- Shape matches the rest of the app: (recipient, type, payload jsonb), with the
  -- client mapping type + payload to text and a link in notifications/+page.svelte.
  insert into public.notification (recipient, type, payload)
  select bm.user_id,
         'band_member_claimed',
         jsonb_build_object(
           'band_id',      v_pending.band_id,
           'band_name',    b.name,
           'display_name', v_pending.display_name,
           'nickname',     p.nickname
         )
  from public.band_member bm
  join public.band b on b.id = bm.band_id
  left join public.profile p on p.id = v_uid
  where bm.band_id = v_pending.band_id
    and bm.role = 'manager'
    and bm.user_id <> v_uid;

  return v_pending.band_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------
-- `create function` grants EXECUTE to PUBLIC, and anon/authenticated INHERIT it,
-- so revoking from anon/authenticated alone is a no-op. Revoke from PUBLIC.
-- (This exact mistake shipped once already — 20260907_purge_revoke_from_public.sql.)
revoke all on function public.band_claim_link(bigint)       from public;
revoke all on function public.regenerate_band_claim(bigint) from public;
revoke all on function public.peek_band_claim(uuid)         from public;
revoke all on function public.claim_band_member(uuid)       from public;

-- Managers only, but the function checks that itself; authenticated is the gate.
grant execute on function public.band_claim_link(bigint)       to authenticated;
grant execute on function public.regenerate_band_claim(bigint) to authenticated;
-- Preview works signed-out, so someone knows what they are signing up for.
grant execute on function public.peek_band_claim(uuid)         to anon, authenticated;
-- Claiming requires an account.
grant execute on function public.claim_band_member(uuid)       to authenticated;

commit;
