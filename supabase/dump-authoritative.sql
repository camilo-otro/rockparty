-- =============================================================================
-- Authoritative schema dump helper
-- =============================================================================
-- The checked-in supabase/schema.sql is reconstructed from the REST API and is
-- NOT authoritative (no RLS, inferred types/keys). Run the queries below in the
-- Supabase Dashboard -> SQL Editor to capture the real definitions, then paste
-- the results back so schema.sql can be reconciled to match production.
--
-- (Requires no local tooling. If you prefer the CLI instead, the one-liner is:
--    npx supabase db dump --schema public --file supabase/schema.sql
--  using the connection string from Project Settings -> Database.)
-- =============================================================================

-- ****************************************************************************
-- ONE-SHOT: run just this statement to get EVERYTHING as one JSON cell, then
-- paste the single result back. (Copy the whole SELECT below, not this file's
-- name.) The individual queries (1-6) further down are the same data split up,
-- if you'd rather run them one at a time.
-- ****************************************************************************
select jsonb_pretty(jsonb_build_object(
  'columns', (
    select jsonb_agg(jsonb_build_object(
      't', table_name, 'pos', ordinal_position, 'col', column_name,
      'type', data_type, 'nullable', is_nullable, 'default', column_default)
      order by table_name, ordinal_position)
    from information_schema.columns where table_schema = 'public'),
  'constraints', (
    select jsonb_agg(jsonb_build_object(
      't', tc.table_name, 'ctype', tc.constraint_type, 'cname', tc.constraint_name,
      'col', kcu.column_name, 'ftable', ccu.table_name, 'fcol', ccu.column_name))
    from information_schema.table_constraints tc
    left join information_schema.key_column_usage kcu
      on kcu.constraint_name = tc.constraint_name and kcu.table_schema = tc.table_schema
    left join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema
    where tc.table_schema = 'public'),
  'indexes', (
    select jsonb_agg(jsonb_build_object('t', tablename, 'name', indexname, 'def', indexdef))
    from pg_indexes where schemaname = 'public'),
  'rls', (
    select jsonb_agg(jsonb_build_object(
      't', relname, 'enabled', relrowsecurity, 'forced', relforcerowsecurity))
    from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'),
  'policies', (
    select jsonb_agg(jsonb_build_object(
      't', tablename, 'name', policyname, 'cmd', cmd, 'roles', roles,
      'using', qual, 'check', with_check))
    from pg_policies where schemaname = 'public'),
  'enums', (
    select jsonb_agg(jsonb_build_object('type', t.typname, 'val', e.enumlabel, 'sort', e.enumsortorder))
    from pg_type t
    join pg_enum e on e.enumtypid = t.oid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public')
)) as schema_dump;


-- 1) Columns, types, nullability, defaults for every public table ------------
select
  table_name,
  ordinal_position          as pos,
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

-- 2) Primary keys, foreign keys, unique & check constraints ------------------
select
  tc.table_name,
  tc.constraint_type,
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name  as foreign_table,
  ccu.column_name as foreign_column
from information_schema.table_constraints tc
left join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name and kcu.table_schema = tc.table_schema
left join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name and ccu.table_schema = tc.table_schema
where tc.table_schema = 'public'
order by tc.table_name, tc.constraint_type, tc.constraint_name;

-- 3) Indexes -----------------------------------------------------------------
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
order by tablename, indexname;

-- 4) Row Level Security: is it enabled per table? ----------------------------
select relname as table_name, relrowsecurity as rls_enabled, relforcerowsecurity as rls_forced
from pg_class
where relnamespace = 'public'::regnamespace and relkind = 'r'
order by relname;

-- 5) RLS policies (the important part for Epic 2 security audit) --------------
select
  schemaname,
  tablename,
  policyname,
  cmd            as command,      -- SELECT / INSERT / UPDATE / DELETE / ALL
  roles,
  qual           as using_expr,   -- USING (...) row-visibility predicate
  with_check     as check_expr    -- WITH CHECK (...) write predicate
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- 6) Enum types, if any (explains role / venue_type integer codes) -----------
select t.typname as enum_type, e.enumlabel as value, e.enumsortorder as sort
from pg_type t
join pg_enum e on e.enumtypid = t.oid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public'
order by enum_type, sort;
