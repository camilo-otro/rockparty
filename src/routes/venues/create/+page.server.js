import { fail } from '@sveltejs/kit';
import { supabase } from '$lib/supabaseClient.js';
// This `actions` object is a special SvelteKit feature.
// It contains functions that handle form submissions.
export const actions = {
  // The `default` action is used when the form doesn't specify a named action.
  default: async ({ request }) => {
    // Get the form data from the incoming request.
    const formData = await request.formData();
    const name = formData.get('name');
    const address = formData.get('address');
    const contactName = formData.get('contact_name');
    const contactInfo = formData.get('contact');
    // --- Basic Validation ---
    if (!name || !address || !contactName || !contactInfo) {
      return fail(400, { error: 'All fields are required.', success: false });
    }

    // Prepare the data for your API endpoint.
    const apiRequestBody = {
        name: name.toString(),
        address: address.toString(),
        contactName: contactName.toString(),
        contactInfo: contactInfo.toString()
    };

    console.log('Sending to external API:', apiRequestBody);

    // --- API Call ---
    try {
        // Insert the venue into the "venues" table in Supabase
        console.log('Creating venue:', { name, address, contactName, contactInfo });
        const { data, error: dbError } = await supabase
            .from('venue')
            .insert([{ name, address, contact_name: contactName, contact: contactInfo }])
            .select();

        if (dbError) {
            console.error('Database error:', dbError);
            return fail(500, { error: 'Database error', details: dbError.message, success: false });
        }

        // If the insertion is successful, return a success response.
        return { success: true, message: 'Venue {name} created successfully', venue: { name, address, contactName, contactInfo } };
    } catch (e) {
      // Handle network errors or other exceptions.
      console.error('Network or other error:', e);
      return fail(500, { error: 'Could not connect to the server.', success: false });
    }
  },
};
