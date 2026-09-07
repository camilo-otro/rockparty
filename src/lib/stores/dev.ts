import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// Whether the current user is a developer (a row in public.dev_user). Devs see
// test data (enforced in RLS) and get the dev-only "Datos de prueba" toggle;
// everyone else never does. Dev membership is granted only out-of-band (SQL
// editor), so this is a display convenience — RLS is the real boundary.
export const isDev = writable(false);

// Pass `knownUid` when the caller already has the user id — notably from an
// onAuthStateChange session. Calling supabase.auth.getUser() from inside that
// callback re-enters the auth client and makes it emit another SIGNED_IN, which
// is a self-sustaining loop (Supabase's own docs warn against calling their
// methods from that callback). Omit it and we fetch, which is fine off that path.
export async function refreshDev(knownUid?: string | null): Promise<void> {
  // `undefined` means "caller doesn't know" -> ask. An explicit `null` means the
  // caller KNOWS there's no user (a SIGNED_OUT session), so don't re-enter the
  // auth client to be told the same thing.
  let uid = knownUid ?? null;
  if (knownUid === undefined) {
    const { data: auth } = await supabase.auth.getUser();
    uid = auth?.user?.id ?? null;
  }
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
