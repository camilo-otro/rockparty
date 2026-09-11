import { supabase } from '$lib/supabaseClient';
import { user as userStore } from '$lib/stores/user';
import { redirect } from '@sveltejs/kit';
import { browser } from '$app/environment';

// Client-only rendering (#48). The app has no server routes and fetches all data
// client-side (RLS is the security boundary), so SSR added no value — and it was
// harmful here: this load runs during SSR where there's no localStorage, so
// getSession() returns null and the app hydrates logged-out until the client
// restores the session (~1s flash of "Ingresar" / auth gates). Running the load
// only on the client lets getSession() see the restored session before first
// render, so the auth state is correct from the first paint.
export const ssr = false;

export const load = async ({ depends, url }) => {
  depends('supabase:auth');
  // The flyer route (#68) turns SSR on, which pulls this root layout load onto
  // the server. Auth lives entirely in the browser (localStorage session), so
  // getSession() would be null server-side anyway — skip it there. This keeps
  // the SSR render clean and never writes the shared `user` store on the server.
  if (!browser) return { supabase, session: null, user: null };
  const { data: { session } } = await supabase.auth.getSession();
  let userRecord = null;
  if (session?.user?.id) {
    // Try to fetch user entity by id. Email is intentionally NOT selected — it's
    // never displayed and is revoked from client reads (see migration
    // 20260821_profile_email_privacy.sql); the completeness gate below uses
    // nickname, which the profile always gets alongside email at creation.
    // `role` is gone (#99): it was never read by any policy, function or
    // component — it only LOOKED like an admin flag, and it was user-writable.
    // Selecting it here was the one thing keeping it alive.
    let { data: dbUser } = await supabase.from('profile').select('id, nickname').eq('id', session.user.id).single();
    // If not found, redirect to performer creation
    if (!dbUser || !dbUser.nickname) {
      userRecord = {
        email: session?.user?.email ?? '',
        avatarUrl: session?.user?.user_metadata?.avatar_url || null,
        id: session?.user?.id
      };
      userStore.set(userRecord);
      if (!/^\/performers\/[^/]+\/edit$/.test(url.pathname)) {
        // Carry where they were going through the profile detour. Without this a
        // deep link is simply lost — which broke claim links (#79) for exactly
        // the people they exist for: someone with no account yet, who cannot be
        // added to a band at all until a profile row exists (band_member.user_id
        // FKs to profile).
        const next = url.pathname + url.search;
        throw redirect(302, '/performers/' + userRecord.id + '/edit?next=' + encodeURIComponent(next));
      }
    } else {
      userRecord = {
        id: dbUser?.id,
        email: session?.user?.email ?? '',
        nickname: dbUser?.nickname,
      };
    userStore.set(userRecord);
    }
  } else {
    userStore.set(null);
  }
  return { supabase, session, user: userRecord };
};