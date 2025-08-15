import { fail } from '@sveltejs/kit';
import { supabase } from '$lib/supabaseClient.js';
export const actions = {
  default: async ({ request }) => {
    const formData = await request.formData();
    const title = formData.get('title');
    const artist = formData.get('artist');
    const key = formData.get('key');
    const reflink = formData.get('reflink');
    if (!title || !artist) {
      return fail(400, { error: 'Title and artist are required.', success: false });
    }
    try {
      const { data, error: dbError } = await supabase
        .from('song')
        .insert([{ title, artist, key, reflink }])
        .select();
      if (dbError) {
        return fail(500, { error: 'Database error', details: dbError.message, success: false });
      }
      return { success: true, message: 'Song created successfully', song: { title, artist, key, reflink } };
    } catch (e) {
      return fail(500, { error: 'Could not connect to the server.', success: false });
    }
  },
};
