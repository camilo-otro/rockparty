import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// Whether the current user may delete user-added songs (a row in
// public.song_moderator) — drives the "Moderar canciones" entry in the profile
// menu, which is a one-person link.
//
// Deliberately NOT reusing isDev: dev_user grants test-data VISIBILITY and has
// four members, while this grants a delete that cascades through set lists.
// Keeping the lists separate means widening one never silently widens the other.
//
// Like isDev this is a display convenience only. The real boundary is the
// `song` DELETE policy, which re-checks is_song_moderator() server-side and also
// refuses any song that is on a non-test set list — a check the client mirrors
// for the UI but does not enforce.
export const isSongModerator = writable(false);

export async function refreshSongModerator(uid: string | null): Promise<void> {
  if (!uid) {
    isSongModerator.set(false);
    return;
  }
  // song_moderator's self-read policy returns only the caller's own row (or none).
  const { data } = await supabase
    .from('song_moderator')
    .select('user_id')
    .eq('user_id', uid)
    .maybeSingle();
  isSongModerator.set(!!data);
}
