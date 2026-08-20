---
name: rockparty-design
description: >-
  The design authority for the Rock Party ("Rock the House") app. Use this
  WHENEVER you review the app's look and feel, design or build a new screen /
  view / component, restyle an existing one, or make any call about color,
  typography, spacing, contrast, states, or copy — even if the user doesn't say
  "design". Trigger it for a Svelte page/component that renders UI, a design
  review or UX audit, "does this match the design / Figma", dark-theme control
  issues, status/badge/empty/loading/error-state styling, or anything visual.
  The Figma file is the authoritative source of truth; this skill wires you to
  it and to the app's tokens.
---

# Rock Party — design

You are the design lead for **Rock the House**, a mobile-first, dark-themed app
for organizing jam sessions ("toques") among musicians. Spanish UI. This skill
makes design work consistent with the established visual language instead of
re-deriving it each time.

## Authoritative sources
The Figma and the code tokens together define the **design language** — palette,
type, spacing, and component vocabulary. Treat them as the guidelines to design
*within*, NOT a pixel-perfect spec to converge the whole app back to. **The app
has intentionally evolved past some Figma frames**, and those divergences are
deliberate — not bugs to fix.

1. **Figma — authoritative for the visual *language*** (tokens, type, component
   patterns/vocabulary), not for exact per-screen fidelity.
   `https://www.figma.com/design/CYgSEvo4PG1d5gLaeIFscC/Rock-party` · fileKey
   `CYgSEvo4PG1d5gLaeIFscC`. Pull with the Figma MCP tools to see intended patterns:
   - `get_metadata(fileKey)` → frames/components (screens: Home, Próximos toques,
     Toque detail, Canción detail; components: Toque, Cancion, Instrumentos, Spots,
     Musicos, Logo).
   - `get_screenshot(fileKey, nodeId)` → view a frame (download the URL).
   - `get_design_context(fileKey, nodeId)` → exact colors/type/spacing (load the
     figma-design-to-code guidance first, as that tool requires).
   Some frames are stale vs the built app — mine them for the *language*, not as a
   checklist.
2. **The implemented tokens** — `tailwind.config.ts` + `src/app.css` (see
   `references/design-system.md`) — the real values to build with. When a new
   pattern emerges in code that Figma lacks, the code + this skill are the living
   record until Figma catches up.

## Project constraints that shape design (from CLAUDE.md)
- **Dark theme only** — `base-950` page, `base-900` surfaces. Design for dark.
- **Mobile-first** — the Figma frames are 393px wide. Design at phone width; scale up.
- **Spanish copy** — labels and messages in Spanish, matching the app's voice.
- **Free-tier-first** — media is external links or small free-tier uploads; don't
  design flows that assume heavy hosted assets.

## Component workbench (Storybook)
Run `pnpm storybook` (Storybook 10, on :6006) to review and adjust components in
isolation across all their states — the fastest way to judge spacing, sizing, and
state coverage without clicking through the app. Stories live next to their
component as `*.stories.ts` and the preview loads `app.css`, so they render on the
real dark theme + tokens. Add a story when you build or restyle a component; use
the a11y/controls panels to check contrast and prop variants. `StatusBadge` has
the first story as the pattern to copy.

## Two modes

### A. Reviewing (audit an existing screen or the whole app)
Judge against the **design language's consistency and real UX quality**, not
literal Figma fidelity — the Figma can lag the app, and deliberate divergences are
fine. Work through `references/review-checklist.md`:
1. Screenshot the built screen; reference the Figma for the intended patterns.
2. Grade — contrast/legibility first (catches the most), then consistency *within
   the app* and with the token/pattern vocabulary, then state coverage, spacing, copy.
3. A difference from a Figma frame is a finding only if it's a genuine problem
   (broken contrast, inconsistent with the rest of the app, a missing state) — not
   merely "doesn't match an old frame." When unsure whether a divergence is
   intentional, ask rather than assume.
4. Report **prioritized** (blocking → visible inconsistency → polish), each with
   the specific fix + token. Offer to file larger ones as issues and apply quick ones.

### B. Designing a new screen / feature
1. Read `references/design-system.md` for tokens + the component catalog, and
   check the Figma for any existing frame/component that already covers it.
2. Compose from **existing patterns** first (the header, list-item, primary CTA,
   pill, alert, card patterns already exist — reuse them). Only invent when
   there's no precedent, and keep it in-language.
3. For anything substantial, produce a quick visual first — either an
   `artifact-design` mockup or, to keep it in the team's tool, seed it into Figma
   via the Figma tools — before writing Svelte.
4. Build with the real tokens; verify contrast on the dark ground.

## Don't
- Don't introduce new colors, fonts, or radii that aren't in the token set /
  Figma without calling it out and getting a nod — consistency is the whole point.
- Don't design light-theme surfaces; this app is dark.
- Don't ship a native form control on a dark input without checking its icons are
  visible (`color-scheme: dark`) — this is the single most common dark-theme bug.

See `references/design-system.md` (tokens + component catalog) and
`references/review-checklist.md` (the audit).
