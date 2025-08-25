import { fail } from '@sveltejs/kit';
import { createAuthenticatedSupabaseClient } from '$lib/supabaseClient.js';
import { sanitizeFormData } from '$lib/sanitize.js';
export const actions = {
  default: async ({ request, locals }) => {
    const formData = await request.formData();
    const sanitized = sanitizeFormData(formData);
    const date = sanitized.date;
    const venue = sanitized.venue;
    const suggested_by = sanitized.suggested_by;
    if (!date || !venue) {
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
        .from('party')
        .insert([{ date, venue, suggested_by }])
        .select();
      if (dbError) {
        return fail(500, { error: 'Database error', details: dbError.message, success: false });
      }
      return { success: true, message: 'Party created successfully', party: { date, venue } };
    } catch (e) {
      return fail(500, { error: 'Could not connect to the server.', success: false });
    }
  },
};
