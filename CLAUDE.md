# Rock Party — Project Context

Read this before making changes. It captures everything known about the
project's state as of August 2026, after ~9 months idle (last commit
2025-11-05).

## What this is

"Rock Party" (branded "Rock the House") is an app for organizing jam
sessions / gigs among musicians. Spanish-language UI. Core entities:

- **Parties** ("toques" = gigs) — an event at a venue on a date
- **Venues** — locations, with admin permissions and contact info (WhatsApp, Instagram)
- **Performers** — musicians who can be assigned to performances
- **Songs** — looked up via MusicBrainz integration
- **Performances** — a performer playing a song (or set) at a party, orderable via drag-and-drop

## Stack

- **Framework:** SvelteKit 2, Svelte 5
- **Styling:** Tailwind CSS (custom theme, see below) + `@tailwindcss/typography`
- **Backend:** Supabase (Postgres + Auth + Storage) — accessed **client-side
  only**, no server routes (`+page.server.js/ts`) exist anywhere in the repo.
  Security relies entirely on Supabase Row Level Security (RLS) policies.
- **Auth:** Google OAuth via Supabase Auth
- **Drag-and-drop:** SortableJS
- **Deployment:** Netlify (`netlify.toml` — `pnpm run build`, publish `build/`)
- **Package manager:** pnpm

## Constraints & principles

Guidelines that shape what we build and how — weigh new features against these.

- **Free-tier-first.** Keep the project runnable on free service tiers as much as
  possible (Supabase free, Netlify free). Weigh every feature against its ongoing
  cost before reaching for a paid tier. This — not any one technique — is the
  governing rule.
- **Media/storage: whatever stays free.** Storage is fine when it's free-tier —
  Supabase Storage's free tier (already in the stack) is fair game, as is any
  free-tier service we integrate. External links (YouTube, Spotify, Instagram,
  photo albums) are a good zero-cost default and the fallback when volume would
  exceed a free limit. The rule is cost, not a ban on storing media.
- **Augment the humans, don't automate their judgment.** The app supports the
  people running the scene rather than replacing their decisions — e.g. capacity
  caps over reputation ranking, a "run the show" console over an auto-advancing
  timer, applause with no engagement-farming.
- **Future interest:** comments and media (as external links) attached to past
  performances — see the Encore phase of the roadmap.

## Design system (already implemented, don't redesign — extend)

Defined in `tailwind.config.ts`:

| Token | Value | Use |
|---|---|---|
| `cold-base` | `#6C04FF` | primary purple |
| `warm-base` | `#FF4000` | primary orange |
| `cold-light` | `#A395FF` | links, secondary accents |
| `mid` | `#71118E` | gradient midpoint |
| `yellow` | `#FFAE00` | highlight accent |
| `base-950` | `#1A1A1A` | page background |
| `base-900` | `#262626` | card/surface background |

Font: **Roboto Condensed** (loaded via Google Fonts in `app.css`), light
weights by default (`font-weight: 300` on body/headings). Logo lives at
`src/lib/assets/images/Logo.png` (purple-to-orange gradient wordmark, "ROCK
the HOUSE"). Additional glyph at `static/images/Digital_Glyph_White.svg`.

## Supabase setup

- Project name: **RockParty**
- Was **paused** (Supabase free-tier auto-pause after 7 days inactivity) as
  of Aug 2026. Restorable from dashboard until **16 Apr 2027**. If you're
  reading this and the app can't connect to the DB, check
  https://app.supabase.com first — the project may need a one-click Restore.
- Env vars required (see `.env.example`): `PUBLIC_SUPABASE_URL`,
  `PUBLIC_SUPABASE_ANON_KEY`. Read via `$env/dynamic/public` in
  `src/lib/supabaseClient.js` — **must be prefixed `PUBLIC_`** or SvelteKit
  won't expose them client-side.
- **Schema:** `supabase/schema.sql` is the AUTHORITATIVE schema, captured
  2026-08-11 from the live DB via the SQL Editor (see
  `supabase/dump-authoritative.sql` to refresh it). It includes types, keys,
  FKs, indexes, and full RLS policies. **11 tables:**
  - Core: `party`, `venue`, `song`, `performance`, `profile`
  - Admin/permissions (enforced by RLS): `venue_admin`, `party_admin`
  - Junction: `performance_user` (performer × instrument × performance)
  - Lookups (publicly readable): `role`, `venue_type`, `instrument`
- **There is NO `performer` table.** "Performers" are `profile` rows; a
  performer is attached to a set-list slot via `performance_user`.
  `/performers/[id]` is a profile view. Older notes implying a `performer`
  table are wrong.
- **Admin actions ARE enforced by RLS** (not just UI-hidden): `venue`/`party`
  UPDATE policies check `created_by` or membership in `venue_admin`/`party_admin`.
  Caveat: `performance` UPDATE is open to any authenticated user (`using true`).
- After any Supabase project restore/recreation, also re-check: Google OAuth
  redirect URLs in Supabase Auth settings, and Netlify's environment
  variables (they're separate from local `.env`).

## Commands

```bash
pnpm install
pnpm run dev          # local dev server
pnpm run build        # production build
pnpm run preview      # preview production build
pnpm run check        # svelte-check + type checking
pnpm run lint         # prettier --check + eslint
pnpm run format       # prettier --write
```

## Branching & deploy workflow

Two-branch model: **`main` = production, `dev` = work-in-progress.**

- **Do all work on `dev`** and commit/push progress there freely. Netlify only
  auto-builds `main`, so nothing on `dev` triggers a deploy or spends build
  minutes.
- **Deploy = merge `dev` → `main`** (deliberately, only when `dev` is
  shippable):
  ```bash
  git checkout main && git merge --ff-only dev && git push && git checkout dev
  ```
  Fast-forward keeps `main`'s history a clean, linear list of what's live. The
  push to `main` is the ONLY thing that deploys.
- **Keep `main` always-deployable** — don't merge unless `pnpm run check` is
  clean and the app runs.
- **Review gate — per issue (primary):** run the **`code-review`** skill as each
  issue is finished, *before* committing/closing it (`git diff` / `--staged`),
  and clear any 🔴 blocking findings first. Small per-issue diffs catch more than a
  big end-of-phase sweep. A lighter pass on the full `dev` vs `main` diff before
  merging confirms the batch is coherent. The skill encodes this repo's real risk
  areas (RLS security, Svelte legacy-mode reactivity traps, dark-theme/token
  rules, unbounded queries, the toast pattern, migration/type discipline).
- `main` is the GitHub default branch and Netlify's production branch. Keep
  Netlify **branch deploys OFF** (default) so `dev` never builds; test locally
  instead.
- `netlify.toml` also has a build-`ignore` rule that skips builds when only
  docs/schema/backlog change — a backstop for commits that land on `main`
  directly.
- Use the **camilo-otro** identity for all git ops (see git config / memory).

## Known rough edges (full tracked list is in GitHub Issues)

- Liberal use of `any` types in `.svelte` files instead of generated
  Supabase types
- Action/mutation feedback now uses a shared toast pattern
  (`src/lib/stores/toasts.ts` + `Toasts.svelte`, mounted in the layout;
  `reportError`/`toastSuccess`/`toastError`/`toastInfo`). Uncaught route errors
  render the themed `src/routes/+error.svelte`. Page-**load** failures are still
  inline `{:else if error}` states by design (a toast alone would leave a blank
  content region). The auth-gate "Debes iniciar sesión" notices are still
  light-themed inline blocks — not migrated.

## History snapshot

~50 commits, Aug 1 2025 → Nov 5 2025, then idle until this session
(Aug 2026). One feature branch (`venue_contact`) was merged for
venue WhatsApp/Instagram contact info. Repo was private, made public
2026-08-11 to unblock tooling access; consider re-privating once the
GitHub connector/access situation is sorted, if that matters to you.

## Where things stand as of this session

1. Confirmed decision: **build on existing codebase, don't rewrite.**
2. Supabase project found paused, user is restoring it now via dashboard.
3. GitHub connector (Claude web) was flaky — tool registration didn't sync
   even after the user confirmed "Connected" status in settings. Not
   resolved as of this writing. If you (Claude Code) have direct `gh` CLI
   or git access, that sidesteps the issue entirely.
4. The backlog now lives in **GitHub Issues**, organized into per-epic
   milestones: https://github.com/camilo-otro/rockparty/issues (migrated from
   the old BACKLOG.md, which was removed).
