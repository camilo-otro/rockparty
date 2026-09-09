-- =============================================================================
-- Migration: song moderation — a delete path for user-added catalogue entries
-- Date: 2026-09-09
-- =============================================================================
-- The catalogue is shared: anyone signed in can insert a song, and #98 (inline
-- Spotify add) makes that a ONE-TAP action from the setlist page. That is the
-- right trade for the flow, but it needs a way to clean up after it — typos,
-- wrong versions, and the odd joke entry.
--
-- Today `song` has exactly two policies (INSERT to authenticated, SELECT to
-- all) and NO delete policy, so RLS denies every delete by default. The table
-- GRANT is already there (authenticated holds DELETE), which is why an attempted
-- cleanup earlier returned 204 and changed nothing: PostgREST reports success
-- for a delete that matched zero rows.
--
-- -----------------------------------------------------------------------------
-- Why the policy predicate is the ONLY safeguard
-- -----------------------------------------------------------------------------
-- performance_song_fkey is ON DELETE CASCADE, and so is everything under it:
--
--   song --cascade--> performance --cascade--> performance_user
--                                \-cascade--> applause
--
-- Deleting one song therefore erases set-list slots, the signups attached to
-- them, and their applause — for every party at once. Cascades run as the
-- table owner and DO NOT consult RLS on the child tables, so `performance`'s own
-- policies cannot save a real set list here. Whatever protection exists has to
-- be written into the `song` DELETE policy itself. That is what this migration
-- does; do not relax it without re-reading this paragraph.
--
-- (Note: supabase/schema.sql line ~259 records this FK WITHOUT the cascade. The
-- live database has it. schema.sql is stale on this point and is corrected in
-- the same commit.)
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Who may moderate
-- ---------------------------------------------------------------------------
-- NOT profile.role. That column looked like the obvious gate — exactly one
-- profile has role = 1 — but it is self-serve: the `profile` UPDATE policy is
-- USING (id = auth.uid()) with no WITH CHECK (so Postgres reuses USING, which
-- stays true after the row changes) and `authenticated` holds UPDATE on the
-- `role` column. Any signed-in user can promote themselves with a single REST
-- call. profile.role is a display/preference field, not a privilege, and must
-- never gate anything. (Tightening it is filed separately — it is a distinct
-- change with its own blast radius, and this feature must not depend on it.)
--
-- NOT is_dev() either: dev_user currently holds four people (Cami, Yorch,
-- Capibear, fuyumehanamura) because it grants TEST-DATA VISIBILITY, which is a
-- much cheaper thing to hand out than a cascading delete. Reusing it would
-- silently widen who can wipe a set list, and would couple the two forever.
--
-- So: a dedicated table, shaped exactly like dev_user — the pattern that is
-- already proven tamper-proof here. Self-read only and NO insert/update/delete
-- policy at all, so membership can only be granted from the SQL editor or with
-- the service_role key. There is no self-escalation path.
create table if not exists public.song_moderator (
  user_id    uuid primary key references public.profile (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.song_moderator enable row level security;

drop policy if exists "song_moderator self read" on public.song_moderator;
create policy "song_moderator self read"
  on public.song_moderator for select
  to authenticated
  using (user_id = (select auth.uid()));

-- Mirrors is_dev() exactly: SECURITY DEFINER so it can read the table past the
-- self-read policy, STABLE, and search_path pinned to ''.
create or replace function public.is_song_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.song_moderator m where m.user_id = (select auth.uid())
  );
$$;

-- Both halves of the grant gotcha (see 20260908_function_grants_tighten.sql):
-- `create function` grants EXECUTE to PUBLIC, and Supabase's pg_default_acl
-- grants it to anon and authenticated BY NAME. Revoking PUBLIC alone leaves the
-- named grants behind.
revoke all on function public.is_song_moderator() from public, anon, authenticated;
grant execute on function public.is_song_moderator() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. "Is this song on a real set list?" -- SECURITY DEFINER, and it must be
-- ---------------------------------------------------------------------------
-- The first draft of this migration inlined the lookup directly in the policy:
--
--   and not exists (select 1 from public.performance pf
--                   left join public.party pt on pt.id = pf.party ...)
--
-- That is WRONG, and wrong in the dangerous direction. A table referenced from
-- inside an RLS policy expression is read as the CALLING user, so RLS on that
-- table applies again. `performance` SELECT is can_see_party(party), and the
-- `party` SELECT policy only reveals parties that are confirmed/live/completed
-- OR that the caller owns or administers. A real toque still in `draft` or
-- `pending_venue` -- or a cancelled one -- belonging to ANOTHER organizer is
-- therefore invisible to the moderator, the subquery returns no rows, the guard
-- reads "unused", and the cascade silently deletes that organizer's set-list
-- entry along with its signups and applause.
--
-- No such party exists in the database today (every non-test toque is confirmed
-- or live), which is exactly why this would have shipped unnoticed and surfaced
-- later as unexplained data loss. pending_venue is a routine state -- it is the
-- whole venue-approval flow.
--
-- SECURITY DEFINER runs the lookup as the owner, past RLS, so it sees every
-- performance and every party. This is the same reason is_dev(), is_party_admin()
-- and can_see_party() are all SECURITY DEFINER; the schema comments on those say
-- so explicitly.
create or replace function public.song_on_real_setlist(p_song bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.performance pf
      left join public.party pt on pt.id = pf.party
     where pf.song = p_song
       -- A performance with no party is missing information, not evidence the
       -- song is unused, so it counts as real and blocks. Unknown provenance
       -- protects the row. An inner join would have dropped those silently.
       and coalesce(pt.is_test, false) = false
  );
$$;

revoke all on function public.song_on_real_setlist(bigint) from public, anon, authenticated;
grant execute on function public.song_on_real_setlist(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The delete policy
-- ---------------------------------------------------------------------------
-- Two conditions, both required: the caller moderates, and the song is not on
-- any non-test set list. Test parties are excluded from the guard on purpose --
-- purge-stale-test-parties hard-deletes them daily, so a slot on one is not
-- something anybody relies on.
drop policy if exists "moderators may delete unused songs" on public.song;
create policy "moderators may delete unused songs"
  on public.song for delete
  to authenticated
  using (
    public.is_song_moderator()
    and not public.song_on_real_setlist(song.id)
  );

-- Supporting index: the guard runs this lookup per candidate row, and
-- performance.song had no index of its own (a FK does not create one).
create index if not exists idx_performance_song on public.performance (song);

-- ---------------------------------------------------------------------------
-- 4. The review list
-- ---------------------------------------------------------------------------
-- The moderation page needs the same privileged view the policy has, for the
-- same reason: a client query would be filtered by RLS and would offer a delete
-- button for a song the database will then refuse. Returning the counts from a
-- definer function keeps the screen and the policy reading the same facts.
--
-- Scope is `added_by is not null`. The catalogue is ~6.5k rows but all but ~18
-- came from the bulk seed with no added_by; those are not what "songs people
-- added" means, and listing them would bury the few that need review. The limit
-- is a backstop against unbounded growth, not a paging mechanism.
create or replace function public.songs_for_moderation()
returns table (
  id                bigint,
  title             varchar,
  artist            varchar,
  ref_link          text,
  created_at        timestamptz,
  added_by_nickname varchar,
  real_uses         bigint,
  test_uses         bigint,
  real_parties      jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.title, s.artist, s.ref_link, s.created_at,
         pr.nickname,
         count(*) filter (where pf.id is not null and coalesce(pt.is_test, false) = false),
         count(*) filter (where pf.id is not null and pt.is_test = true),
         -- Which toques block it. A count alone is not enough to judge whether
         -- the block is correct; a null id here is an orphaned performance.
         coalesce(
           jsonb_agg(distinct jsonb_build_object('id', pt.id, 'title', pt.title))
             filter (where pf.id is not null and coalesce(pt.is_test, false) = false),
           '[]'::jsonb
         )
    from public.song s
    left join public.profile pr    on pr.id = s.added_by
    left join public.performance pf on pf.song = s.id
    left join public.party pt       on pt.id = pf.party
   where s.added_by is not null
     -- Gated inside: a non-moderator gets an empty set, not the catalogue.
     and public.is_song_moderator()
   group by s.id, s.title, s.artist, s.ref_link, s.created_at, pr.nickname
   order by s.created_at desc
   limit 500;
$$;

revoke all on function public.songs_for_moderation() from public, anon, authenticated;
grant execute on function public.songs_for_moderation() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Seed the one moderator
-- ---------------------------------------------------------------------------
-- Cami Soto. Matched on the profile id rather than nickname or email so a
-- display-name change cannot silently move the privilege.
insert into public.song_moderator (user_id)
values ('0671ee04-4ab2-4f59-a6f6-e5cda28677d8')
on conflict (user_id) do nothing;

commit;

-- =============================================================================
-- supabase/schema.sql and src/lib/database.types.ts were updated by hand in the
-- same commit (including the stale cascade on performance_song_fkey, which
-- schema.sql had recorded without it). Re-run the generator after applying to
-- confirm the hand-written types match.
--
-- To verify the guard actually holds, exercise it over REST as the moderator --
-- NOT from the SQL editor, where you are the table owner and RLS does not apply
-- at all, so every delete succeeds and tells you nothing:
--   7042 "Pride (In The Name Of Love)"  on 2 real toques      -> must refuse
--   7041 "One" / Metallica              on 1 TEST toque only  -> must allow
-- A refusal looks like 204 with an EMPTY body, not an error, so check the
-- returned row count (the page uses .select() for exactly this reason).
-- =============================================================================
