import { uploadAvatar, deleteAvatarByUrl } from './avatarStorage';

// Profile avatars (#96). Same shape as bands: a cropped 512x512 WebP in the
// public `profile-avatars` bucket at {user_id}/{timestamp}.webp.
//
// Note `profile.avatar_url` holds one of TWO things — a Google CDN URL (the
// signup default, and what removing a photo falls back to) or a URL in this
// bucket. Passing a Google URL as `oldUrl` is safe: objectPathFromUrl returns
// null for anything outside the bucket, so nothing is deleted.
const BUCKET = 'profile-avatars';

export const uploadProfileAvatar = (userId: string, blob: Blob, oldUrl?: string | null) =>
  uploadAvatar(BUCKET, userId, blob, oldUrl);

export const deleteProfileAvatarByUrl = (url: string) => deleteAvatarByUrl(BUCKET, url);
