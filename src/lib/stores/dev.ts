import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// Whether the current user is a developer (a row in public.dev_user). Devs see
// test data (enforced in RLS) and get the dev-only "Datos de prueba" toggle;
// everyone else never does. Dev membership is granted only out-of-band (SQL
// editor), so this is a display convenience — RLS is the real boundary.
export const isDev = writable(false);

export async function refreshDev(): Promise<void> {
  const { data: auth } = await supabase.auth.getUser();
  const uid = auth?.user?.id;
  if (!uid) {
    isDev.set(false);
    return;
  }
  // dev_user's self-read policy returns only the caller's own row (or none).
  const { data } = await supabase
    .from('dev_user')
    .select('user_id')
    .eq('user_id', uid)
    .maybeSingle();
  isDev.set(!!data);
}
