import { supabase } from '$lib/supabaseClient';
import { user as userStore } from '$lib/stores/user';
import { redirect } from '@sveltejs/kit';

export const load = async ({ fetch, data, depends, url }) => {
  depends('supabase:auth');
  const { data: { session } } = await supabase.auth.getSession();
  let userRecord = null;
  if (session?.user?.id) {
    // Try to fetch user entity by auth_id
    let { data: dbUser } = await supabase.from('user').select('id, role, nickname, auth_id').eq('auth_id', session.user.id).single();
    // If not found, redirect to performer creation
    if (!dbUser) {
      userRecord = {
        email: session?.user?.email ?? '',
        auth_id: session?.user?.id
      };
      userStore.set(userRecord);
      if (!url.pathname.startsWith('/performers/create')) {
        throw redirect(302, '/performers/create');
      }
    } else {
      userRecord = {
        id: dbUser?.id,
        email: session?.user?.email ?? '',
        role: dbUser?.role,
        nickname: dbUser?.nickname,
        auth_id: dbUser?.auth_id
      };
    userStore.set(userRecord);
    }
  } else {
    userStore.set(null);
  }
  return { supabase, session, user: userRecord };
};