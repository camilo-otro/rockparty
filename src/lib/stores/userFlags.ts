import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// The per-user flags the profile menu and the dev-only form toggles read (#101).
//
// One module and ONE request, replacing dev.ts + venueAdmin.ts + songModerator.ts
// and the five round trips they used to make on every cold load (a getUser()
// call for a uid the layout already had, plus four table lookups). Splitting the
// stores across three files while a single function set all of them would be
// worse than either extreme: you would declare a store in one place and assign
// it somewhere else entirely.
//
// All three are DISPLAY conveniences, not security. RLS decides every read and
// write regardless of what these say — a user who flips isSongModerator in the
// console gets a menu entry leading to a page the database refuses to fill.

// Developer (a row in public.dev_user, #67). Sees test data and gets the
// "Datos de prueba" toggle on the create/edit forms.
export const isDev = writable(false);

// Manages at least one venue — creator OR venue_admin, because venues have no
// creator-auto-add trigger, so the two are genuinely separate questions.
export const managesVenue = writable(false);

// May delete user-added catalogue entries (#100). One account today.
export const isSongModerator = writable(false);

/**
 * Refresh all three from a single RPC.
 *
 * `uid` is REQUIRED and must come from a session the caller already holds —
 * this function deliberately never asks the auth client who the user is. The
 * old refreshDev() had a `knownUid?` parameter whose "caller doesn't know"
 * branch called supabase.auth.getUser(); doing that from inside
 * onAuthStateChange re-enters the auth client, which emits another SIGNED_IN,
 * which is a self-sustaining loop. Supabase's own docs warn against calling
 * their methods from that callback. Removing the optional branch removes the
 * trap along with the wasted request.
 *
 * Pass null for a signed-out user: that clears the flags without a round trip.
 */
export async function refreshUserFlags(uid: string | null): Promise<void> {
  if (!uid) {
    isDev.set(false);
    managesVenue.set(false);
    isSongModerator.set(false);
    return;
  }

  // my_user_flags() reads auth.uid() server-side; `uid` is only the signal that
  // somebody is signed in, so there is no way for the client to ask about
  // another user by passing a different id.
  const { data, error } = await supabase.rpc('my_user_flags');
  const flags = data?.[0];
  if (error || !flags) {
    // Fail closed. These only ever ADD menu entries, so false hides an entry the
    // user might have earned — annoying, and fixed by a reload — whereas true
    // would show a link into a page the database will refuse to fill.
    isDev.set(false);
    managesVenue.set(false);
    isSongModerator.set(false);
    return;
  }

  isDev.set(!!flags.is_dev);
  managesVenue.set(!!flags.manages_venue);
  isSongModerator.set(!!flags.is_song_moderator);
}
