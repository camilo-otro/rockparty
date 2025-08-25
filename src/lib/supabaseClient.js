// @ts-nocheck
import { createClient } from '@supabase/supabase-js'
import { env } from '$env/dynamic/public'

export const supabase = createClient(env.PUBLIC_SUPABASE_URL, env.PUBLIC_SUPABASE_ANON_KEY, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  }
})

// Create authenticated supabase client for server-side use
// Note: Type information is omitted since this is a JavaScript file.

/**
 * Creates an authenticated Supabase client for server-side use.
 * @param accessToken - The access token for authentication.
 * @returns Supabase client instance.
 */
export function createAuthenticatedSupabaseClient(accessToken) {
    return createClient(
        env.PUBLIC_SUPABASE_URL,
        env.PUBLIC_SUPABASE_ANON_KEY,
        {
            global: {
                headers: {
                    Authorization: `Bearer ${accessToken}`
                }
            }
        }
    )
}