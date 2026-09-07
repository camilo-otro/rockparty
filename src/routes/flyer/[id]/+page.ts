import type { PageLoad } from './$types';
import { supabase } from '$lib/supabaseClient';

// SSR only this route (overrides the layout's ssr=false, #48) so crawlers get
// per-event Open Graph tags for shared flyers (#68). RLS applies to the anon
// server-side read, so test/draft toques come back null for crawlers and fall
// back to the generic brand preview — no private data leaks.
export const ssr = true;

export const load: PageLoad = async ({ params }) => {
  const id = Number(params.id);

  // ONE wave (#89, see #84). This load blocks the flyer's first byte — it's the
  // page a stranger opens from a shared link, so serial round trips here are the
  // most expensive in the app. Both real dependencies are gone via embeds:
  // the venue rides along on the party row, and the signups ride along on the
  // performances (which is what made this a 5-hop chain).
  //
  // RLS applies to embedded rows exactly as it did to the separate queries, so
  // an anon crawler still sees only what the policies allow.
  const [partyRes, perfRes, rsvpRes] = await Promise.all([
    supabase
      .from('party')
      // Aliased so the embed doesn't shadow the scalar `party.venue` column.
      .select('id, title, date, description, venue, status, is_test, venue_ref:venue ( name, address )')
      .eq('id', id)
      .maybeSingle(),
    supabase
      .from('performance')
      .select('id, order, song ( title ), performance_user ( user_id, status )')
      .eq('party', id)
      .order('order', { ascending: true }),
    supabase.from('party_rsvp').select('user_id', { count: 'exact', head: true }).eq('party_id', id)
  ]);

  const party = partyRes.data;
  // A party the anon/current role can't SELECT means the flyer falls back to the
  // generic brand card — don't report counts for a toque we can't show.
  if (!party) {
    return { party: null, venue: null, songs: [] as string[], songCount: 0, musicianCount: 0, rsvpCount: 0 };
  }

  const venue = ((party as any).venue_ref ?? null) as { name: string | null; address: string | null } | null;
  const rows = (perfRes.data ?? []) as any[];
  const songs = rows.map((r) => r.song?.title).filter(Boolean).slice(0, 5) as string[];
  // Status is filtered here rather than on the embed: it's a handful of rows per
  // setlist, and it keeps the single round trip.
  const musicianCount = new Set(
    rows.flatMap((r) => (r.performance_user ?? []).filter((s: any) => s.status === 'approved').map((s: any) => s.user_id))
  ).size;

  return { party, venue, songs, songCount: rows.length, musicianCount, rsvpCount: rsvpRes.count ?? 0 };
};
