import { supabase } from './supabaseClient';

// Shared avatar storage for bands (#75) and profiles (#96).
//
// Both follow the same convention: a cropped 512x512 image at
// {owner}/{timestamp}.{ext} in a public bucket. Versioned names plus
// delete-on-replace keep exactly one avatar per owner and the CDN cache clean.
//
// WebP where the browser can encode it, JPEG where it cannot — the format is
// whatever the cropper managed to produce, not something this module decides.
//
// Factored out rather than copied because objectPathFromUrl is the fiddly part
// — it is what stops a delete from being attempted against a URL that does not
// belong to the bucket at all (a Google CDN avatar, notably). Two copies of that
// would drift.

const CACHE_CONTROL = '2592000'; // 30 days — safe, since names are versioned

// The formats the buckets accept. Keep this in step with each bucket's
// `allowed_mime_types`, or an upload the client thinks is fine is refused by
// the server with an English message.
const EXT_BY_TYPE: Record<string, string> = {
  'image/webp': 'webp',
  'image/jpeg': 'jpg'
};

/**
 * Upload a new avatar, return its public URL, and best-effort delete the old one.
 *
 * `oldUrl` is ignored unless it points inside this bucket, so passing a Google
 * avatar URL is safe and simply deletes nothing.
 */
export async function uploadAvatar(
  bucket: string,
  owner: string | number,
  blob: Blob,
  oldUrl?: string | null
): Promise<string> {
  // Follow the blob rather than assert a format. This used to hardcode
  // image/webp and a .webp name, so a browser that could not encode WebP (the
  // cropper's toBlob silently yields PNG — see AvatarCropper) uploaded a PNG
  // wearing a WebP label. The server sniffs the bytes, so it refused, and the
  // avatar could never be set on that browser.
  const type = blob.type || 'image/webp';
  const ext = EXT_BY_TYPE[type];
  if (!ext) throw new Error(`Formato de imagen no soportado: ${type}`);

  const path = `${owner}/${Date.now()}.${ext}`;
  const { error } = await supabase.storage.from(bucket).upload(path, blob, {
    contentType: type,
    cacheControl: CACHE_CONTROL,
    upsert: false
  });
  if (error) throw error;
  const { data } = supabase.storage.from(bucket).getPublicUrl(path);
  if (oldUrl) await deleteAvatarByUrl(bucket, oldUrl);
  return data.publicUrl;
}

/**
 * Delete an avatar object given its public URL. Best-effort — an orphaned object
 * is minor, and a URL from outside the bucket is a no-op rather than an error.
 */
export async function deleteAvatarByUrl(bucket: string, url: string): Promise<void> {
  const path = objectPathFromUrl(bucket, url);
  if (!path) return;
  await supabase.storage.from(bucket).remove([path]);
}

/**
 * Extract the object path ({owner}/{ts}.webp) from a public URL.
 *
 * Returns null for any URL that is not in this bucket — which is the guard that
 * makes a Google-hosted avatar safe to pass around as `oldUrl`.
 */
export function objectPathFromUrl(bucket: string, url: string): string | null {
  const marker = `/${bucket}/`;
  const i = url.indexOf(marker);
  if (i === -1) return null;
  return url.slice(i + marker.length).split('?')[0];
}
