import { fail } from '@sveltejs/kit';
import { supabase } from '$lib/supabaseClient.js';
export const actions = {
  default: async ({ request }) => {
    const formData = await request.formData();
    const date = formData.get('date');
    const venue = formData.get('venue');
    if (!date || !venue) {
      return fail(400, { error: 'All fields are required.', success: false });
    }
    try {
      const { data, error: dbError } = await supabase
        .from('party')
        .insert([{ date, venue }])
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
