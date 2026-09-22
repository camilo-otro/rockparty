# Rock Party — review checklist

Repo-specific checks, ordered by stakes. Each item names a real failure mode seen
in (or latent in) this codebase. `→` is the fix.

## 1. Security — RLS is the ENTIRE security boundary
The app is client-only (no `+page.server.*`, no API routes). Anyone can call
Supabase with the public anon key and craft any query. **UI hiding is not
security** — only RLS is.

- **New table / column access:** does the table have RLS enabled with policies that
  actually match intent? A table with RLS on and *no* policy is deny-all (breaks
  reads); a table with `using (true)` on INSERT/UPDATE/DELETE is wide open (anyone
  can mutate). Lookups (`role`, `venue_type`, `instrument`) are intentionally
  world-readable; core/admin tables are not. → Add/adjust a policy; verify with
  the Supabase advisors (`get_advisors`).
- **Mutations must be authorization-checked in RLS**, not just gated in the
  component. Admin actions (edit venue/party, manage admins) must check
  `created_by = auth.uid()` or membership in `venue_admin`/`party_admin`. Known
  soft spot: `performance` UPDATE has historically been open — scrutinize any new
  open mutation policy.
- **A policy must never read its own table, and should not inline another's.**
  CLAUDE.md's rule is that a table referenced in a policy is read AS THE CALLER,
  so its policies apply again — use the DEFINER helper (`is_party_admin`,
  `is_venue_admin`, `can_edit_set`, …). A policy that reads its OWN table
  recurses on its own, with no help from anywhere else. This is not theoretical:
  on 2026-09-18 narrowing `party_admin`'s SELECT gave a previously trivial policy
  a body, closed a loop that had been latent for months, and took out toque
  creation for three days with `42501 infinite recursion detected`. It was
  invisible until somebody tried to create one.
  **Do not reason about the chains — ask the database.** One query, one second:

  ```sql
  -- any policy that reads its own table: these WILL recurse
  select c.relname, p.polname
  from pg_policy p join pg_class c on c.oid = p.polrelid
  where coalesce(pg_get_expr(p.polqual, p.polrelid), '')      ~* ('from\s+(public\.)?' || c.relname || '\M')
     or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') ~* ('from\s+(public\.)?' || c.relname || '\M');
  ```

  Run it after ANY policy change, not just one that looks risky — the change that
  breaks things is usually to a different table than the one that fails.
- **Recreating a policy? Diff `polroles` and `polwithcheck` first.** Omitting
  `with check` does not preserve it: Postgres silently reuses the USING clause,
  which is a different rule. A "behaviour-preserving" rewrite of `party`'s UPDATE
  policy quietly tightened it this way, because the original's `with check (true)`
  was never checked.
- **Secrets:** only `PUBLIC_`-prefixed env vars belong client-side. The anon key
  is public by design; the **service_role key must never** appear in client code,
  committed files, or `PUBLIC_` vars. Flag any hard-coded key/token.
- **PostgREST filter injection:** user input interpolated into `.or(...)`,
  `.ilike(...)`, `.filter(...)` strings can break the filter grammar or widen it
  (commas, parens, `%`, `_`). → Sanitize before building the filter, e.g.
  `term.replace(/[%_,()]/g, '')` (see `src/routes/songs/+page.svelte`). Bound
  results with `.limit()`.

## 2. Correctness

### Svelte 5 legacy-mode reactivity (the subtle bug source)
This repo uses `export let` (legacy runes-off mode). Dependency tracking is
**textual**: a `$:` statement or a `{#each expr}`/`{cond}` template expression
re-runs only when a variable **named in the expression itself** changes — NOT
when a variable read *inside a function it calls* changes.
- `$: list = applyFilters(items)` where `applyFilters` closes over `venueFilter`
  will **not** recompute when `venueFilter` changes. → Pass the deps as arguments
  so they appear textually: `$: list = applyFilters(items, venueFilter, dateFilter)`
  (see `src/routes/parties/+page.svelte`).
- `{#each getThings() as t}` won't re-run when state `getThings()` reads changes
  unless that state is also referenced in the template. → Prefer `$:` derived
  values with explicit deps over function calls in markup for filtered lists.
- `onMount(() => somethingAsync())` — a returned Promise is **not** a cleanup
  function. Return a real cleanup fn or nothing.
- Every `user.subscribe(...)` / store subscription created in `onMount` must be
  unsubscribed in `onDestroy` (the pattern is `unsubscribeUser`). Flag leaks.

### Data & logic
- **Unbounded queries:** `.select('*')` on a large table (e.g. `song` has ~6.5k
  rows) ships everything to the client. → Add server-side search (trigram `ilike`,
  the indexes exist) + `.limit()`. Browse defaults should cap rows.
- **Null-safety:** `.single()` can return `{ data: null }`; Supabase rows may have
  null columns. Guard with optional chaining and empty-state branches before
  dereferencing.
- **Dates:** party dates must not be in the past on create (client-side check
  exists). Build `YYYY-MM-DD` from local parts (`getFullYear()/getMonth()+1/...`),
  not `toISOString()` (which is UTC and can shift the day). Compare dates
  consistently.
- **Schema truth:** `key` (tonalidad) lives on `performance`, **not** `song`.
  Don't read song-level fields that don't exist. When in doubt, check
  `src/lib/database.types.ts` / `supabase/schema.sql`.

## 3. Data / schema discipline
- Any DDL change ships as a file in `supabase/migrations/*.sql`, **and** updates
  `supabase/schema.sql` (authoritative) **and** regenerates
  `src/lib/database.types.ts`. A migration without the matching type regen is a
  finding.
- **Irreversible operations** (`drop table`, `drop column`, destructive updates)
  must be called out explicitly and be loss-checked — e.g. migrate straggler rows
  before a drop (see the `temp_spotify_songs` migration). Migrations are applied
  by the user in the SQL Editor; the review should flag anything risky to run.

## 4. Consistency (design + patterns)
- **Dark theme only.** No light surfaces — flag `bg-slate-100`, `bg-red-100`,
  `bg-green-100`, `bg-yellow-100`, `text-slate-*` on backgrounds, etc. Use tokens:
  `base-950` page, `base-900` surfaces, `cold-base`/`cold-light`, `warm-base`,
  `yellow`. No new colors/fonts/radii outside the set. (For anything visual,
  defer to the `rockparty-design` skill.)
- **Native form controls** (`<input type=date>`, `<select>`) need
  `color-scheme: dark` — it's global in `app.css`, so flag any inline style/reset
  that would override it and make icons invisible on the dark field.
- **Error/action feedback uses the shared toast pattern**
  (`src/lib/stores/toasts.ts`: `reportError`/`toastError`/`toastSuccess`/
  `toastInfo`), not new inline alert boxes. Forms should stay visible on error so
  the user can retry. Page-**load** errors staying inline is intentional — not a
  finding.
- **Spanish copy**, in the app's voice. Flag English strings in user-facing UI.

## 5. Constraints & polish
- **Free-tier-first:** flag features that assume a paid Supabase/Netlify tier or
  heavy hosted media. Media should be external links or free-tier storage.
- **Types:** prefer generated Supabase types over `any`. The existing `any` sea is
  a tracked rough edge — flag *new* gratuitous `any`, don't relitigate the rest.
- **Dead code / leftovers:** removed features should remove their state, imports,
  and markup (e.g. dropping an inline error box → also drop its now-unused
  `success`/`error` vars and `fly` import).

## Gate
- `pnpm run check` must be clean (0 errors) before approving a merge.
- Prefer verifying testable findings against the running app (Browser preview) or
  the Supabase advisors rather than asserting.
