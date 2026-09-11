# A shareable invitation to play one song

**Status:** specced, not started · **Issue:** #111 · **Extends:** #68 (flyer OG) / #77 (setlist signup)

## The problem

There is already a Share button on a song — `PerformanceDetail.handleShare()`
builds *"Te invito a tocar {canción} en Rock Party"* and shares
`window.location.href`, i.e. `/performance/[id]`.

That link previews as **nothing**. Measured against production:

| URL | What a crawler receives |
|---|---|
| `/flyer/25` | 11,908 bytes — `og:title`, `og:description`, 1200×630 `og:image` |
| `/performance/125` | **1,491 bytes — an empty shell. No title, no image, no description.** |
| `/parties/25` | same empty shell |

`/performance/[id]` has no `<svelte:head>` and the global `ssr = false` applies,
so a crawler gets the SPA skeleton. The `navigator.share` *text* may survive on
mobile, but the link itself arrives in a WhatsApp group as a bare URL.

So the recipient sees no song, no event, no date, no venue — and the page behind
it is auth-gated. The one link in the app whose entire job is recruiting a
musician is the one that says least.

## On "does an image make it safer to share"

Worth separating, because only half of this is about images.

**Reputation.** CLAUDE.md records that the domain was blocked on WhatsApp around
Oct–Nov 2025, when it was ~5 weeks old, with newly-registered-domain reputation
noted as the likely factor. It is now ~12 months old, which is the variable that
actually moved. WhatsApp's criteria are not published; **nobody can tell you an
image fixes a block, and this spec does not claim it.** What is defensible: a URL
that resolves to a real page with proper Open Graph metadata looks like an
ordinary web page to an automated classifier, and a 1.5 KB empty shell looks less
like one. Treat that as a reason not to ship bare links, not as a remedy.

**Conversion.** This is the concrete half and it is entirely in our control. A
preview that says *"Lobo Hombre En París — Serenata Rock, sáb 27 sep · falta
bajo"* is an invitation. A bare URL is homework.

## Shape: a public companion route, NOT SSR on the app page

The obvious move — switch `ssr = true` on `/performance/[id]` — is wrong, and
the reason is already documented in `+layout.js`:

> this load runs during SSR where there's no localStorage, so getSession()
> returns null and the app hydrates logged-out until the client restores the
> session (~1s flash of "Ingresar" / auth gates)

`/performance/[id]` is an **app** page, dense with auth-dependent UI — signup
buttons, instrument pickers, approve/decline for admins. SSR-ing it reintroduces
exactly the flash #48 removed, on a page people use constantly, to benefit
visitors who mostly are not logged in.

The precedent for the right answer already exists one level up: **`/flyer/[id]`
is the public, SSR'd companion to `/parties/[id]`.** This is the same
relationship one level down.

```
/parties/[id]        app page   ──public companion──▶  /flyer/[id]          SSR
/performance/[id]    app page   ──public companion──▶  /invite/[id]         SSR  ← new
```

English route name, per the "English code, Spanish UI" rule.

## What the page shows

Small, and built to answer one question: *should I say yes?*

- **The song** — title and artist, the largest thing on the page.
- **The toque** — title, date, venue.
- **What is still open** — the actual pull. "Falta bajo y batería" beats any
  amount of brand copy, and it is why this page exists rather than a redirect.
- **One CTA** — *"Inscríbete para tocar"* → `/performance/[id]`, which handles
  auth as it already does.
- The Spotify link when `song.ref_link` is set, and the brand footer, mirroring
  the flyer.

## Privacy: instruments, never names

The flyer deliberately publishes a musician **count**, never nicknames. Carry
that forward: this page shows which instruments are taken and which are open,
not who is playing.

That is both the safer choice and the more useful one — "falta bajo" is the
information a recipient needs; "Yorch is playing guitar" is a person-to-event
mapping published to anyone with a link, which is the thing #102 just finished
removing elsewhere.

## RLS already does the right thing — verified, not assumed

Everything the card needs comes back in **one** anon request, and the guard
holds. Tested against production with the anon key:

```
/performance?id=eq.33&select=id,song(title,artist),
             party(id,title,date,status,is_test,venue_ref:venue(name))

  perf 33  (Serenata Rock, confirmed, real) -> full row, song + party + venue
  perf 125 (Monster Mash,  is_test)         -> []
```

So a shared link to a song on a test, draft or `pending_venue` toque returns
nothing and the page falls back to the generic brand card — the same fallback
`/flyer/[id]` already relies on. Mirror its second guard too:
`publicPreview = !!row && !row.party.is_test`, belt and braces over RLS.

**No new data is exposed.** The flyer already publishes the song titles of a
public toque; this publishes a subset of the same facts, scoped to one song.

## Also change the Share button

`handleShare()` and `ShareModal` currently share `window.location.href`. They
should share `/invite/[id]`. The share *text* can then drop the explanation it is
currently carrying alone, since the preview will say it.

Note `handleShare` is reached from the party-page overlay too (#94), where
`window.location.href` is the *party* URL with shallow-routing state — so it must
build the invite URL from the performance id rather than reading the address bar.
That is a real bug the current code only avoids because the target has no preview
to get wrong.

## Out of scope

- **A per-song generated image.** `og:image` points at the existing 1200×630 card
  to start. #109 covers generated per-event cards; once that machinery exists a
  per-song variant is nearly free, and this spec should not block on it.
- **Making `/performance/[id]` public.** It stays the app page, auth and all.
- **Invitations to a specific person.** This is a link anyone can open, like the
  flyer. A targeted invite with a notification is a different feature.

## Worth deciding before building

1. **Does the invite page need its own layout, or reuse the flyer's?** They will
   look like siblings. Extracting a shared public-page shell is tempting and
   probably premature at two instances.
2. **What should it say when the song is already full?** Falling back to "ver el
   toque" and pointing at the flyer is probably right — the link stays useful
   instead of becoming a dead end.
3. **Should `/invite/[id]` 302 to `/performance/[id]` for a signed-in visitor?**
   It would save a tap for someone who already has an account. It also means the
   page a sharer sees is not the page their friend sees, which makes it hard to
   reason about what you just sent.
