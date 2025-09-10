import { supabase } from '$lib/supabaseClient';
import { user as userStore } from '$lib/stores/user';
import { redirect } from '@sveltejs/kit';

export const load = async ({ depends, url }) => {
  depends('supabase:auth');
  const { data: { session } } = await supabase.auth.getSession();
  let userRecord = null;
  if (session?.user?.id) {
    // Try to fetch user entity by id
    let { data: dbUser } = await supabase.from('profile').select('id, role, nickname').eq('id', session.user.id).single();
    // If not found, redirect to performer creation
    if (!dbUser) {
      userRecord = {
        email: session?.user?.email ?? '',
        id: session?.user?.id
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
      };
    userStore.set(userRecord);
    }
  } else {
    userStore.set(null);
  }
  return { supabase, session, user: userRecord };
};