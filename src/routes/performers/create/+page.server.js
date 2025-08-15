import { fail } from '@sveltejs/kit';
import { supabase } from '$lib/supabaseClient.js';
import { sanitizeFormData } from '$lib/sanitize.js';
export const actions = {
  default: async ({ request }) => {
    const formData = await request.formData();
    const sanitized = sanitizeFormData(formData);
    const nickname = sanitized.nickname;
    const authId = sanitized.auth_id;
    if (!nickname) {
      return fail(400, { error: 'El Nickname es requerido.', success: false });
    }
    try {
      const { data, error: dbError } = await supabase
        .from('user')
        .insert([{ nickname, auth_id: authId }])
        .select();
      if (dbError) {
        return fail(500, { error: 'Database error', details: dbError.message, success: false });
      }
      return { success: true, message: 'Performer created successfully', performer: { nickname } };
    } catch (e) {
      return fail(500, { error: 'Could not connect to the server.', success: false });
    }
  },
};
