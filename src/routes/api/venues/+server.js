// src/routes/api/venues/+server.js

// Import the Supabase client
import { supabase } from '$lib/supabaseClient';

// Import the 'json' helper from SvelteKit to easily create JSON responses.
import { json } from '@sveltejs/kit';

/**
 * This function handles GET requests to this endpoint.
 * @param {import('./$types').RequestHandler} event
 */
export async function GET({ url }) {
  // You can access query parameters from the URL if needed
  // For example: const limit = url.searchParams.get('limit');

  console.log('Received GET request to /api/venues');

  // Use the Supabase client to fetch data from your 'posts' table.
  const { data, error } = await supabase
    .from('venue')
    .select('*');

  // Handle potential errors from the database query.
  if (error) {
    console.error('Error fetching posts for API:', error);
    // Return a 500 Internal Server Error response.
    return json({ error: 'Could not fetch posts' }, { status: 500 });
  }

  // If the query is successful, return the data as a JSON response
  // with a 200 OK status.
  return json(data, { status: 200 });
}