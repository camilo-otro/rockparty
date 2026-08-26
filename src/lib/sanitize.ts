// Non-destructive input normalization for user-entered text.
//
// It ONLY trims surrounding whitespace, strips control characters that are never
// meaningful in these fields (null bytes, etc.—tab and newline are kept so
// multi-line descriptions survive), and caps length. It deliberately does NOT
// strip quotes, angle brackets, "script", or SQL keywords:
//
//   - SQL injection isn't reachable here — the Supabase/PostgREST client sends
//     values as parameterized JSON, never concatenated into SQL.
//   - Svelte auto-escapes every `{...}` interpolation and the app uses no
//     `{@html}`, so stored text can't execute as markup.
//
// Stripping those characters would corrupt legitimate names, song titles, and
// descriptions (apostrophes, "and"/"or", "script", …) for zero security gain.
// If `{@html}` is ever introduced, sanitize with a real HTML sanitizer at that
// render site — not here at the input.

/** Trim, remove control chars (keeping tab/newline), and cap length. */
export function normalizeText(input: unknown, maxLength = 500): string {
  if (typeof input !== 'string') return '';
  // Drop C0 control chars and DEL; keep tab (9), newline (10), and everything
  // printable (>= 32, excluding 127) so accents/emoji/quotes all survive.
  let out = '';
  for (const ch of input) {
    const code = ch.codePointAt(0) ?? 0;
    if (code === 9 || code === 10 || (code >= 32 && code !== 127)) out += ch;
  }
  return out.trim().slice(0, maxLength);
}
