import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// Whether the current user manages at least one venue — drives the "Mis locales"
// entry in the profile menu, which most users (musicians) never need.
//
// Two queries, because unlike parties and bands there is NO trigger adding a
// venue's creator to venue_admin: of the venues in the DB, most have a
// created_by and no venue_admin row at all. So "manages a venue" genuinely means
// `venue.created_by = me` OR a `venue_admin` row, and the pair has to be checked.
// The home page's managedVenueIds does exactly the same thing.
//
// Called once per page load from the layout's onMount (alongside refreshUnread /
// refreshDev), not from the layout's `load` — this is a cosmetic menu signal, so
// it should never block a render, and once per session is enough. Both queries
// go out together and ask only for existence.
export const managesVenue = writable(false);

export async function refreshManagesVenue(uid: string | null): Promise<void> {
  if (!uid) {
    managesVenue.set(false);
    return;
  }
  const [ownedRes, adminRes] = await Promise.all([
    supabase.from('venue').select('id').eq('created_by', uid).limit(1),
    supabase.from('venue_admin').select('venue_id').eq('user_id', uid).limit(1)
  ]);
  managesVenue.set(!!(ownedRes.data?.length || adminRes.data?.length));
}
