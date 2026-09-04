// Edge Function: spotify-track (#80, #83)
// A tiny Spotify Web API proxy via the Client-Credentials flow, holding the
// secret server-side (never shipped to the browser). Two modes:
//   { q }   → search tracks (GET /v1/search)  → { results: [...] }   (#83)
//   { url } → resolve one track (GET /v1/tracks/{id}) → the track metadata (#80)
// Neither endpoint is among the Nov-2024 deprecations. See
// docs/specs/song-import-spotify.md.
//
// Secrets: SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET
// Deployed with verify_jwt=true (default) — only signed-in users may call it.

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// Extract a Spotify track id from any of: an open.spotify.com/track/{id}[?si=…]
// URL (with optional locale prefix), a spotify:track:{id} URI, or a bare id.
function parseTrackId(input: string): string | null {
  const s = (input ?? '').trim();
  if (!s) return null;
  const uri = s.match(/^spotify:track:([A-Za-z0-9]{22})$/);
  if (uri) return uri[1];
  const url = s.match(/open\.spotify\.com\/(?:[a-z-]+\/)?track\/([A-Za-z0-9]{22})/);
  if (url) return url[1];
  if (/^[A-Za-z0-9]{22}$/.test(s)) return s; // bare id
  return null;
}

// Cache the app token across invocations of a warm instance.
let cached: { token: string; expiresAt: number } | null = null;

async function getToken(): Promise<string> {
  if (cached && Date.now() < cached.expiresAt - 100_000) return cached.token;
  const id = Deno.env.get('SPOTIFY_CLIENT_ID');
  const secret = Deno.env.get('SPOTIFY_CLIENT_SECRET');
  if (!id || !secret) throw new Error('missing_spotify_credentials');
  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${btoa(`${id}:${secret}`)}`,
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: 'grant_type=client_credentials'
  });
  if (!res.ok) throw new Error('spotify_token_failed');
  const data = await res.json();
  cached = { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
  return cached.token;
}

// Map a Spotify track object to our clean shape. `small` picks the smallest
// album image (list thumbnails); otherwise the largest.
function trackMeta(t: any, small = false) {
  const imgs = t.album?.images ?? [];
  return {
    title: t.name ?? '',
    artist: (t.artists ?? []).map((a: any) => a.name).filter(Boolean).join(', '),
    artists: (t.artists ?? []).map((a: any) => a.name),
    album: t.album?.name ?? null,
    art_url: (small ? imgs[imgs.length - 1]?.url : imgs[0]?.url) ?? imgs[0]?.url ?? null,
    duration_s: t.duration_ms ? Math.round(t.duration_ms / 1000) : null,
    spotify_url: t.external_urls?.spotify ?? (t.id ? `https://open.spotify.com/track/${t.id}` : null),
    isrc: t.external_ids?.isrc ?? null
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  let body: any = {};
  try { body = await req.json(); } catch { /* handled below */ }
  const q = (body?.q ?? '').trim();
  const url = body?.url ?? '';

  try {
    const token = await getToken();

    // Search mode (#83): { q } → a list of tracks.
    if (q) {
      const res = await fetch(
        `https://api.spotify.com/v1/search?type=track&limit=8&q=${encodeURIComponent(q)}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      if (res.status === 429) return json({ error: 'rate_limited', message: 'Spotify está ocupado, intenta de nuevo.' }, 429);
      if (!res.ok) return json({ error: 'spotify_error' }, 502);
      const data = await res.json();
      return json({ results: (data.tracks?.items ?? []).map((t: any) => trackMeta(t, true)) });
    }

    // Resolve mode (#80): { url } → one track.
    const id = parseTrackId(url);
    if (!id) return json({ error: 'invalid_link', message: 'Busca una canción o pega un enlace de Spotify.' }, 400);
    const res = await fetch(`https://api.spotify.com/v1/tracks/${id}`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (res.status === 404) return json({ error: 'not_found', message: 'No se encontró esa canción en Spotify.' }, 404);
    if (res.status === 429) return json({ error: 'rate_limited', message: 'Spotify está ocupado, intenta de nuevo.' }, 429);
    if (!res.ok) return json({ error: 'spotify_error' }, 502);
    return json(trackMeta(await res.json()));
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'unknown';
    return json({ error: 'lookup_failed', detail: msg }, 500);
  }
});
