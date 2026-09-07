-- =============================================================================
-- Migration: every performance gets a running-order position (#37)
-- Date: 2026-09-06
-- =============================================================================
-- BUG: songs added through the setlist flow never set "order", so they landed
-- NULL. The Stage 1 migration backfilled the rows that existed then, but the
-- insert path was never fixed, so every song added since is NULL again.
--
-- Why that scrambles the setlist: the detail page fetched performances with no
-- ORDER BY and sorted client-side with `(a.order ?? MAX) - (b.order ?? MAX)`,
-- which returns 0 for every pair when all orders are NULL. A stable sort then
-- just preserves whatever order Postgres handed back — and an UPDATE rewrites a
-- row's tuple and moves it physically, so start_show and every advance_show
-- changed the apparent order. Exactly the reported symptom.
--
-- Fixing it in the DB rather than in one client: a trigger covers the multi-add
-- flow, the clone flow, and anything added later, and it cannot be forgotten.
-- =============================================================================

begin;

create or replace function public.performance_default_order()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Append to the end of that toque's running order. An explicit order (the
  -- clone flow sets one) is always respected.
  if new."order" is null and new.party is not null then
    select coalesce(max(p."order") + 1, 0)
      into new."order"
      from public.performance p
     where p.party = new.party;
  end if;
  return new;
end;
$$;

drop trigger if exists performance_set_default_order on public.performance;
create trigger performance_set_default_order
  before insert on public.performance
  for each row execute function public.performance_default_order();

-- Backfill whatever slipped through since the Stage 1 migration. Idempotent:
-- only touches rows still NULL, and orders them by id so the result matches the
-- order they were added in.
with ordered as (
  select id,
         (row_number() over (partition by party order by "order" nulls last, id) - 1)::smallint as n
  from public.performance
  where party is not null
)
update public.performance p
set "order" = o.n
from ordered o
where p.id = o.id
  and p."order" is null;

commit;
