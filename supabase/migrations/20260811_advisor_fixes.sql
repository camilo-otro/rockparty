-- =============================================================================
-- Migration: Supabase advisor fixes (performance + hygiene)
-- Date: 2026-08-11
-- Apply AFTER 20260811_tighten_performance_update_rls.sql (already applied to
-- prod). Wrapped in a transaction so it's all-or-nothing. Verified safe against
-- current data (venue_admin: 3 rows, no null/duplicate keys).
-- =============================================================================
-- Addresses these advisor lints:
--   * auth_rls_initplan  -> wrap auth.uid() in (select auth.uid()) so it's
--                           evaluated once per query, not once per row.
--   * unindexed_foreign_keys -> add covering indexes on FK columns.
--   * no_primary_key     -> give venue_admin a composite PK.
--   * function_search_path_mutable -> pin auto_add_admin's search_path.
-- Deliberately NOT fixed:
--   * duplicate_index (profile.user_auth_id_key == profile_pkey): all 7 FKs to
--     profile.id depend on the user_auth_id_key index, so it can't be dropped
--     without CASCADE-dropping and recreating those FKs. Not worth it for a
--     trivial duplicate on a tiny table; left as an accepted WARN.
-- Not included (do via dashboard): Postgres minor-version security upgrade.
-- =============================================================================

begin;

-- ---- 1. RLS: evaluate auth.uid() once per query, not per row ----------------
alter policy "allow update to party admins" on public.party
  using (
    (created_by = (select auth.uid()))
    or exists (
      select 1 from public.party_admin
      where party_admin.party_id = party.id and party_admin.user_id = (select auth.uid())
    )
  );

alter policy "allow update to venue admins" on public.venue
  using (
    (created_by = (select auth.uid()))
    or exists (
      select 1 from public.venue_admin
      where venue_admin.venue_id = venue.id and venue_admin.user_id = (select auth.uid())
    )
  );

alter policy "allow update to own user" on public.profile
  using (id = (select auth.uid()));

alter policy "Enable Update for authenticated users only" on public.performance
  using (
    exists (
      select 1 from public.party p
      where p.id = performance.party
        and (
          p.created_by = (select auth.uid())
          or exists (
            select 1 from public.party_admin pa
            where pa.party_id = p.id and pa.user_id = (select auth.uid())
          )
        )
    )
  );

alter policy "Enable update for authenticated users only" on public.performance_user
  using (user_id = (select auth.uid()));

alter policy "allow delete to own user" on public.performance_user
  using (user_id = (select auth.uid()));

alter policy "allow Insert to party owner and other party admins" on public.party_admin
  with check (
    ((select party.created_by from public.party where party.id = party_admin.party_id) = (select auth.uid()))
    or exists (
      select 1 from public.party_admin party_admin_1
      where party_admin_1.party_id = party_admin.party_id and party_admin_1.user_id = (select auth.uid())
    )
  );

alter policy "allow insert for party admins" on public.venue_admin
  with check (
    ((select venue.created_by from public.venue where venue.id = venue_admin.venue_id) = (select auth.uid()))
    or exists (
      select 1 from public.venue_admin venue_admin_1
      where venue_admin_1.venue_id = venue_admin.venue_id and venue_admin_1.user_id = (select auth.uid())
    )
  );

-- ---- 2. Covering indexes on foreign keys ------------------------------------
create index if not exists idx_party_created_by            on public.party (created_by);
create index if not exists idx_party_venue                 on public.party (venue);
create index if not exists idx_party_admin_user_id         on public.party_admin (user_id);
create index if not exists idx_performance_party           on public.performance (party);
create index if not exists idx_performance_song            on public.performance (song);
create index if not exists idx_performance_suggested_by    on public.performance (suggested_by);
create index if not exists idx_performance_user_instrument on public.performance_user (instrument_id);
create index if not exists idx_performance_user_user_id    on public.performance_user (user_id);
create index if not exists idx_profile_role                on public.profile (role);
create index if not exists idx_song_added_by               on public.song (added_by);
create index if not exists idx_venue_created_by            on public.venue (created_by);
create index if not exists idx_venue_venue_type            on public.venue (venue_type);
create index if not exists idx_venue_admin_user_id         on public.venue_admin (user_id);
-- (venue_admin.venue_id FK is covered by the new composite PK added below.)

-- ---- 3. Give venue_admin a primary key --------------------------------------
alter table public.venue_admin alter column user_id set not null;
alter table public.venue_admin add constraint venue_admin_pkey primary key (venue_id, user_id);

-- ---- 4. Pin search_path on the auto_add_admin trigger function --------------
-- Safe: the function fully-qualifies everything (public.party_admin, auth.uid()).
alter function public.auto_add_admin() set search_path = '';

commit;
