import { uploadAvatar, deleteAvatarByUrl } from './avatarStorage';

// Band avatars (#75). A cropped 512x512 WebP in the public `band-avatars`
// bucket at {band_id}/{timestamp}.webp.
//
// The mechanics moved to avatarStorage.ts when profiles grew the same feature
// (#96); this stays as the band-flavoured entry point so call sites are
// unchanged and the bucket name is stated once.
const BUCKET = 'band-avatars';

export const uploadBandAvatar = (bandId: number, blob: Blob, oldUrl?: string | null) =>
  uploadAvatar(BUCKET, bandId, blob, oldUrl);

export const deleteBandAvatarByUrl = (url: string) => deleteAvatarByUrl(BUCKET, url);
