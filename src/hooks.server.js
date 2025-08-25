import { createClient } from '@supabase/supabase-js'
import { env } from '$env/dynamic/public'

export const handle = async ({ event, resolve }) => {
  // Create supabase client to get session
  const supabase = createClient(env.PUBLIC_SUPABASE_URL, env.PUBLIC_SUPABASE_ANON_KEY)
  
  // Get session from cookies
  const { data: { session } } = await supabase.auth.getSession()
  
  // Pass session to locals for use in server actions
  event.locals.session = session
  event.locals.supabase = supabase
  
  return resolve(event)
}