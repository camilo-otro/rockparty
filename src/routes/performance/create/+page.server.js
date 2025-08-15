import { fail } from '@sveltejs/kit';
import { supabase } from '$lib/supabaseClient.js';
export const actions = {
  default: async ({ request }) => {
    const formData = await request.formData();
    const party = formData.get('party');
    const song = formData.get('song');
    const suggested_by = formData.get('suggested_by');
    const ref_link = formData.get('ref_link');
    const key = formData.get('key');
    if (!party || !song || !suggested_by) {
      return fail(400, { error: 'Party, song, and suggested_by are required.', success: false });
    }
    try {
      const { data, error: dbError } = await supabase
        .from('performance')
        .insert([{ party, song, suggested_by, ref_link, key }])
        .select();
      if (dbError) {
        return fail(500, { error: 'Database error', details: dbError.message, success: false });
      }
      return { success: true, message: 'Performance created successfully', performance: { party, song, suggested_by, ref_link, key } };
    } catch (e) {
      return fail(500, { error: 'Could not connect to the server.', success: false });
    }
  },
};
