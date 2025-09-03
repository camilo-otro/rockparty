// Utility for fetching recording titles from MusicBrainz

function normalizeAndSortResults(results: string[], search: string): string[] {
  const cleaned = results.map(r => r.trim().replace(/["'.:,;!?-]/g, ''));
  // Count repetitions
  const freqMap: Record<string, number> = {};
  cleaned.forEach(r => {
    const key = r.toLowerCase();
    freqMap[key] = (freqMap[key] || 0) + 1;
  });
  // Remove duplicates and sort by frequency
  const unique = Array.from(new Set(cleaned.map(r => r.toLowerCase())));
  const normalized = unique.sort((a, b) => freqMap[b] - freqMap[a]);
  const lowerSearch = search.toLowerCase().replace(/["'.:,;!?-]/g, '').trim();
  const startsWith = normalized.filter(r => r.startsWith(lowerSearch));
  const includes = normalized.filter(r => !r.startsWith(lowerSearch) && r.includes(lowerSearch));
  const rest = normalized.filter(r => !r.startsWith(lowerSearch) && !r.includes(lowerSearch)).sort((a, b) => a.localeCompare(b));
  return [...startsWith, ...includes, ...rest].slice(0, 15);
}

export async function fetchSongTitles(title: string) {
  const baseUrl = 'https://musicbrainz.org/ws/2/recording/';
  const params = new URLSearchParams({
    query: `recording:${title}`,
    fmt: 'json',
    limit: '100'
  });
  const url = `${baseUrl}?${params.toString()}`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'RockPartyWebApp/Beta (camilootro@gmail.com)'
    }
  });
  if (res.status !== 200 && res.status !== 304) throw new Error('MusicBrainz request failed');
  const data = await res.json();
  type Recording = { title: string };
  const titles = (data.recordings ?? []).map((rec: Recording) => rec.title);
  return normalizeAndSortResults(titles, title);
}

export async function fetchArtistNames(artist: string) {
  const baseUrl = 'https://musicbrainz.org/ws/2/artist/';
  const params = new URLSearchParams({
    query: `artist:${artist}`,
    fmt: 'json',
    limit: '100'
  });
  const url = `${baseUrl}?${params.toString()}`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'RockPartyWebApp/Beta (camilootro@gmail.com)'
    }
  });
  if (res.status !== 200 && res.status !== 304) throw new Error('MusicBrainz request failed');
  const data = await res.json();
  type Artist = { name: string };
  const names = (data.artists ?? []).map((a: Artist) => a.name);
  return normalizeAndSortResults(names, artist);
}
