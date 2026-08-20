# Rock the House — design system

Exact values from `tailwind.config.ts` / `src/app.css`, plus the patterns seen in
the Figma file. Figma is authoritative for anything not captured here — pull the
specific frame with `get_design_context` when you need precise per-component values.

## Color tokens
| Token | Hex | Role |
|---|---|---|
| `base-950` | `#1A1A1A` | page background |
| `base-900` | `#262626` | cards / surfaces / list rows |
| `cold-base` | `#6C04FF` | **primary** — full-width CTAs, brand purple, pills |
| `cold-light` | `#A395FF` | links, secondary accents, muted counts ("5 TOQUES") |
| `warm-base` | `#FF4000` | orange — end of the brand gradient; "live/now" emphasis |
| `yellow` | `#FFAE00` | highlight — chevrons, entity titles, warning/attention |
| `mid` | `#71118E` | gradient midpoint (purple→orange wordmark) |
| white | `#FFFFFF` | primary text on dark |

The brand wordmark is a **purple→orange gradient** ("ROCK the HOUSE"). Reuse that
gradient (`cold-base → mid → warm-base`) sparingly for hero/brand moments only.

Semantic (not brand) colors — keep separate from the accent palette:
- success/positive: a green outside the palette; use sparingly.
- danger/cancel: red (e.g. `red-600`) for destructive/cancelled states.

## Typography
- Family: **Roboto Condensed** (`font-sans`), loaded in `app.css`. Fallback `system-ui`.
- Weights are remapped: `normal` = 200, `medium` = 400, `bold` = 600. Body and
  headings default to **300** (light) — the app's signature is light-weight,
  condensed type.
- Headings: **UPPERCASE**, large, light weight, a touch of letter-spacing
  (e.g. section titles "PRÓXIMOS TOQUES", "SETLIST", "MÚSICOS").
- Scale (`fontSize`): xs .75 / sm .875 / base 1 / lg 1.125 / xl 1.25 / 2xl 1.5 /
  3xl 1.875 / 4xl 2.25 / 5xl 3 (rem).

## Layout
- Mobile-first, ~393px content width, generous vertical rhythm.
- Cards/rows: `base-900` on `base-950`, `rounded-lg`, thin `space-y-[1px]` gaps
  between rows in a list (the 1px gap shows the darker ground as a divider).

## Component catalog (from Figma — reuse these)
- **Header**: gradient logo left; right side is an "Ingresar" purple pill (logged
  out) or a circular avatar (logged in).
- **Primary CTA**: full-width `cold-base` button, white text, rounded, often with a
  trailing icon (`Crea un nuevo toque +`, `Sugerir una canción +`, `Invitar músicos`).
- **List row — Toque**: entity title (large), date/time, location with a pin icon,
  a **yellow chevron** on the right; a small purple **"BUSCANDO MÚSICOS"** pill when
  the toque still needs players.
- **List row — Venue**: name, area/neighborhood, right-aligned `cold-light` count
  ("5 TOQUES").
- **Toque detail**: uppercase title; "Organizado por" + avatar + name (link);
  description; date/time; location line; a **row of two primary CTAs** (Invitar
  músicos / Compartir evento); a **SETLIST** heading with a filter icon; an
  **alert row** with a warning glyph ("⚠ 5 canciones buscan músicos! Filtrar");
  numbered setlist rows (big index, song title, artist, instrument-icon cluster);
  "Duración estimada"; then a **MÚSICOS** list (avatar, name, "Voz · Bajo",
  count).
- **Instrumentos** component — has state variants `Buscando` (open slot),
  `Opcional`, `Yo` (this is me). Use these for the gaps-to-fill / signup UI.
- **Spots** component — `Estado = Full | Mid | Empty`. The capacity indicator for a
  song's needed roles (ties to the gaps-to-fill / oversubscription spec).
- **Pill/badge**: small, uppercase, rounded-full, purple for informational
  ("BUSCANDO MÚSICOS"); pick semantic colors for status (see party status below).
- **Avatar**: circular, thin ring.

## Dark-theme form controls (important)
`app.css` styles `input, textarea, select` as `bg-base-950 text-white`. Native
controls (date pickers, selects) then render their **icons dark on a dark field →
invisible**. Always set **`color-scheme: dark`** on such inputs so the browser
draws native affordances light. This is the #1 dark-theme trap here.

## Party status (net-new — not in Figma yet)
Statuses: `draft · pending_venue · confirmed · live · completed · cancelled`.
Render as a pill using the existing pill pattern (`StatusBadge.svelte`). Suggested
mapping until the Figma catches up: draft = neutral outline; pending_venue =
`yellow`; confirmed = `cold-base`; live = `warm-base`; completed = muted `base-900`;
cancelled = red. Flag for a proper Figma treatment when convenient.
