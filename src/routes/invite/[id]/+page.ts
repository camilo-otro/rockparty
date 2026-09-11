import type { PageLoad } from './$types';
import { supabase } from '$lib/supabaseClient';

// SSR only this route (overrides the layout's ssr=false, #48) so a shared song
// invite previews as something (#111). Same relationship /flyer/[id] has to
// /parties/[id], one level down:
//
//   /parties/[id]      app page  ──public companion──▶  /flyer/[id]
//   /performance/[id]  app page  ──public companion──▶  /invite/[id]   ← this
//
// Measured before this existed: /flyer/25 returned 11,908 bytes with og:title,
// og:description and a 1200x630 og:image; /performance/125 returned 1,491 bytes
// of empty shell. The one link in the app whose whole job is recruiting a
// musician was the one that said least.
//
// Why not just set ssr = true on /performance/[id]: it is an app page, dense
// with auth-dependent UI (signup buttons, instrument pickers, approve/decline).
// SSR-ing it reintroduces the logged-out flash #48 removed, on a page people use
// constantly, to benefit visitors who are mostly not logged in.
export const ssr = true;

// The setlist model has no per-song "required instruments" list: `instrument` is
// a fixed six-row lookup and every one of them is an open spot until an approved
// signup takes it (see availableInstruments in PerformanceDetail). So "what is
// still open" is the six minus the taken — which is why the whole table is
// fetched rather than something hanging off the performance.

export const load: PageLoad = async ({ params }) => {
	const id = Number(params.id);

	// ONE wave. This blocks the invite's first byte — it is the page a stranger
	// opens from a WhatsApp link, so a serial round trip here is the expensive
	// kind. The instrument lookup depends on nothing, so it rides alongside.
	//
	// RLS applies to the anon server-side read exactly as it does to the client:
	// `performance` leans on can_see_party(), and party's own SELECT policy admits
	// only status in (confirmed, live, completed). A link to a draft, a
	// pending_venue, a cancelled or a test toque therefore comes back as NO ROW,
	// and the page falls back to the generic brand card. Verified over REST with
	// the anon key: perf 33 (real) → full row; perf 125 (is_test) → [].
	const [perfRes, instrRes] = await Promise.all([
		supabase
			.from('performance')
			.select(
				'id, band_id, band:band_id ( name ), song ( title, artist, ref_link ),' +
					// Aliased so the embed doesn't shadow the scalar `party.venue` column,
					// same as the flyer's load.
					' party ( id, title, date, status, is_test, venue_ref:venue ( name ) ),' +
					' performance_user ( status, instrument:instrument_id ( name ) )'
			)
			.eq('id', id)
			.maybeSingle(),
		supabase.from('instrument').select('id, name').order('id')
	]);

	const row = perfRes.data as any;
	const party = row?.party ?? null;

	// No row, or a row whose party we somehow got without being allowed to show
	// it: fall back to the generic brand card rather than half-rendering.
	if (!row || !party) {
		return {
			performance: null,
			song: null,
			party: null,
			venue: null,
			bandName: null,
			taken: [] as string[],
			open: [] as string[],
			lineupKnown: false
		};
	}

	// Only APPROVED signups take a spot. A pending applicant leaves the spot open
	// to compete for — the same rule PerformanceDetail's takenInstrumentIds uses,
	// and the reason we can publish this without publishing who applied.
	const taken = ((row.performance_user ?? []) as any[])
		.filter((s) => s.status === 'approved')
		.map((s) => s.instrument?.name)
		.filter(Boolean) as string[];

	const takenSet = new Set(taken);
	const instruments = (instrRes.data ?? []) as any[];
	const open = instruments.map((i) => i.name as string).filter((name) => !takenSet.has(name));

	// If the instrument lookup failed, `open` is empty for a reason that has
	// nothing to do with the song — and an empty `open` is what the page reads as
	// "ya está completa". Saying a wide-open song is full is worse than saying
	// nothing, so the page needs to tell the two apart.
	const lineupKnown = !instrRes.error && instruments.length > 0;

	return {
		performance: { id: row.id, band_id: row.band_id ?? null },
		song: row.song ?? null,
		party: {
			id: party.id,
			title: party.title,
			date: party.date,
			status: party.status,
			is_test: party.is_test
		},
		venue: party.venue_ref ?? null,
		bandName: row.band?.name ?? null,
		taken,
		open,
		lineupKnown
	};
};
