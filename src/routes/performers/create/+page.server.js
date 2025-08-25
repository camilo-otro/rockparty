import { fail } from '@sveltejs/kit';
import { createAuthenticatedSupabaseClient } from '$lib/supabaseClient.js';
import { sanitizeFormData } from '$lib/sanitize.js';
export const actions = {
  default: async ({ request, locals }) => {
    const formData = await request.formData();
    const sanitized = sanitizeFormData(formData);
    const nickname = sanitized.nickname;
    const authId = sanitized.auth_id;
    const email = sanitized.email;
    if (!nickname || !authId || !email) {
      return fail(400, { error: 'All fields are required.', success: false });
    }
    const supabase = locals.session ? 
      createAuthenticatedSupabaseClient(locals.session.access_token) :
      null;
    if (!supabase) {
      return fail(401, { error: 'Authentication required.', success: false });
    }
    try {
      const { data, error: dbError } = await supabase
        .from('user')
        .insert([{ nickname, auth_id: authId, email }])
        .select();
      if (dbError) {
        return fail(500, { error: 'Database error', details: dbError.message, success: false });
      }
      return { success: true, message: 'Performer created successfully', performer: { nickname, email } };
    } catch (e) {
      return fail(500, { error: 'Could not connect to the server.', success: false });
    }
  },
};
