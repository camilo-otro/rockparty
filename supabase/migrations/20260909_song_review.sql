-- =============================================================================
-- Migration: mark a reviewed song as done, so the list drains (#100)
-- Date: 2026-09-09  (follow-up to 20260909_song_moderation.sql, same day)
-- =============================================================================
-- The moderation list is every song with an added_by. That set only ever GROWS,
-- so without a "done" state the screen becomes a permanent backlog: the same 17
-- rows every visit, with new ones mixed in among them and no way to tell which
-- have already been looked at. A review queue that never drains stops being read.
--
-- Approval is deliberately ORTHOGONAL to deletability. Most of the noise is
-- songs that are perfectly fine AND on a real set list — "Shy Away", "She",
-- "Limón y Sal" — which can never be deleted and would otherwise sit in the list
-- forever. So a song can be approved whether or not it is deletable, and
-- approving does not touch the delete guard.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The reviewed stamp
-- ---------------------------------------------------------------------------
-- Nullable columns on `song` rather than a `song_review` side table: this is one
-- fact per song with no history worth keeping, `added_by` already lives here as
-- comparable provenance metadata, and it keeps the review list a single-table
-- scan. Both are additive and nullable, so the existing `select('*')` in
-- songs/[id] and the `setof song` return of search_songs stay valid.
alter table public.song
  add column if not exists reviewed_at timestamptz;
-- Who cleared it. Only one person moderates today, but recording it now means
-- the answer exists if that ever changes; backfilling it later would not work.
alter table public.song
  add column if not exists reviewed_by uuid references public.profile (id);

-- ---------------------------------------------------------------------------
-- 2. Setting the stamp — an RPC, not an UPDATE policy
-- ---------------------------------------------------------------------------
-- `song` has no UPDATE policy at all today, so nobody can modify a catalogue
-- entry. Adding one for moderators would hand them the whole row, because RLS
-- cannot restrict WHICH COLUMNS an update touches — the same limitation that
-- forced #95's confirm_requirement into a SECURITY DEFINER RPC and that makes
-- profile.role unusable as a gate (#99).
--
-- So the write surface stays exactly two columns, and `song` keeps its "nobody
-- edits the catalogue from the client" property.
create or replace function public.set_song_reviewed(p_song bigint, p_reviewed boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_song_moderator() then
    raise exception 'not a song moderator' using errcode = '42501';
  end if;

  update public.song
     set reviewed_at = case when p_reviewed then now() else null end,
         reviewed_by = case when p_reviewed then (select auth.uid()) else null end
   where id = p_song;

  -- A silent no-op on a bad id would look identical to success from the client.
  if not found then
    raise exception 'song % not found', p_song using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.set_song_reviewed(bigint, boolean) from public, anon, authenticated;
grant execute on function public.set_song_reviewed(bigint, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The review list, now filtered
-- ---------------------------------------------------------------------------
-- DROP first: the return type gains columns, and `create or replace` cannot
-- change a function's result type. The parameter also makes it a new signature,
-- so the old zero-arg version would linger as an overload and PostgREST would
-- not know which one a bare call meant.
drop function if exists public.songs_for_moderation();

-- p_reviewed selects WHICH queue, exclusively -- it does not merely widen the
-- result. An "include reviewed" flag would return both sets and leave the split
-- to the client, which puts the `limit 500` on the wrong side of the filter: a
-- large pending queue would crowd the reviewed rows out of the response
-- entirely. Defaults to the pending queue, which is the job.
create or replace function public.songs_for_moderation(p_reviewed boolean default false)
returns table (
  id                bigint,
  title             varchar,
  artist            varchar,
  ref_link          text,
  created_at        timestamptz,
  added_by_nickname varchar,
  real_uses         bigint,
  test_uses         bigint,
  real_parties      jsonb,
  reviewed_at       timestamptz,
  reviewed_by_nickname varchar
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
         coalesce(
           jsonb_agg(distinct jsonb_build_object('id', pt.id, 'title', pt.title))
             filter (where pf.id is not null and coalesce(pt.is_test, false) = false),
           '[]'::jsonb
         ),
         s.reviewed_at,
         rv.nickname
    from public.song s
    left join public.profile pr     on pr.id = s.added_by
    left join public.profile rv     on rv.id = s.reviewed_by
    left join public.performance pf on pf.song = s.id
    left join public.party pt       on pt.id = pf.party
   where s.added_by is not null
     and (s.reviewed_at is not null) = p_reviewed
     -- Gated inside: a non-moderator gets an empty set, not the catalogue.
     and public.is_song_moderator()
   group by s.id, s.title, s.artist, s.ref_link, s.created_at, pr.nickname,
            s.reviewed_at, rv.nickname
   -- Reviewed rows sort by when they were cleared, so the "ya revisadas" view
   -- reads as a log of recent decisions rather than by original add date.
   order by coalesce(s.reviewed_at, s.created_at) desc
   limit 500;
$$;

revoke all on function public.songs_for_moderation(boolean) from public, anon, authenticated;
grant execute on function public.songs_for_moderation(boolean) to authenticated;

commit;

-- =============================================================================
-- NOT backfilled on purpose. The 17 existing entries have never actually been
-- reviewed; stamping them would empty the queue by declaring the work done
-- rather than doing it. They stay pending until someone clears them.
--
-- supabase/schema.sql and src/lib/database.types.ts are updated in the same
-- commit. Re-run the generator after applying to confirm they match.
--
-- To verify over REST (as the moderator, NOT the SQL editor — there you are the
-- table owner and RLS does not apply):
--   rpc/set_song_reviewed {p_song: <id>, p_reviewed: true}  -> song leaves the
--     default list, appears in the p_reviewed: true one
--   the same call with an anon token                        -> 42501
-- =============================================================================
