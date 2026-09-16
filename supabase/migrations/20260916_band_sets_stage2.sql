-- =============================================================================
-- Migration: #110 STAGE 2 — close the insert side of the ownership rule
-- Date: 2026-09-16
-- =============================================================================
-- MUST BE APPLIED AFTER the client deploy that understands sets. That deploy
-- happened on 2026-09-14, so this is now safe.
--
-- Stage 1 deliberately left two things alone because either would have broken
-- the then-live client the moment it ran. Both are now due.
--
-- -----------------------------------------------------------------------------
-- 1. The hole this actually closes
-- -----------------------------------------------------------------------------
-- `performance` INSERT is `with check (true)`: anyone signed in can insert a
-- performance into any party. That was a deliberate, documented property of the
-- jam-night model — and #110 made it worse without meaning to, because `set_id`
-- is now a writable column. A stranger can pass the id of a BAND's block and
-- their song appears inside that band's set.
--
-- So the ticket currently enforces "who may REARRANGE a band's set" (the band,
-- never the organizer) while leaving "who may PUT A SONG IN IT" open to
-- everybody. The two halves have to match.
--
-- The rule mirrors can_edit_set, with one deliberate difference:
--
--   OPEN block  -> anyone signed in. This is the jam-night model and the whole
--                  reason open blocks exist; it is NOT what was broken.
--   BAND block  -> can_sign_up_band(band_id). The band, and only the band —
--                  NOT the party admin. An organizer injecting a song into a
--                  band's set is deciding their setlist just as much as
--                  reordering it would be, which is the call made when
--                  can_edit_set became an ownership question.
--
-- Note this is NARROWER than the rule stage 1's own header sketched ("open set,
-- or a member of the set's band, or a party admin"). That sketch predates the
-- ownership refinement; the "or a party admin" clause is gone on purpose.
--
-- -----------------------------------------------------------------------------
-- 2. Why the policy tolerates a NULL set_id
-- -----------------------------------------------------------------------------
-- The client never sends set_id. Both insert paths — "Sugerir una canción" and
-- the copy-setlist in the re-propose flow — omit it, and the BEFORE INSERT
-- trigger assign_performance_set() fills in the trailing OPEN block.
--
-- PostgreSQL evaluates an INSERT's RLS WITH CHECK against the FINAL row, after
-- BEFORE ROW triggers, so set_id should always be populated by the time this is
-- tested. The `set_id is null` branch is there so the policy is correct even if
-- that ordering is not what I think it is — and it costs nothing in safety,
-- because the trigger can only ever assign an OPEN block. There is no way to
-- reach a band's set by omitting set_id.
--
-- Verify after applying (see the notes at the bottom): an insert with no set_id
-- must still succeed, or every "add a song" in the app is dead.
--
-- -----------------------------------------------------------------------------
-- 3. NOT NULL
-- -----------------------------------------------------------------------------
-- Safe now: 0 rows have a null set_id (checked immediately before writing this),
-- and the trigger guarantees new ones cannot. It turns "a song adrift with no
-- block" from a silent state the setlist would sort to the end into an error at
-- the point of the mistake.
-- =============================================================================

begin;

-- 1 ---------------------------------------------------------------------------
alter table public.performance alter column set_id set not null;

-- 2 ---------------------------------------------------------------------------
drop policy if exists "allow insert to authenticated users" on public.performance;
drop policy if exists "insert performance: open block, or that band" on public.performance;
create policy "insert performance: open block, or that band" on public.performance
  for insert to authenticated
  with check (
    -- filled by assign_performance_set() with the trailing OPEN block
    performance.set_id is null
    or exists (
      select 1 from public.party_set s
      where s.id = performance.set_id
        and (s.band_id is null or public.can_sign_up_band(s.band_id))
    )
  );

-- 3 ---------------------------------------------------------------------------
-- Removing the block that is ON STAGE would strand advance_show(): the
-- now-playing pointer IS a performance row, and deleting the set cascades it.
--
-- A trigger rather than a DELETE policy, deliberately. A policy that refuses
-- returns 0 rows and PostgREST answers 200/204 with an empty body, so the
-- client reads a refusal as success (the trap recorded in CLAUDE.md). An
-- exception gives the organizer a reason instead of a silent no-op.
create or replace function public.block_live_set_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1
    from public.party p
    join public.performance pf on pf.set_id = old.id
    where p.id = old.party_id
      and p.status = 'live'
      and pf.live_state = 'playing'
  ) then
    raise exception 'that block is playing right now — end the show first';
  end if;
  return old;
end;
$$;

drop trigger if exists trg_block_live_set_delete on public.party_set;
create trigger trg_block_live_set_delete
  before delete on public.party_set
  for each row execute function public.block_live_set_delete();

revoke all on function public.block_live_set_delete() from public, anon, authenticated;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration — set_id
-- becoming NOT NULL does not change the generated Row/Insert shapes in a way the
-- client reads, and no function signature changed.
--
-- VERIFY, in this order, as a signed-in user over REST (never the SQL editor):
--   1. insert a performance with NO set_id  -> must SUCCEED and land in the
--      trailing open block. If this fails, "Sugerir una canción" is dead and
--      this migration must be rolled back immediately:
--        drop policy "insert performance: open block, or that band" on public.performance;
--        create policy "allow insert to authenticated users" on public.performance
--          for insert to authenticated with check (true);
--   2. insert with set_id = an OPEN block   -> succeeds
--   3. insert with set_id = a band's block you are NOT in -> REFUSED
--   4. insert with set_id = your own band's block          -> succeeds
--
-- STILL NOT BUILT after this (UI, not schema):
--   * the per-block `+` from the spec, so a band can add to its own block
--     directly rather than adding a loose song and signing the band up for it;
--   * any control to delete a band's block at all — the organizer's documented
--     remedy when a band goes quiet currently exists only in SQL.
-- =============================================================================
