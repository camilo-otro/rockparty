import { fail } from '@sveltejs/kit';
import { supabase } from '$lib/supabaseClient.js';
export const actions = {
  default: async ({ request }) => {
    const formData = await request.formData();
    const nickname = formData.get('nickname');
    const role = formData.get('role');
    if (!nickname || !role) {
      return fail(400, { error: 'All fields are required.', success: false });
    }
    try {
      const { data, error: dbError } = await supabase
        .from('user')
        .insert([{ nickname, role }])
        .select();
      if (dbError) {
        return fail(500, { error: 'Database error', details: dbError.message, success: false });
      }
      return { success: true, message: 'Performer created successfully', performer: { nickname, role } };
    } catch (e) {
      return fail(500, { error: 'Could not connect to the server.', success: false });
    }
  },
};
