import { fail } from '@sveltejs/kit';
import { createAuthenticatedSupabaseClient } from '$lib/supabaseClient.js';
import { sanitizeFormData } from '$lib/sanitize.js';
export const actions = {
  default: async ({ request, locals }) => {
    const formData = await request.formData();
    const sanitized = sanitizeFormData(formData);
    const title = sanitized.title;
    const artist = sanitized.artist;
    const key = sanitized.key;
    const reflink = sanitized.reflink;
    const added_by = sanitized.added_by;
    
    if (!title || !artist) {
      return fail(400, { error: 'Title and artist are required.', success: false });
    }
    
    // Use authenticated supabase client
    const supabase = locals.session ? 
      createAuthenticatedSupabaseClient(locals.session.access_token) :
      null;
      
    if (!supabase) {
      return fail(401, { error: 'Authentication required.', success: false });
    }
    
    try {
      const { data, error: dbError } = await supabase
        .from('song')
        .insert([{ title, artist, key, reflink, added_by }])
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
