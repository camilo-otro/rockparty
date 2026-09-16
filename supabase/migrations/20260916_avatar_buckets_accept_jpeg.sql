-- =============================================================================
-- Migration: avatar buckets accept JPEG as well as WebP (#75, #96)
-- Date: 2026-09-16
-- =============================================================================
-- APPLY BEFORE THE CLIENT DEPLOY. Additive — it only widens what is accepted, so
-- the currently-live client (which uploads WebP) keeps working either way. The
-- new client can emit JPEG, and would be refused until this runs.
--
-- -----------------------------------------------------------------------------
-- The live bug
-- -----------------------------------------------------------------------------
-- Two people reported that setting a band photo failed with "png is not
-- supported", and that picking a JPEG instead changed nothing. Both bands were
-- created the same day and neither has an object in the bucket.
--
-- The client never uploaded what it thought it did. AvatarCropper called
--
--   canvas.toBlob(cb, 'image/webp', q)
--
-- and trusted the result. But toBlob does NOT fail on a format the browser
-- cannot encode — the HTML spec says it must silently produce PNG instead. So on
-- a browser without canvas WebP *encoding* every avatar came out as a PNG, and
-- this bucket, being WebP-only, refused it.
--
-- That is why the input format made no difference: the OUTPUT format is chosen
-- by the browser's encoder, not by the file the user picked. PNG in, PNG out;
-- JPEG in, PNG out. Two people hitting the identical message from different
-- source files is the signature of that, not a coincidence.
--
-- Verified in a real browser: asking a canvas for a format it cannot encode
-- (image/avif in Chromium) returns a Blob whose type is image/png, no error
-- raised. The client now checks blob.type and treats a mismatch as "unsupported".
--
-- -----------------------------------------------------------------------------
-- Why JPEG rather than a WebP polyfill
-- -----------------------------------------------------------------------------
-- Every canvas can encode JPEG, it is lossy so `quality` still gives the client
-- a way to hit the size budget, and it costs nothing. A WASM WebP encoder would
-- be a few hundred KB of payload to avoid a format every browser already has.
--
-- PNG is deliberately NOT added: it ignores `quality`, so an oversized avatar
-- would have no way to shrink, and it ran ~4x larger than WebP in testing —
-- which would just trade this failure for a 413.
--
-- The server-side limits stay a backstop to the client's guardrails, unchanged
-- at 256 KB. See docs/specs/bands.md (Avatar handling).
-- =============================================================================

begin;

update storage.buckets
set allowed_mime_types = array['image/webp', 'image/jpeg']
where id in ('band-avatars', 'profile-avatars');

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration (the
-- generated types do not cover the storage schema).
--
-- VERIFY:
--   select id, allowed_mime_types, file_size_limit from storage.buckets;
--     -> both buckets list image/webp and image/jpeg, limit still 262144
--
-- Then set a band photo from a browser without canvas WebP encoding (Safari is
-- the usual one) and confirm it saves as a .jpg.
-- =============================================================================
