-- =============================================================================
-- Migration: ranked song search RPC (#82)
-- Date: 2026-09-04
-- =============================================================================
-- Replaces the client's `.or(title.ilike,artist.ilike).order(title).limit(20)`
-- which (a) ranked AFTER the server-side limit (so exact matches like "One" got
-- cut before the client could rank them), and (b) matched a whole multi-word
-- query against title OR artist, so "one metallica" found nothing.
--
-- search_songs splits the query into terms, requires EVERY term to appear in the
-- combined "title artist" text (cross-field), and ranks BEFORE limiting: exact
-- title > title prefix > exact artist > pg_trgm similarity of the combined text >
-- alphabetical. song is public-read, so this is a plain (invoker) function.
-- =============================================================================

begin;

create or replace function public.search_songs(q text, lim int default 20)
returns setof public.song
language sql stable
set search_path = ''
as $$
  with c as (select lower(trim(q)) as ql),
       terms as (select unnest(string_to_array((select ql from c), ' ')) as term)
  select s.*
  from public.song s, c
  where c.ql <> ''
    and not exists (
      select 1 from terms t
      where t.term <> ''
        and lower(coalesce(s.title, '') || ' ' || coalesce(s.artist, '')) not like '%' || t.term || '%'
    )
  order by
    (lower(s.title) = c.ql) desc,                                                     -- exact title
    (lower(s.title) like c.ql || '%') desc,                                           -- title prefix
    (lower(coalesce(s.artist, '')) = c.ql) desc,                                      -- exact artist
    -- pg_trgm's similarity(); schema-qualified because search_path is '' (pg_trgm
    -- lives in public). Built-ins resolve via the implicit pg_catalog.
    public.similarity(lower(coalesce(s.title, '') || ' ' || coalesce(s.artist, '')), c.ql) desc,
    s.title
  limit least(greatest(lim, 1), 50);
$$;

commit;
