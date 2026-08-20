-- =============================================================================
-- Migration: make can_see_party SECURITY INVOKER (follow-up to party status)
-- Date: 2026-08-20
-- =============================================================================
-- The status migration created can_see_party as SECURITY DEFINER, which the
-- advisor flags (a definer function callable by anon/authenticated via
-- /rest/v1/rpc). There's no recursion risk (party's SELECT policy doesn't
-- reference performance), so switch it to SECURITY INVOKER and let it lean on
-- party's own SELECT policy for the visibility rule. Behavior is identical;
-- the performance policy that calls it needs no change.
-- =============================================================================

create or replace function public.can_see_party(pid bigint)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (select 1 from public.party p where p.id = pid);
$$;
