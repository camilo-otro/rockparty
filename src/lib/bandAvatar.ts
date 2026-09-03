import { supabase } from './supabaseClient';

// Band avatars (#75): a cropped/optimized 512x512 WebP in the public
// `band-avatars` bucket at {band_id}/{timestamp}.webp. Versioned names +
// delete-on-replace keep each band at exactly one avatar and the CDN cache clean.
const BUCKET = 'band-avatars';
const CACHE_CONTROL = '2592000'; // 30 days — safe, names are versioned

// Upload a new avatar, return its public URL, and best-effort delete the old one.
export async function uploadBandAvatar(bandId: number, blob: Blob, oldUrl?: string | null): Promise<string> {
  const path = `${bandId}/${Date.now()}.webp`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, blob, {
    contentType: 'image/webp',
    cacheControl: CACHE_CONTROL,
    upsert: false
  });
  if (error) throw error;
  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
  if (oldUrl) await deleteBandAvatarByUrl(oldUrl);
  return data.publicUrl;
}

// Delete an avatar object given its public URL (best-effort; an orphan is minor).
export async function deleteBandAvatarByUrl(url: string): Promise<void> {
  const path = objectPathFromUrl(url);
  if (!path) return;
  await supabase.storage.from(BUCKET).remove([path]);
}

// Extract the object path ({band_id}/{ts}.webp) from a public URL.
function objectPathFromUrl(url: string): string | null {
  const marker = `/${BUCKET}/`;
  const i = url.indexOf(marker);
  if (i === -1) return null;
  return url.slice(i + marker.length).split('?')[0];
}
