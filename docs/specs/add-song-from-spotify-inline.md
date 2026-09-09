# Adding a song from Spotify without leaving the setlist

**Status:** specced, not started · **Extends:** #80 / #83
(`docs/specs/song-import-spotify.md`)

## The problem

Adding a song that is not yet in the catalogue makes you leave the page you are
working on, and then makes you do the same search twice.

The flow today, from `/performance/create?partyId=X`:

1. Type the song. `search_songs` finds nothing.
2. Tap "¿No encuentras tu canción? **Agrégala aquí**" →
   `/songs/create?from=performance&partyId=X`.
3. Type the song **again**. Now it searches Spotify.
4. Tap the track. It is inserted into `song`, then `continueFlow()` waits 500ms
   and `goto`s back to `/performance/create?partyId=X`.
5. You land on a **fresh page with an empty search box**. The song you just added
   is *not* on the setlist.
6. Type the song a **third time**, and tap it to actually add the performance.

Three searches and a page round trip to put one song on a setlist. The catalogue
has ~6.5k songs so most searches hit locally, but the long tail is exactly when
someone is adding something new — the moment the app is most annoying is the
moment it matters.

## Why this is small

Almost everything needed already exists:

| Piece | State |
|---|---|
| Spotify **search** (`{ q }` → tracks) | **Already deployed** in the `spotify-track` edge function (#83). No backend work. |
| `tidySpotifyResults` (drops remix/live, strips remaster tags) | Already extracted to `$lib/spotify`. |
| Insert-or-reuse by Spotify link | Already written in `songs/create`; `song.ref_link` carries a UNIQUE constraint (`song_ref_link_key`), so the DB enforces dedupe and 23505 is already handled. |
| Adding a performance in one tap | Already how a local result behaves (`addSong`). |

So this is a client-side composition job: run the Spotify search in place, and on
tap resolve a `song.id` then feed it into the `addSong` path that already exists.

## The flow it becomes

1. Type the song once.
2. Tap it — from either group.
3. It is on the setlist.

## When Spotify results appear

**Zero local results → search Spotify automatically.** No threshold to tune and
no wasted invocation: when the catalogue has nothing, searching Spotify is the
only useful thing left to do, and it is precisely the "I can't find my song"
moment.

**Local results exist → do not search automatically**, but offer it. The line
that currently reads "¿No encuentras tu canción? Agrégala aquí" becomes an
in-place trigger — *"¿No está? Búscala en Spotify"* — which runs the same search
and expands a second group without leaving the page.

This keeps edge-function invocations proportional to actual need. Supabase's free
tier allows 500k/month and the search is debounced at 300ms with a latest-wins
guard (copy `runSearch` from `songs/create`), so cost is not a real constraint —
but firing a network call on every keystroke for a search that will usually
succeed locally is still waste worth avoiding.

Render Spotify hits as a **clearly separate group** ("En Spotify"), never mixed
into local results: tapping one has a side effect — it adds a song to the
catalogue for everyone — and the UI should not hide that.

## Attribution is a requirement, not a nicety

Spotify's Developer Terms require attributing metadata with the Spotify Marks and
a link back. `songs/create` already does this (the logo from
`static/images/spotify-logo.svg` plus "Metadatos de Spotify", and the track's
Spotify URL stored as `song.ref_link`). **The inline group must carry the same
attribution** — same logo, same wording, and the same `ref_link` write. Reuse the
markup rather than re-deriving it.

## Tapping a Spotify result

One new function; everything after it is the existing path.

```
resolveSongId(track) -> song.id
  if track.ref_link:
      select id from song where ref_link = <link>      -- reuse
  insert into song (title, artist, ref_link, added_by, duration?) returning id
  on 23505 (someone inserted the same link concurrently):
      re-select by ref_link and use that id
```

Then hand the id to the existing `addSong` logic so a Spotify pick behaves
exactly like a local one.

Three details that fall out of reusing that path, all of which the current
round-trip flow gets wrong or skips:

- **`song.duration` is decimal MINUTES**, the catalogue's convention, while the
  edge function returns seconds. `songs/create` already handles this; do not
  re-introduce the bug by copying the raw value.
- **A reused song can already be on the setlist.** Resolving by `ref_link` may
  return a song that is already there under a different search term, so run the
  same duplicate checks a local pick gets (`existing[songId]`, the `added`
  guard, the "Quedó N veces" toast) *after* the id is known, not before.
- **Band signup applies too.** If `signupChoice` is set, the new performance
  should get `sign_band_up` exactly as a local pick does.

## What happens to `/songs/create`

It stays — it is still the path from `/songs`, and still the only place to paste
a Spotify URL directly, which is a genuinely different input.

What goes is the **`?from=performance&partyId=` detour**: once the inline flow
exists, sending someone to another page and back is strictly worse. Remove that
link from `performance/create`, and with it the `continueFlow()` branch that
returns there.

## Out of scope

- **Paste-a-URL inline.** The `{ url }` mode exists and could be added later, but
  typing a name is what people do on a phone; a pasted link is the desktop case
  that `/songs/create` already serves.
- **Album art.** #81 wants `art_url` on `song`; the edge function already returns
  images. Worth doing, but it is a schema change and belongs to that issue.
- **Changing `search_songs`.** The local ranked search is fine; this only adds a
  second source when it comes back empty.

## Worth deciding before building

1. **Should a Spotify pick be added silently, or confirmed?** Tapping adds a row
   to the shared `song` catalogue that everyone will see afterwards. The spec
   above assumes silent (one tap, matching a local pick) because a confirm step
   re-introduces friction this feature exists to remove — but "you are adding
   this to the app for everyone" is a real side effect, and a subtler signal (a
   distinct group heading and a toast that says the song was added) may or may
   not be enough.
2. **How many Spotify results?** `songs/create` shows what the function returns
   after tidying. On the setlist page, a long second list pushes the "Agregadas"
   section off-screen. Cap at ~5?
