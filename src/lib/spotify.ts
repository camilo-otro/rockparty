// Tidy Spotify track titles for the catalog (#83 follow-up).
// The rules key off the *version qualifier* — the trailing "(…)" or " - …" that
// Spotify appends — never the base title, so "Live and Let Die" / "Alive" are
// safe while "Song (Live)" / "… - Remix" are caught.

// Versions to keep OUT of results entirely. The version tag follows the track's
// own language (not the user's locale), so cover common languages; "remix" is a
// loanword used across locales. Extend as needed.
//   live: EN "live", ES "en vivo"/"en directo", PT "ao vivo", IT "dal vivo"
const UNWANTED_QUALIFIER =
  /(\(|\s-\s)[^)]*\b(remix|live|en\s+vivo|en\s+directo|ao\s+vivo|dal\s+vivo)\b/i;

// Trailing qualifiers to strip from a kept title. remaster: EN "remaster(ed)",
// ES "remasterizado/a", FR "remasterisé"; plus mono/stereo.
const REMASTER_KEYWORDS = String.raw`remaster(ed)?|remasterizad[oa]|remasteris[eé]|mono|stereo`;
const REMASTER_PAREN = new RegExp(String.raw`\s*\([^)]*\b(${REMASTER_KEYWORDS})\b[^)]*\)\s*$`, 'i');
const REMASTER_DASH = new RegExp(String.raw`\s*-\s*[^-(]*\b(${REMASTER_KEYWORDS})\b[^-(]*$`, 'i');

/** True if the track is a remix/live version we don't want in results. */
export function isUnwantedVersion(title: string): boolean {
  return UNWANTED_QUALIFIER.test(title ?? '');
}

/** Strip trailing remaster/mono/stereo qualifiers; never returns empty. */
export function cleanSongTitle(title: string): string {
  const cleaned = (title ?? '')
    .replace(REMASTER_PAREN, '')
    .replace(REMASTER_DASH, '')
    .trim();
  return cleaned || (title ?? '').trim();
}

/** Filter unwanted versions out of Spotify results and clean the kept titles. */
export function tidySpotifyResults<T extends { title: string }>(results: T[]): T[] {
  return (results ?? [])
    .filter((r) => !isUnwantedVersion(r.title))
    .map((r) => ({ ...r, title: cleanSongTitle(r.title) }));
}
