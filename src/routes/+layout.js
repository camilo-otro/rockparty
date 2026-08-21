import { supabase } from '$lib/supabaseClient';
import { user as userStore } from '$lib/stores/user';
import { redirect } from '@sveltejs/kit';

export const load = async ({ depends, url }) => {
  depends('supabase:auth');
  const { data: { session } } = await supabase.auth.getSession();
  let userRecord = null;
  if (session?.user?.id) {
    // Try to fetch user entity by id. Email is intentionally NOT selected — it's
    // never displayed and is revoked from client reads (see migration
    // 20260821_profile_email_privacy.sql); the completeness gate below uses
    // nickname, which the profile always gets alongside email at creation.
    let { data: dbUser } = await supabase.from('profile').select('id, role, nickname').eq('id', session.user.id).single();
    // If not found, redirect to performer creation
    if (!dbUser || !dbUser.nickname) {
      userRecord = {
        email: session?.user?.email ?? '',
        avatarUrl: session?.user?.user_metadata?.avatar_url || null,
        id: session?.user?.id
      };
      userStore.set(userRecord);
      if (!/^\/performers\/[^/]+\/edit$/.test(url.pathname)) {
        throw redirect(302, '/performers/' + userRecord.id + '/edit');
      }
    } else {
      userRecord = {
        id: dbUser?.id,
        email: session?.user?.email ?? '',
        role: dbUser?.role,
        nickname: dbUser?.nickname,
      };
    userStore.set(userRecord);
    }
  } else {
    userStore.set(null);
  }
  return { supabase, session, user: userRecord };
};