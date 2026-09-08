# Profile avatar upload — reuse the band avatar machinery

**Status:** captured, not started · **Follows:** #75 (band avatar upload, shipped)

## What users get

Set your own profile picture instead of being stuck with whatever Google
supplied. Same crop-and-upload flow bands already have.

## What already exists

Most of this is built. #75 shipped a complete avatar pipeline for bands, and
almost none of it is band-specific:

| Piece | State | Reusable? |
|---|---|---|
| `AvatarCropper.svelte` | shipped | **As-is.** Props are `initialUrl` + `label`; it dispatches `crop {blob, previewUrl}`, `remove`, `error`. Nothing about bands in it beyond the default label. |
| `lib/bandAvatar.ts` | shipped | Nearly. Generic except a hardcoded `BUCKET` and a `bandId` argument. |
| Storage bucket pattern | shipped | Pattern reusable; needs a second bucket with its own ownership policy. |
| `profile.avatar_url` column | exists | Already there, already granted for client SELECT. |
| The 11 places that render a profile avatar | shipped | **Already read `profile.avatar_url`.** They pick up an upload for free. |

The cropper already produces a 512×512 WebP and the bucket caps at 256 KB with
`image/webp` only, so the free-tier storage question is settled: ~50 KB per
avatar against Supabase's 1 GB is not a constraint worth thinking about.

## What's actually missing

1. A `profile-avatars` bucket with a per-user ownership policy.
2. Generalising `bandAvatar.ts` so both callers share it.
3. UI in `PerformerForm` — today the avatar is literally
   `<input type="hidden" bind:value={avatarUrl} />`. It is carried through the
   form and never shown.
4. **The header fix.** See below; this is the part that would otherwise make the
   feature look broken.

## The header bug this has to fix

`src/routes/+layout.svelte:100` renders the nav avatar from
`session.user.user_metadata.avatar_url` — the **Google** photo, not
`profile.avatar_url`.

So without this fix: you upload a photo, every other surface in the app updates,
and the one in the top-right corner — the first place you would look to confirm
it worked — keeps showing the old Google one. It would read as a broken upload.

The cause is upstream in `src/routes/+layout.js`: it selects
`profile.select('id, role, nickname')` and, in the branch where the profile
exists, builds a `UserRecord` **without `avatarUrl` at all** — even though the
type declares it. The header has nothing to read, so it falls back to auth
metadata.

The fix is one column on a query that already runs:

```js
// +layout.js
.select('id, role, nickname, avatar_url')
...
userRecord = { id, email, role, nickname, avatarUrl: dbUser.avatar_url ?? session.user.user_metadata?.avatar_url ?? null };
```

then have the header read `$user.avatarUrl`. **No extra request** — one more
column on an existing round trip, which matters given #84.

## Design

### Bucket

A separate `profile-avatars` bucket, not a shared one. Ownership differs — a
band avatar is writable by any band manager, a profile avatar only by its owner —
and mixing two ownership models in one bucket's policies is how those policies
get subtly wrong.

```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('profile-avatars','profile-avatars', true, 262144, array['image/webp']);

-- public read
--   select using (bucket_id = 'profile-avatars')
-- owner writes: the folder IS the uid
--   insert with check (bucket_id = 'profile-avatars'
--                      and (storage.foldername(name))[1] = auth.uid()::text)
--   update / delete: same predicate
```

Path shape `{uid}/{timestamp}.webp`, mirroring bands' `{band_id}/{timestamp}.webp`.
Versioned names plus delete-on-replace keep one object per user and the CDN
cache honest — same reasoning as #75.

Note this predicate is *simpler* than the band one: `= auth.uid()::text` rather
than a `is_band_manager(...)` lookup. No cast to bigint, so no risk of the
folder-name cast blowing up on a non-numeric path.

### Generalising the helper

Rename `lib/bandAvatar.ts` → `lib/avatarStorage.ts` with the bucket and owner
folder as parameters:

```ts
uploadAvatar(bucket: string, ownerFolder: string, blob: Blob, oldUrl?: string | null): Promise<string>
deleteAvatarByUrl(bucket: string, url: string): Promise<void>
```

Keep thin `uploadBandAvatar` / `uploadProfileAvatar` wrappers so call sites stay
readable and the bucket name is named once per domain rather than at every call.

One behaviour worth keeping deliberately: `objectPathFromUrl` returns `null` for
a URL that isn't in the bucket, and the delete is a no-op. That is exactly right
for the common profile case — the "old URL" being replaced is usually a Google
CDN link, which we neither own nor should try to delete. The existing code
already handles this correctly; don't "fix" it.

### What "remove" means for a profile

Bands treat remove as "no avatar". Profiles are different: there is almost always
a Google photo sitting behind it.

**Remove should mean "go back to my Google photo"**, implemented by writing the
auth metadata URL back into `profile.avatar_url` — not by nulling the column.

Two reasons:

- All 11 render sites read `profile.avatar_url` directly. Nulling it would
  require every one of them to grow a fallback; keeping the column always
  populated means none of them change.
- It is the more honest label. The control should read **"Usar mi foto de
  Google"**, not "Quitar" — because "quitar" implies you end up with no picture,
  and you don't.

If the account has no Google photo, writing null is correct and the existing
`/images/avatar-default.svg` fallback handles it.

## Build order

1. Create the bucket + policies (Supabase dashboard / migration file, applied by
   hand like every other migration here).
2. `bandAvatar.ts` → `avatarStorage.ts`, parameterised, with both wrappers.
   Update the two band call sites. No behaviour change — verify bands still work
   before moving on.
3. `PerformerForm`: swap the hidden input for `<AvatarCropper label="Tu foto" />`,
   wire `crop` / `remove` the way `bands/[id]/edit` does.
4. Upload on submit in `performers/[id]/edit` and `performers/create`, mirroring
   the band create/edit pattern (upload → get URL → save it on the row).
5. The header fix — the extra column in `+layout.js` and `$user.avatarUrl` in the
   layout markup.

Steps 1–2 are a pure refactor and can land on their own.

## Verification worth doing explicitly

- Upload a photo → it appears in the **header** as well as on the performer page,
  setlist rows, and the organizer list. The header is the one that would silently
  fail.
- Replacing an uploaded avatar deletes the old object (check the bucket) — but
  replacing a *Google* URL deletes nothing and throws nothing.
- Another user cannot write into your folder: try an upload to
  `{someone-elses-uid}/x.webp` with the anon key and confirm storage refuses it.
  This is the security check that matters, and folder-name policies are easy to
  get subtly wrong.
- A >256 KB or non-WebP upload is refused by the bucket, not just by the client.
- Bands still work after the refactor.

## Out of scope

- Cropping/zoom improvements to `AvatarCropper` — reuse it exactly as-is.
- Avatars for venues.
- Cleaning up storage objects when an account is deleted. Worth a note, but an
  orphaned 50 KB object is a smaller problem than the machinery to prevent it.
