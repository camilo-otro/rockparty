import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { env } from '$env/dynamic/public'
import type { Database } from './database.types'

// $env/dynamic/public types values as `string | undefined`; these are required
// (the app can't reach Supabase without them), so fail loudly if missing.
const SUPABASE_URL = env.PUBLIC_SUPABASE_URL
const SUPABASE_ANON_KEY = env.PUBLIC_SUPABASE_ANON_KEY
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error(
    'Missing PUBLIC_SUPABASE_URL / PUBLIC_SUPABASE_ANON_KEY (see .env.example)'
  )
}

export const supabase: SupabaseClient<Database> = createClient<Database>(
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  {
    auth: {
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: true
    }
  }
)

/**
 * Creates an authenticated Supabase client for server-side use.
 * @param accessToken - The access token for authentication.
 */
export function createAuthenticatedSupabaseClient(
  accessToken: string
): SupabaseClient<Database> {
  return createClient<Database>(
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    {
      global: {
        headers: {
          Authorization: `Bearer ${accessToken}`
        }
      }
    }
  )
}
