# Backlog

Tracked here until GitHub Issues/Projects is wired up (connector was flaky
as of Aug 2026 — see CLAUDE.md). Migrate these to Issues once that's
sorted; keep this file in sync in the meantime or delete it once migrated.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done

---

## Epic 0: Get the environment running again
Priority: do this first, blocks everything else.

- [x] Restore paused Supabase project from dashboard (confirmed live —
      REST returns data, homepage renders venues)
- [x] Verify local `pnpm install && pnpm run dev` connects to DB successfully
- [ ] Verify Google OAuth login still works post-restore
- [x] Export current DB schema to a SQL file, commit it to the repo
      (closes the "no schema file" gap). Authoritative dump (types, keys, FKs,
      indexes, RLS) captured from the live DB and committed as
      `supabase/schema.sql`; refresh query kept in
      `supabase/dump-authoritative.sql`.
- [ ] Set up a keep-alive job (GitHub Action hitting the DB every 1-2 days)
      so this doesn't happen again on the free tier

## Epic 1: Design System Consistency
Bring every screen up to the current visual language.

- [ ] Restyle `/login` page to match Tailwind design system (currently
      plain HTML, predates the design system)
- [ ] Audit all pages for consistent spacing/typography per
      `tailwind.config.ts` tokens
- [ ] Remove leftover `/test` route from routes tree

## Epic 2: Security Hardening
All data access is client-side straight to Supabase — no server routes.

- [x] Audit and document Row Level Security (RLS) policies for every table.
      DONE — all 12 tables have RLS on; policies are captured verbatim in
      `supabase/schema.sql`. (No `performer` table; "performers" are `profile`
      rows joined via `performance_user`.)
- [x] Verify admin-only actions (venue edit, party admin) are enforced by
      RLS, not just hidden in the UI. CONFIRMED — `venue`/`party` UPDATE
      policies check `created_by` or `venue_admin`/`party_admin` membership.
- [x] FIX: `performance` / `performance_user` UPDATE policies used
      `using (true)` — any authenticated user could edit any set-list slot.
      Tightened to party owner/admins (performance) and owning user
      (performance_user); applied to prod and verified via pg_policies. See
      `supabase/migrations/20260811_tighten_performance_update_rls.sql`.
- [ ] Review deny-all tables: `role` and `temp_spotify_songs` have RLS on
      with no policies (no reads at all). Confirm `role` not being readable
      doesn't break any UI that wants role names; drop `temp_spotify_songs`
      if it's dead.
- [x] Ran Supabase security + performance advisors and fixed the actionable
      findings: wrapped `auth.uid()` as `(select auth.uid())` in 8 owner/admin
      policies (per-row re-eval), added 13 FK covering indexes, gave
      `venue_admin` a primary key, and pinned `auto_add_admin`'s search_path.
      See `supabase/migrations/20260811_advisor_fixes.sql`. Remaining advisor
      to-do: Postgres minor-version security upgrade (dashboard action).
- [ ] Confirm sanitization (`sanitize.ts`) is applied consistently across
      all create/edit forms

## Epic 3: Core Feature Completion

- [ ] Party lifecycle — check/define current status model (draft →
      confirmed → completed?)
- [ ] Performer song suggestions — verify the earlier bug fix holds
      (performers who hadn't suggested songs weren't being fetched)
- [ ] Venue contact info (WhatsApp/Instagram) — confirm it's exposed
      everywhere it should be in the UI (merged via `venue_contact` branch)

## Epic 4: Code Health

- [ ] Replace `any` types in `.svelte` files with generated Supabase types
- [x] ~~Add a checked-in DB schema file~~ → folded into Epic 0
- [ ] Set up a shared error boundary / toast pattern instead of inline
      per-page error strings

## Epic 5: Deployment & Docs

- [ ] Replace generic `sv`-template README with real project description,
      setup steps, required env vars
- [ ] Document the Netlify deploy process and required environment
      variables
- [ ] Decide whether to keep the repo public or re-privatize it (it was
      made public 2026-08-11 to unblock tooling access)
