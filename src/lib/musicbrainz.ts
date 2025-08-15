// Utility for fetching recording titles from MusicBrainz

export async function fetchSongTitles(title: string) {
  const baseUrl = 'https://musicbrainz.org/ws/2/recording/';
  const params = new URLSearchParams({
    query: `recording:"${title}"`,
    fmt: 'json',
    limit: '10'
  });
  const url = `${baseUrl}?${params.toString()}`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'RockPartyWebApp/Beta (camilootro@gmail.com)'
    }
  });
  if (!res.ok) throw new Error('MusicBrainz request failed');
  const data = await res.json();
  const titles = (data.recordings ?? []).map((rec: any) => rec.title);
  // Remove duplicates
  return Array.from(new Set(titles));
}

export async function fetchArtistNames(artist: string) {
  const baseUrl = 'https://musicbrainz.org/ws/2/artist/';
  const params = new URLSearchParams({
    query: `artist:"${artist}"`,
    fmt: 'json',
    limit: '10'
  });
  const url = `${baseUrl}?${params.toString()}`;
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'RockPartyWebApp/Beta (camilootro@gmail.com)'
    }
  });
  if (!res.ok) throw new Error('MusicBrainz request failed');
  const data = await res.json();
  const names = (data.artists ?? []).map((a: any) => a.name);
  // Remove duplicates
  return Array.from(new Set(names));
}
