import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';

// Unread notification count for the header bell (#57). The layout keeps it fresh
// (on mount + after each navigation); the notifications page refreshes it after
// marking things read so the badge updates without a navigation.
export const unreadCount = writable(0);

export async function refreshUnread(): Promise<void> {
  const { data } = await supabase.auth.getSession();
  if (!data.session) {
    unreadCount.set(0);
    return;
  }
  const { count } = await supabase
    .from('notification')
    .select('id', { count: 'exact', head: true })
    .is('read_at', null);
  unreadCount.set(count ?? 0);
}
