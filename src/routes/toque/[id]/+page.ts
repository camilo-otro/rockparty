import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

// The public flyer moved to /flyer/[id] (English routes — code/routes are English,
// only UI copy is Spanish). Keep this permanent redirect so any already-shared
// /toque/[id] links (and their cached previews) still resolve. SSR so crawlers
// following an old link get the 308 too.
export const ssr = true;

export const load: PageLoad = ({ params }) => {
  throw redirect(308, `/flyer/${params.id}`);
};
