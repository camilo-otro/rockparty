# Design review checklist

Work top-down: legibility bugs first (they hurt most and are cheapest), then
fidelity to the Figma, then consistency, then polish. For each finding, name the
**specific fix and token**, and mark severity: 🔴 blocking · 🟠 visible · 🟡 polish.

Always compare the built screen against its Figma frame side by side (screenshot
both). If a screen has no Figma frame, review it against the patterns in
`design-system.md` and flag that a Figma frame is missing.

## 1. Legibility & contrast (🔴 first)
- Text meets contrast on the dark ground (white / `cold-light` on `base-950/900`
  is fine; avoid mid-grays that muddy).
- **Native control icons visible** — date/time pickers, selects on dark inputs
  need `color-scheme: dark`. (Recurring bug.)
- Icons/glyphs have enough contrast; not black-on-dark.
- Tap targets ≥ ~44px; interactive things look interactive; visible focus state.

## 2. Consistency with the design language (NOT literal Figma fidelity)
The Figma can lag the built app; deliberate divergences are not bugs. Flag a
Figma difference only when it's a real problem or an inconsistency *within the
app* — never merely "doesn't match an old frame." Check:
- Colors map to the **tokens**, not one-off hexes.
- Type: Roboto Condensed, light weights, UPPERCASE section headings with
  letter-spacing; correct scale step.
- Spacing/radius consistent with the rest of the app (rounded-lg, 1px row gaps,
  card padding rhythm).
- Components reuse the shared **vocabulary** (header, CTA, list row, pill, alert,
  card) rather than a bespoke one-off.

## 3. Component & pattern consistency
- Reuses the shared patterns (header, primary CTA, list row, pill, alert, card)
  rather than a bespoke variant.
- Buttons: primary = full-width `cold-base`; destructive = red; consistent radius.
- Status/state shown with the pill pattern, consistent colors across screens.
- Entity titles, counts, links use their conventional token (title, `cold-light`
  count, link color).

## 4. State coverage
Every data view has: **loading**, **empty** (friendly Spanish copy, not a blank),
**error**, and where relevant **draft/pending/cancelled**. Signup/slot UIs show
open vs filled (`Instrumentos`/`Spots` components).

## 5. Copy (Spanish)
- Spanish, consistent voice; actions say what they do ("Publicar", "Cancelar
  toque"); errors explain + guide ("La fecha no puede ser en el pasado").
- Consistent terminology: *toque*, *local*, *intérprete/músico*, *setlist*.

## 6. Responsive
- Works at 393px; no horizontal scroll; scales up gracefully on wider screens.

## Output format
Group findings by screen. Lead with a one-line verdict per screen, then the
prioritized list. End with: quick wins to apply now, and larger items to file as
GitHub issues (Phase 1 "Doors" design polish, or a dedicated design pass).
