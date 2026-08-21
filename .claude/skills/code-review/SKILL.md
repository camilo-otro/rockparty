---
name: code-review
description: >-
  The code-review authority for the Rock Party ("Rock the House") app. Use this
  WHENEVER you review code for correctness or quality — before a dev→main merge,
  when the user says "review this", "check for bugs", "is this safe", "any
  issues", after finishing a feature and before committing, or when asked to look
  over a diff / PR / file. It encodes the repo's real risk areas: Supabase RLS
  security (the app is client-only, so RLS is the entire security boundary),
  Svelte 5 legacy-mode reactivity gotchas, the dark-theme + design-token rules,
  unbounded queries, the shared toast/error pattern, and schema/migration
  discipline. Trigger it for any review of Svelte/TS/SQL changes in this repo.
---

# Rock Party — code review

You are the code-review gate for **Rock the House** (SvelteKit 2 / Svelte 5 /
Supabase, client-only, Spanish UI, dark theme). Your job is to catch **real bugs
and security holes** before they reach `main` — not to bikeshed style. This app
has **no server routes**: security lives entirely in Supabase Row Level Security,
and the frontend is Svelte 5 running in legacy (`export let`) mode with its own
reactivity traps. Those two facts drive most of what matters here.

## When to run
- **As each issue is completed** — this is the PRIMARY cadence. Review the issue's
  changes *before* committing and closing it, while the diff is small, focused,
  and the context is fresh. Small per-issue diffs catch far more than one big
  end-of-phase sweep. Make this a standing step: finish the work → run this skill
  → clear 🔴 blockers → commit + close the issue.
- **Before a `dev` → `main` merge** — a lighter final pass (the per-issue reviews
  already did the deep work; here just confirm the batch is coherent and
  `pnpm run check` is clean).
- On request: "review this", "check for bugs", a specific file, or a diff/PR.

## What to review (scope)
Pick the tightest scope that covers the finished work:

1. **Per-issue, pre-commit (preferred):** the working-tree changes for the issue
   you just finished.
   ```bash
   git status --short
   git diff                 # unstaged
   git diff --staged        # staged
   ```
2. **Per-issue, already committed:** the commit(s) for this issue, e.g. the last N
   on `dev` since the issue work began.
   ```bash
   git log --oneline -8
   git diff <base>..HEAD    # <base> = commit before this issue's work
   ```
3. **Deploy candidate (final pass):** the whole `dev` vs `main` diff.
   ```bash
   git fetch origin main --quiet 2>/dev/null; git diff main...dev --stat
   git diff main...dev
   ```

If the user names specific files or a range, review that. Read the **full changed
files**, not just the hunks — a reactivity or RLS bug is often visible only in
context.

## How to review
1. Pull the diff and read each changed file in full.
2. Grade against `references/checklist.md`, in this priority order — **security and
   correctness first**, since those are what ship bugs:
   1. **Security (RLS / secrets / input)** — the highest-stakes category here.
   2. **Correctness** (reactivity, null-safety, dates, unbounded queries, logic).
   3. **Data/schema discipline** (migrations, generated types, schema.sql).
   4. **Consistency** (dark-theme tokens, the toast pattern, Spanish copy).
   5. **Polish / nits** (naming, dead code, `any` creep).
3. For each finding, decide: is this a **real defect** (would cause a wrong result,
   a security exposure, a crash, a broken state) or a **preference**? Only raise
   preferences as clearly-labeled nits. When unsure whether something is a bug,
   say so and describe the failing scenario rather than asserting.
4. Cross-check the running app or `pnpm run check` when a finding is testable.

## Output — prioritized, actionable
Report findings grouped by severity, most severe first. For each:
- **`file:line`** (clickable) + a one-line statement of the defect.
- The concrete **failing scenario** (inputs/state → wrong outcome) for bugs.
- A specific **fix**, with the token / pattern / API to use.

Use these severities:
- 🔴 **Blocking** — security hole, data loss, crash, or wrong result. Must fix before merge.
- 🟠 **Should-fix** — a real bug in an edge case, or a consistency break users will see.
- 🟡 **Nit** — style/polish; safe to defer.

End with a **verdict**: safe to merge, or the blocking items to clear first. If
nothing is wrong, say so plainly — don't invent findings. Offer to apply the
quick fixes and to file larger ones as GitHub issues.

## Don't
- Don't rewrite the diff or redesign; review it. Small inline fixes are fine when
  the user asks.
- Don't flag deliberate, documented divergences (see CLAUDE.md) as bugs — e.g.
  page-**load** errors are intentionally inline, not toasts; `any` types are a
  known, tracked rough edge (flag *new* gratuitous ones, not the existing sea).
- Don't approve a merge with `pnpm run check` failing.

See `references/checklist.md` for the detailed, repo-specific checks.
