# Rock Party — Project Context

Read this before making changes. Current as of **September 2026** and actively
developed. Where a fact here disagrees with the database or the code, the
database and the code win — check, then fix this file.

## What this is

"Rock Party" (branded "Rock the House") is an app for organizing jam
sessions / gigs among musicians. Spanish-language UI. Core entities:

- **Parties** ("toques" = gigs) — an event at a venue on a date
- **Venues** — locations, with admin permissions and contact info (WhatsApp, Instagram)
- **Performers** — musicians who can be assigned to performances
- **Songs** — a shared catalogue (~6.5k rows). Metadata comes from **Spotify**
  via the `spotify-track` edge function (#80/#83); an older note here said
  MusicBrainz, which is no longer used. Anyone signed in can add one in a single
  tap from the setlist (#98), which is why `/songs/moderation` exists (#100).
- **Performances** — a performer playing a song at a party. Ordered by an
  `order` column, moved with up/down buttons (there is **no** drag-and-drop
  library; SortableJS was removed).
- **Bands** — a persistent lineup that can be signed up for a performance (#40),
  with claim links for members who have no account yet (#79).
- **Logistics** — what a toque needs and who brings it: `party_requirement`
  rows sourced from a venue, an organizer, a musician or a rental (#95/#97).

## Stack

- **Framework:** SvelteKit 2, Svelte 5
- **Styling:** Tailwind CSS (custom theme, see below) + `@tailwindcss/typography`
- **Backend:** Supabase (Postgres + Auth + Storage) — accessed **client-side
  only**, no server routes (`+page.server.js/ts`) exist anywhere in the repo.
  Security relies entirely on Supabase Row Level Security (RLS) policies.
- **Auth:** Google OAuth via Supabase Auth
- **Deployment:** Netlify (`netlify.toml` — `pnpm run build`, publish `build/`),
  live at **https://rockthehouse.app** — see **Production & infrastructure** below
- **Package manager:** pnpm

## Production & infrastructure

The "where it runs" reference. The Supabase and deploy-workflow sections below
carry the deeper detail; this is the at-a-glance map.

- **Live site:** **https://rockthehouse.app** — custom domain served by Netlify.
  Production is the `main` branch; every push to `main` triggers a Netlify build
  (`pnpm run build` → publish `build/`). `dev` never builds (test locally).
- **Host:** Netlify. Runtime env vars (`PUBLIC_SUPABASE_URL`,
  `PUBLIC_SUPABASE_ANON_KEY`) are set in the Netlify UI, separate from local
  `.env`.
- **DNS / registrar:** `rockthehouse.app` is registered at **Cloudflare** and its
  DNS runs on Cloudflare nameservers (`sri`/`carla.ns.cloudflare.com`), pointing
  to Netlify for hosting. Registered **2025-09-20** (the domain was only ~5 weeks
  old during the late-Oct/Nov-2025 WhatsApp-share ban — newly-registered-domain
  reputation was a likely factor; see #68).
- **Database / Auth / Realtime:** Supabase project **RockParty**
  (ref `ohuhilcqluniqnkxiqhr`, API `https://ohuhilcqluniqnkxiqhr.supabase.co`).
- **Auth:** Google OAuth via Supabase. The Supabase Auth **Site URL** and the
  Google OAuth **authorized redirect URIs** must include
  `https://rockthehouse.app` (plus `http://localhost:5173` for local dev).
  Re-check these after any Supabase project restore.
- **Scheduled jobs:** `pg_cron` (installed) runs the daily jobs — the day-before
  toque reminder (#35 / #57) at 14:00, and `purge-stale-test-parties` at 15:00,
  which **hard-deletes** test toques that are cancelled (>1 day) or past-dated,
  cascading to their setlists, signups, RSVPs and applause. Definitions live in
  `supabase/migrations/`. Gotcha learned the hard way: for a `SECURITY DEFINER`
  function, `revoke ... from anon, authenticated` is a **no-op** — those roles
  inherit EXECUTE from `PUBLIC`. Revoke from `PUBLIC`.
- **Keep-alive:** `.github/workflows/supabase-keepalive.yml` — a daily GitHub
  Action pings the REST API (an *external* request; internal pg_cron doesn't
  count) to stop the 7-day free-tier auto-pause (#7). Needs the repo secret
  `SUPABASE_ANON_KEY`. GitHub disables it after ~60 days of no repo activity —
  use an external monitor (UptimeRobot / cron-job.org) for long idle stretches.
- **Realtime:** the `supabase_realtime` publication includes `notification`,
  `performance`, and `performance_user` — drives the live bell + setlist (#63).
  RLS still applies, so subscribers only receive rows they can `SELECT`.
- **Search:** `pg_trgm` (installed) backs song/toque search (#26).
- **Edge Functions:** `supabase/functions/*` — the app's only server-side code.
  So far: **`spotify-track`** (#80) resolves a pasted Spotify link to song
  metadata via the Web API Client-Credentials flow, keeping the Spotify secret
  off the client. Deployed to the same Supabase project (so it's live for every
  branch — not gated by the Netlify/`main` deploy). Secrets `SPOTIFY_CLIENT_ID`
  / `SPOTIFY_CLIENT_SECRET` are set in Supabase (Edge Functions → secrets), not
  in `.env`/Netlify. **The repo file is the source of truth**; the dashboard
  editor has no version control, so redeploy by pasting the repo file back in.
  Attribution note: Spotify's Developer Terms require attributing metadata with
  the Spotify Marks + a link back — the add-song UI shows the Spotify logo
  (`static/images/spotify-logo.svg`) + "Metadatos de Spotify" and stores the
  Spotify URL as `song.ref_link`.
- **Unlinked pages:** `static/roadmap.html` → https://rockthehouse.app/roadmap.html
  (product roadmap for the design collaborator; `noindex`, not in any nav).

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
- **English code, Spanish UI.** All code, routes, entities, DB objects, and logic
  are **English** (`party`, `/parties`, `band`, `/bands`); only user-facing copy is
  **Spanish** (labels like "Toques", "Bandas"). Keep code consistently English so
  future i18n can add languages without renaming anything. The public flyer lives
  at **`/flyer/[id]`**; the old Spanish `/toque/[id]` 308-redirects to it.
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

- Project name: **RockParty** (ref `ohuhilcqluniqnkxiqhr`; API URL
  `https://ohuhilcqluniqnkxiqhr.supabase.co`)
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
  FKs, indexes, and full RLS policies. **25 tables** (the count drifted as
  bands, logistics, applause and RSVPs landed — check `pg_tables` rather than
  trusting a number here):
  - Core: `party`, `venue`, `song`, `performance`, `profile`
  - Admin/permissions (enforced by RLS): `venue_admin`, `party_admin`
  - Grant-only privilege lists (no self-insert policy — granted via the SQL
    editor only): `dev_user` (#67), `song_moderator` (#100). These are the ONLY
    privilege mechanism; there is deliberately no role column on `profile` (#99).
  - Junction: `performance_user` (performer × instrument × performance),
    `profile_instrument` (performer × instrument they play — owner-managed, #28),
    `venue_equipment` (venue × equipment — venue-admin-managed, #30)
  - Lookups (publicly readable): `venue_type`, `instrument`, `equipment`
    (+ `equipment_suggestion`), `party_role`. `equipment` and `party_role` carry
    a stable `code` — match on it in migrations, never on the display name (#106).
- **There is NO `performer` table.** "Performers" are `profile` rows; a
  performer is attached to a set-list slot via `performance_user`.
  `/performers/[id]` is a profile view. Older notes implying a `performer`
  table are wrong.
- **Admin actions ARE enforced by RLS** (not just UI-hidden): `venue`/`party`
  UPDATE policies check `created_by` or membership in `venue_admin`/`party_admin`.
  `performance` UPDATE is party-admin only (creator or `party_admin`) — an older
  note here described it as `using true`, which has not been true for a while.
  `performance` INSERT, however, IS `with check (true)`: anyone signed in can add
  a song to any party's setlist.
  Venue-side checks go through `is_venue_admin()` (#102); do not inline a
  `venue_admin` subquery in a policy, as its SELECT is now restrictive.
- **Test-data visibility (#67):** `party.is_test` / `venue.is_test` hide dev/test
  rows from real users — the `party`/`venue` SELECT policies add
  `(is_test = false or public.is_dev())`, and performances inherit via
  `can_see_party()`. Developers are rows in `dev_user` (no self-insert policy —
  grant only via the SQL editor / service_role, so no self-escalation);
  `is_dev()` gates both visibility and the dev-only "Datos de prueba" toggle on
  the create/edit forms (default on for devs; non-devs always create real data).
  Songs/profiles stay global. Client flag state lives in
  `src/lib/stores/userFlags.ts` — `isDev`, `managesVenue`, `isSongModerator`,
  all filled by ONE `my_user_flags()` RPC call (#101). `dev.ts`, `venueAdmin.ts`
  and `songModerator.ts` no longer exist. `refreshUserFlags(uid)` REQUIRES the
  uid: calling `supabase.auth.getUser()` from inside `onAuthStateChange`
  re-enters the auth client and loops.
- **SECURITY DEFINER helpers** (the app's real permission vocabulary — prefer
  these over inlining a subquery, see *Recurring lessons*):
  `is_dev()`, `is_party_admin(pid)`, `is_band_manager(bid)`, `is_venue_admin(vid)`,
  `is_song_moderator()`, `can_see_party(pid)`, `can_see_band(bid)`,
  `can_applaud(pid)`, `can_sign_up_band(bid)`, `song_on_real_setlist(song)`.
  Narrow-write RPCs: `confirm_requirement`, `set_song_reviewed`, `sign_band_up`,
  `set_band_signup_status`, `claim_band_member`, and the live-mode controls
  (`start_show`, `advance_show`, `skip_song`, `jump_to_song`, `end_current_song`,
  `undo_last_move`, `end_show`). Read helpers: `my_user_flags()`,
  `songs_for_moderation()`, `search_songs(q, lim)`, `peek_band_claim(token)`.
- **Privilege is grant-only.** `dev_user` and `song_moderator` are the entire
  mechanism: no self-insert policy, membership added from the SQL editor. There
  is deliberately no role column on `profile` (#99) — role is derived from usage.
- After any Supabase project restore/recreation, also re-check: the Auth **Site
  URL** and Google OAuth redirect URIs (must include `https://rockthehouse.app`),
  and Netlify's environment variables (they're separate from local `.env`).

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
  push to `main` is the ONLY thing that deploys **the frontend**.
- **Two deploy targets that are NOT the Netlify push** — apply them when the diff
  touches them, independently of merging to `main` (they hit the shared Supabase
  project, so they affect every branch immediately):
  - **DB migrations** (`supabase/migrations/*`) — applied by hand in the Supabase
    SQL editor. Reconcile `supabase/schema.sql` + regenerate `database.types.ts`.
    **Ordering:** additive migrations can go first (the old client ignores what it
    does not know about). A migration that DROPS or RENAMES something the live
    client still reads must go AFTER the deploy — #99 drops a column the old
    `+layout.js` selected, and running it early would have bounced every
    signed-in user into the profile-creation form. Each migration should say
    which kind it is.
  - **Edge Functions** (`supabase/functions/*`) — deployed via the Supabase
    dashboard (Edge Functions → Deploy → *Via Editor*, name must match, paste the
    repo file) or the CLI. No dashboard version control → the repo file is the
    source of truth; redeploy by pasting it back in.
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
- **22 hardcoded `VOLVER` links.** Most pages have one entry point so it does not
  matter; `/performers/[id]` uses `afterNavigate` to remember where it was opened
  from, because it has four. Copy that pattern if another page grows entry points.
- **`performance` INSERT is `with check (true)`** — anyone signed in can add a
  song to any party's setlist. Deliberate today (the jam-night model), but it is
  what #110 has to tighten to keep non-members out of a band's set.

## History

~263 commits, Aug 2025 → Sep 2026, with a ~9-month gap (Nov 2025 → Aug 2026)
that a lot of older comments still refer to as "this session". The repo was made
public 2026-08-11 to unblock tooling access; whether to re-privatise is #24.

The backlog lives in **GitHub Issues**:
https://github.com/camilo-otro/rockparty/issues — organised into milestones
named for the roadmap phases (Soundcheck, Doors, Warm-up, Showtime, Encore) plus
two unnumbered buckets that run alongside them, **Housekeeping** and **On Tour**
(mobile). The older `Epic N:` milestones are closed; `epic-*` survives as a
cross-cutting label.

## Recurring lessons, learned the hard way

Patterns worth knowing before writing anything here — each one cost a real bug.

- **RLS cannot restrict WHICH COLUMNS an update touches.** Widening an UPDATE
  policy to let someone edit one field hands them the whole row. Every
  narrow write in this app is therefore a `SECURITY DEFINER` RPC:
  `confirm_requirement` (#95), `set_song_reviewed` (#100), and the reason
  `profile.role` was deleted rather than defended (#99).
- **A table referenced inside an RLS policy is read AS THE CALLING USER**, so
  its own policies apply again. That is why guards are definer functions
  (`is_dev`, `is_party_admin`, `is_band_manager`, `is_venue_admin`,
  `song_on_real_setlist`) and not inline subqueries. Inlining silently
  UNDER-blocks, and a self-referencing policy raises "infinite recursion".
- **A definer function used inside a policy that applies `to anon` must be
  EXECUTABLE by anon.** A policy calling a function the caller cannot execute
  raises permission-denied rather than evaluating false — revoking anon from
  `is_venue_admin` would take down the public flyer.
- **Granting EXECUTE needs both halves.** `create function` grants to PUBLIC and
  Supabase's `pg_default_acl` grants to anon/authenticated BY NAME. Revoke from
  `public, anon, authenticated`, then grant back deliberately.
- **PostgREST answers a refused DELETE with 200/204 and an empty body**, not an
  error. Check the returned row count (`.select()`), or a refusal reads as
  success.
- **Svelte 5 is in LEGACY mode.** `$:` tracks dependencies by NAME, textually. A
  helper that reads a store internally will not re-run — name the dependency in
  the statement, or pass it as an argument. Sets must be reassigned, never
  mutated in place.
- **Verify over REST, never in the SQL editor.** There you are the table owner,
  RLS does not apply, and every query succeeds while telling you nothing.
- **Test as the account that does NOT own the thing.** Most venue/party policies
  have a `created_by` branch that keeps working, so a pass as the creator proves
  nothing about the admin branch.
