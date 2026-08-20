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

## Authoritative sources (in order)
1. **Figma — the source of truth for visual design.**
   `https://www.figma.com/design/CYgSEvo4PG1d5gLaeIFscC/Rock-party`
   fileKey: `CYgSEvo4PG1d5gLaeIFscC`
   Pull from it with the Figma MCP tools before designing or reviewing:
   - `get_metadata(fileKey)` → list frames/components (screens: Home, Próximos
     toques, Toque detail, Canción detail; components: Toque, Cancion,
     Instrumentos, Spots, Musicos, Logo).
   - `get_screenshot(fileKey, nodeId)` → see a frame (download the URL, view it).
   - `get_design_context(fileKey, nodeId)` → exact colors/type/spacing for a node
     (load the figma-design-to-code guidance first, as that tool requires).
   If a screen exists in Figma, match it. If it doesn't (e.g. party status
   badges), design it *in this language* and note it's net-new.
2. **The implemented tokens** — `tailwind.config.ts` (colors, type scale, weights)
   and `src/app.css` (base styles). These are the real values to build with; see
   `references/design-system.md`.

## Project constraints that shape design (from CLAUDE.md)
- **Dark theme only** — `base-950` page, `base-900` surfaces. Design for dark.
- **Mobile-first** — the Figma frames are 393px wide. Design at phone width; scale up.
- **Spanish copy** — labels and messages in Spanish, matching the app's voice.
- **Free-tier-first** — media is external links or small free-tier uploads; don't
  design flows that assume heavy hosted assets.

## Two modes

### A. Reviewing (audit an existing screen or the whole app)
Work through `references/review-checklist.md`. The short version:
1. Screenshot the built screen (run the dev server, or read the component) **and**
   the corresponding Figma frame. Put them side by side.
2. Grade against the checklist — contrast/legibility first (it catches the most),
   then token fidelity, component consistency, state coverage, spacing, copy.
3. Report findings **prioritized** (blocking legibility bugs → visible
   inconsistencies → polish), each with the specific fix and token to use. Offer
   to file the larger ones as GitHub issues and to apply the quick ones.

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
