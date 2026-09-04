# Song import via Spotify link — spec

Status: **draft spec** (approved: Option B, Spotify Edge Function). Replaces the
flaky MusicBrainz autocomplete on `/songs/create`.

## Goal
Adding a song becomes: **find it on Spotify → paste the link → confirm**. The app
extracts title + artist (+ duration, album art) from the Spotify Web API. The link
is the quality gate — no more free-typed junk, natural dedup on the stored link.

## Why an Edge Function (recap)
Spotify's public oEmbed (client-side, no key) gives **title + album art but not the
artist**; every endpoint that returns the artist needs an API token, and the token
needs a **client secret that must not ship to the browser**. So a small Supabase
Edge Function holds the secret, calls the Web API, and returns clean metadata. It's
the app's first server-side component — contained, read-only, free-tier.

## Spotify compliance (verified 2026-09; Developer Terms + Policy)
Build these in from day one:
- **Endpoint:** `GET https://api.spotify.com/v1/tracks/{id}` via the **Client
  Credentials** flow — confirmed *not* among the Nov-2024 deprecations (those were
  audio-features / audio-analysis / recommendations / related-artists / featured
  playlists — none used here).
- **Storing metadata is allowed** (title, artist, track link, art — non-personal
  data). No fixed cache-duration limit stated.
- **Attribution is mandatory.** *"If you display any Spotify Content you must
  clearly attribute the content as being supplied and made available by Spotify,
  by using the Spotify Marks"* and *"Metadata, cover art… must be accompanied by a
  link back to the applicable… content on the Spotify Service."* →
  - Show the **Spotify logo/mark + "Metadatos de Spotify"** on the add-song confirm
    card and wherever Spotify-sourced data is first surfaced.
  - The song stores the **Spotify URL as `ref_link`** = the required link-back; the
    performance detail already renders "Escuchar en Spotify" (keep it).
  - Use the **official Spotify logo asset** unmodified (from Spotify's design
    resources); do not recolor or alter it.
- **Prohibited (all N/A but note):** no using Spotify content to train ML/AI; not a
  standalone metadata/art catalog; not replicating Spotify's core experience. Our
  use (setlist metadata) is fine — do not present the song list as a music catalog.
- **App mode / limits:** keep the Spotify app in **Development mode** — Client
  Credentials catalog calls have no 25-user limit (that's for user-auth flows), and
  volume is low (song adds). Request **Extended Quota Mode** only if usage grows;
  we'll already meet its attribution/branding review since it's built in.
- **Secret** lives only as an Edge Function secret — never in client code or a
  `PUBLIC_` var.

## Architecture

```
client (/songs/create)
  └─ supabase.functions.invoke('spotify-track', { body: { url } })   [user JWT]
        └─ Edge Function `spotify-track`
             ├─ parse track id from url (open.spotify.com/track/{id}, spotify:track:{id}, ?si=…)
             ├─ client-credentials token (cached in-memory ~3500s)
             ├─ GET /v1/tracks/{id}
             └─ → { title, artist, artists[], album, art_url, duration_s, spotify_url, isrc }
  └─ dedup: find existing song by ref_link (unique) → reuse if present
  └─ insert song { title, artist, ref_link: spotify_url, duration } (added_by)
```

### Edge Function `supabase/functions/spotify-track/index.ts`
- **Auth:** `verify_jwt = true` — only logged-in users invoke it (adding songs
  already requires auth; mild abuse control). `supabase-js` sends the user JWT
  automatically.
- **CORS:** return the standard CORS headers + handle the `OPTIONS` preflight.
- **Input:** `{ url: string }` (a Spotify track URL or `spotify:track:` URI). Reject
  anything that isn't a track link with a clear error.
- **Token cache:** module-scoped `{ token, expiresAt }`; refresh via
  `POST https://accounts.spotify.com/api/token` (`grant_type=client_credentials`,
  Basic auth = base64(`client_id:client_secret`)). Reuse until ~100s before expiry.
- **Fetch:** `GET https://api.spotify.com/v1/tracks/{id}` with `Bearer`.
- **Return** (200): `{ title: name, artist: artists.map(a=>a.name).join(', '),
  artists, album: album.name, art_url: album.images[0]?.url,
  duration_s: Math.round(duration_ms/1000), spotify_url: external_urls.spotify,
  isrc: external_ids?.isrc }`. On a bad/unknown id → 404 with a friendly message;
  pass through Spotify 429 (rate limit) so the client can say "intenta de nuevo".
- **Secrets:** `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`.

### Client — rework `/songs/create`
- Remove the two `AutocompleteInput` (MusicBrainz) fields.
- **Primary flow:**
  1. CTA **"Buscar en Spotify"** → opens `https://open.spotify.com/search` in a new
     tab (helps the user find the track).
  2. **"Pega el enlace de Spotify"** input. On paste/submit → invoke the function.
  3. **Confirm card:** album art + title + artist + **Spotify attribution** (logo +
     "Metadatos de Spotify"). Button: "Agregar al setlist" / "Crear canción".
  4. **Dedup:** normalize the URL, look up `song` by `ref_link`; if found, reuse
     that song (no dup — return it to the caller). The `ref_link` + `(title,artist)`
     unique constraints are the backstop.
  5. Insert `{ title, artist, ref_link: spotify_url, duration: duration_s }` and
     continue the existing `from=performance` / `partyId` return flow.
- **Manual fallback (decision — recommend keep, de-emphasized):** a collapsed
  "¿No está en Spotify? Agrégala manualmente" revealing plain title/artist inputs
  (no autocomplete). Covers the long tail (local/obscure songs). Drop it if stricter
  quality control is preferred — flagged for the owner.

## Data model
No schema change required — `song` already has `title`, `artist`, `ref_link`
(unique), `duration`. **Optional additions (nice-to-have, own decision):**
- `art_url text` — store album art to show a thumbnail on setlists (attribution +
  link-back already covered by `ref_link`).
- `isrc text` — stable cross-service id; enables adding other services later
  (match by ISRC) without dupes.

## Setup (one-time, owner)
1. Create a Spotify app at `developer.spotify.com/dashboard`; accept the Developer
   Terms. Copy `Client ID` + `Client Secret`.
2. `supabase secrets set SPOTIFY_CLIENT_ID=… SPOTIFY_CLIENT_SECRET=…`.
3. `supabase functions deploy spotify-track` (Supabase CLI linked to the project).

## Out of scope / later
- **Other services** (YouTube / Apple / Deezer). Deezer has a no-auth API with full
  metadata and could be a client-only complement; match across services by ISRC.
- **Album art on setlists** (needs `art_url`).
- Migrating the **rehearsal page** off MusicBrainz (it still imports
  `$lib/musicbrainz.ts`); this ticket only reworks `/songs/create`.
- **Paste-a-whole-setlist** (multiple links at once) — pairs with #77 multi-add.
