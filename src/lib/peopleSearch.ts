import { supabase } from '$lib/supabaseClient';

// Bounded, server-side people search for the admin pickers (#92).
//
// PartyForm and VenueForm both used to fetch EVERY row of `profile` and filter
// with `nickname.toLowerCase().includes(...)` in the browser. Between them they
// mount on four pages, so every visit shipped the whole user table. Free at 21
// profiles, linear thereafter, and quiet — the form just gets slower to become
// usable with no error to notice.
//
// Shared rather than copied into both because the fiddly parts — sanitising the
// term, the minimum length, the limit — are exactly the bits that drift apart
// when duplicated. The debounce and latest-wins guard stay in the components,
// since that state belongs to an instance, not to a module.

export const PEOPLE_LIMIT = 20;

// Below this a substring match is everybody, which defeats the point of the
// limit and makes the first keystroke the most expensive one.
const MIN_TERM = 2;

export type Person = { id: string; nickname: string | null };

/**
 * Search profiles by nickname. Returns [] for a term too short to narrow
 * anything — the caller should treat that as "no suggestions", not an error.
 */
export async function searchPeople(raw: string): Promise<Person[]> {
  // PostgREST parses filters from a string, so these characters either break
  // the grammar or silently widen the match. Same guard as the song search in
  // routes/songs/+page.svelte.
  const term = (raw ?? '').trim().replace(/[%_,()]/g, '');
  if (term.length < MIN_TERM) return [];

  const { data, error } = await supabase
    .from('profile')
    .select('id, nickname')
    .ilike('nickname', `%${term}%`)
    .order('nickname')
    .limit(PEOPLE_LIMIT);

  // A failed lookup means "no suggestions", never a thrown form. The picker is
  // an assist; the field it decorates still works without it.
  if (error) return [];
  return data ?? [];
}

/**
 * The people already attached to something, by id.
 *
 * Needed because the pickers used to pre-fill from the full user list
 * (`userOptions.filter(u => initialAdmins.includes(u.id))`), which stops being
 * true the moment that list is bounded — an existing admin outside the first
 * page of results would silently vanish from the form and be dropped on save.
 */
export async function peopleByIds(ids: string[]): Promise<Person[]> {
  if (!ids?.length) return [];
  const { data, error } = await supabase
    .from('profile')
    .select('id, nickname')
    .in('id', ids);
  if (error) return [];
  return data ?? [];
}
