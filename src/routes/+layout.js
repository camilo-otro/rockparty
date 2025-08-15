import { supabase } from '$lib/supabaseClient';
import { user as userStore } from '$lib/stores/user';

export const load = async ({ fetch, data, depends }) => {
  depends('supabase:auth');
  const { data: { session } } = await supabase.auth.getSession();
  let userRecord = null;
  if (session?.user?.id) {
    const { data: dbUser } = await supabase.from('user').select('id, role, nickname').eq('id', session.user.id).single();
    userRecord = {
      id: session.user.id,
      email: session.user.email,
      role: dbUser?.role,
      nickname: dbUser?.nickname
    };
    userStore.set(userRecord);
  } else {
    userStore.set(null);
  }
  return { supabase, session, user: userRecord };
};