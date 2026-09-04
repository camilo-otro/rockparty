// Edge Function: spotify-track (#80)
// Resolves a Spotify track link to clean metadata (title, artist, art, duration)
// via the Web API Client-Credentials flow. Holds the Spotify secret server-side
// (never shipped to the browser). GET /v1/tracks/{id} is not among the Nov-2024
// deprecations. See docs/specs/song-import-spotify.md.
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  let url = '';
  try { url = (await req.json())?.url ?? ''; } catch { /* handled below */ }

  const id = parseTrackId(url);
  if (!id) return json({ error: 'invalid_link', message: 'Pega un enlace de canción de Spotify.' }, 400);

  try {
    const token = await getToken();
    const res = await fetch(`https://api.spotify.com/v1/tracks/${id}`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (res.status === 404) return json({ error: 'not_found', message: 'No se encontró esa canción en Spotify.' }, 404);
    if (res.status === 429) return json({ error: 'rate_limited', message: 'Spotify está ocupado, intenta de nuevo.' }, 429);
    if (!res.ok) return json({ error: 'spotify_error' }, 502);

    const t = await res.json();
    return json({
      title: t.name ?? '',
      artist: (t.artists ?? []).map((a: any) => a.name).filter(Boolean).join(', '),
      artists: (t.artists ?? []).map((a: any) => a.name),
      album: t.album?.name ?? null,
      art_url: t.album?.images?.[0]?.url ?? null,
      duration_s: t.duration_ms ? Math.round(t.duration_ms / 1000) : null,
      spotify_url: t.external_urls?.spotify ?? `https://open.spotify.com/track/${id}`,
      isrc: t.external_ids?.isrc ?? null
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'unknown';
    return json({ error: 'lookup_failed', detail: msg }, 500);
  }
});
