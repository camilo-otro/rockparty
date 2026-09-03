import type { PageLoad } from './$types';
import { supabase } from '$lib/supabaseClient';

// SSR only this route (overrides the layout's ssr=false, #48) so crawlers get
// per-event Open Graph tags for shared flyers (#68). RLS applies to the anon
// server-side read, so test/draft toques come back null for crawlers and fall
// back to the generic brand preview — no private data leaks.
export const ssr = true;

export const load: PageLoad = async ({ params }) => {
  const id = Number(params.id);

  const { data: party } = await supabase
    .from('party')
    .select('id, title, date, description, venue, status, is_test')
    .eq('id', id)
    .maybeSingle();

  let venue: { name: string | null; address: string | null } | null = null;
  let songs: string[] = [];
  let songCount = 0;
  let musicianCount = 0;
  let rsvpCount = 0;

  if (party) {
    if (party.venue != null) {
      const { data: v } = await supabase
        .from('venue').select('name, address').eq('id', party.venue).maybeSingle();
      venue = v;
    }
    const { data: perfs } = await supabase
      .from('performance')
      .select('id, order, song ( title )')
      .eq('party', id)
      .order('order', { ascending: true });
    const rows = perfs ?? [];
    songCount = rows.length;
    songs = rows.map((r: any) => r.song?.title).filter(Boolean).slice(0, 5);

    const perfIds = rows.map((r: any) => r.id);
    if (perfIds.length) {
      const { data: appr } = await supabase
        .from('performance_user').select('user_id').eq('status', 'approved').in('performance_id', perfIds);
      musicianCount = new Set((appr ?? []).map((a: any) => a.user_id)).size;
    }
    const { count } = await supabase
      .from('party_rsvp').select('user_id', { count: 'exact', head: true }).eq('party_id', id);
    rsvpCount = count ?? 0;
  }

  return { party, venue, songs, songCount, musicianCount, rsvpCount };
};
