# Rock the House

An app for organizing jam sessions — _toques_ — among musicians: line up a
venue, build the setlist together, and see who's playing, running the show, or
coming to watch. Spanish-language UI, mobile-first, dark theme.

**Live:** https://rockthehouse.app

## Stack

- **SvelteKit 2 / Svelte 5** + **Tailwind CSS** (custom dark theme)
- **Supabase** (Postgres + Auth + Storage + Realtime), accessed **client-side
  only** — no server routes. Security relies entirely on Row Level Security
  (RLS) policies.
- **Auth:** Google OAuth via Supabase Auth
- **Hosting:** Netlify (production = the `main` branch)

## Local development

Requires [pnpm](https://pnpm.io/).

```bash
pnpm install
pnpm run dev          # local dev server at http://localhost:5173
```

Copy `.env.example` to `.env` and fill in the Supabase credentials — both
**must** be prefixed `PUBLIC_` or SvelteKit won't expose them client-side:

```
PUBLIC_SUPABASE_URL=...
PUBLIC_SUPABASE_ANON_KEY=...
```

### Other commands

```bash
pnpm run build        # production build
pnpm run preview      # preview the production build
pnpm run check        # svelte-check + type checking
pnpm run lint         # prettier --check + eslint
pnpm run format       # prettier --write
```

## Deploy

Two-branch model: **`main` = production, `dev` = work-in-progress.** Do all work
on `dev`; deploying is a deliberate fast-forward merge into `main`, which is the
only thing Netlify builds:

```bash
git checkout main && git merge --ff-only dev && git push && git checkout dev
```

Keep `main` always-deployable — only merge when `pnpm run check` is clean and the
app runs.

## More

- **Project context & conventions:** [`CLAUDE.md`](CLAUDE.md) — stack, design
  system, Supabase/RLS setup, infrastructure, and the branching workflow.
- **Roadmap & backlog:** [GitHub Issues](https://github.com/camilo-otro/rockparty/issues),
  organized into per-phase milestones. A visual snapshot lives at
  https://rockthehouse.app/roadmap.html.
- **Database schema:** [`supabase/schema.sql`](supabase/schema.sql) is
  authoritative (types, keys, FKs, indexes, RLS policies).
