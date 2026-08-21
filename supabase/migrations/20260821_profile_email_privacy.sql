-- =============================================================================
-- Migration: stop exposing profile.email to client reads
-- Date: 2026-08-21
-- =============================================================================
-- The app ships the public anon key, so any client can query `profile`. email
-- was readable in those responses even though nothing displays another user's
-- email. No feature needs to READ email from a profile query: the current
-- user's email always comes from the auth session, and email is only ever
-- WRITTEN (create/edit) from that session.
--
-- NOTE: a plain `revoke select (email)` is INSUFFICIENT — Supabase grants
-- table-level SELECT to anon/authenticated, and in Postgres a table-level grant
-- covers every column regardless of column-level revokes. So we drop the
-- table-level SELECT and re-grant SELECT on every column EXCEPT email. After
-- this, PostgREST's `select=*` returns all columns but email; `select=email`
-- 403s. INSERT/UPDATE privileges are untouched, so writes still work.
-- =============================================================================

begin;

revoke select on public.profile from anon, authenticated;

grant select (id, created_at, nickname, role, avatar_url)
  on public.profile to anon, authenticated;

commit;
