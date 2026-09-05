-- =============================================================================
-- Migration: live mode — Stage 1 (#37)
-- Date: 2026-09-05
-- =============================================================================
-- The show's progress is one piece of state: which performance is playing right
-- now. Rather than a pointer column on `party`, each performance carries its own
-- live_state and the single 'playing' row IS the pointer.
--
-- Why: `performance` is already in the supabase_realtime publication and `party`
-- is not, so the audience view streams with no new plumbing; and one enum can't
-- disagree with itself the way a pointer + per-song state can.
--
-- See docs/specs/live-mode.md.
-- =============================================================================

begin;

-- ---- state -----------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'public' and t.typname = 'performance_live_state') then
    create type public.performance_live_state as enum ('queued', 'playing', 'played', 'skipped');
  end if;
end
$$;

alter table public.performance
  add column if not exists live_state public.performance_live_state not null default 'queued',
  add column if not exists started_at timestamptz,
  add column if not exists ended_at   timestamptz;

comment on column public.performance.live_state is
  'Live-show state. The single ''playing'' row per party is the now-playing pointer.';
comment on column public.performance.started_at is
  'When this song started. Setting it is what opens song applause (#38).';

-- At most one song playing per toque — a DB invariant, so two admins tapping
-- Next at once yield one winner and one 23505, never two now-playing songs.
create unique index if not exists performance_one_playing_per_party
  on public.performance (party) where live_state = 'playing';

-- Cheap lookup of "the next queued song" while advancing.
create index if not exists idx_performance_party_live_state
  on public.performance (party, live_state);

-- ---- realtime --------------------------------------------------------------
-- `performance` is already published; add `party` so status changes (show
-- started / ended / cancelled mid-show) stream to the audience view too.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'party'
  ) then
    alter publication supabase_realtime add table public.party;
  end if;
end
$$;

-- ---- persist the running order --------------------------------------------
-- `order` is null on essentially every existing row: the detail page sorts by
-- (order nulls last, then fetch order) and renumbers 0..n IN MEMORY, persisting
-- only when someone uses the reorder arrows. That was harmless while the order
-- was merely displayed — live mode ADVANCES through it, so the console and the
-- audience must agree on "next" deterministically.
--
-- Backfill by the same rule the UI has been showing (order nulls last, then id),
-- so nobody's setlist visibly reshuffles. Newly-added songs keep landing with a
-- null order and sort last, which is exactly "appended to the end".
with ordered as (
  select id, (row_number() over (partition by party order by "order" nulls last, id) - 1)::smallint as n
  from public.performance
  where party is not null
)
update public.performance p
set "order" = o.n
from ordered o
where p.id = o.id and p."order" is distinct from o.n;

-- ---- show control ----------------------------------------------------------
-- SECURITY INVOKER: RLS stays the boundary (performance/party UPDATE are already
-- restricted to the party's creator or a party_admin). The explicit guard is for
-- a clear error instead of a silent 0-row update.

-- Start the show: party -> live, and cue the first song in running order.
create or replace function public.start_show(p_party bigint)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_first bigint;
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can start the show';
  end if;

  update public.party set status = 'live'
  where id = p_party and status in ('confirmed', 'live');
  if not found then
    raise exception 'this toque cannot be started (must be confirmed)';
  end if;

  -- Already running? Leave the current song alone.
  select id into v_first from public.performance
  where party = p_party and live_state = 'playing' limit 1;
  if v_first is not null then
    return v_first;
  end if;

  select id into v_first from public.performance
  where party = p_party and live_state = 'queued'
  order by "order" nulls last, id limit 1;

  if v_first is not null then
    update public.performance
    set live_state = 'playing', started_at = now(), ended_at = null
    where id = v_first;
  end if;

  return v_first;
end;
$$;

-- The workhorse: end the current song and start the next one in running order.
-- Returns the id of the song now playing, or null when the setlist is spent.
create or replace function public.advance_show(p_party bigint)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_next bigint;
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can run the show';
  end if;

  -- Close the current song first, so the partial unique index is free.
  update public.performance
  set live_state = 'played', ended_at = now()
  where party = p_party and live_state = 'playing';

  select id into v_next from public.performance
  where party = p_party and live_state = 'queued'
  order by "order" nulls last, id limit 1;

  if v_next is not null then
    update public.performance
    set live_state = 'playing', started_at = now(), ended_at = null
    where id = v_next;
  end if;

  return v_next;
end;
$$;

-- End the show: close whatever is playing, party -> completed.
create or replace function public.end_show(p_party bigint)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_party_admin(p_party) then
    raise exception 'only a party admin can end the show';
  end if;

  update public.performance
  set live_state = 'played', ended_at = now()
  where party = p_party and live_state = 'playing';

  update public.party set status = 'completed' where id = p_party;
  if not found then
    raise exception 'could not end this toque';
  end if;
end;
$$;

commit;
