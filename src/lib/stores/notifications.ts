import { writable } from 'svelte/store';
import { supabase } from '$lib/supabaseClient';
import type { RealtimeChannel } from '@supabase/supabase-js';

// Unread notification count for the header bell (#57). The layout keeps it fresh
// (on mount + after each navigation + on focus), and Realtime pushes new ones
// live (#63); the notifications page refreshes it after marking things read.
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

// Live bell (#63): subscribe to the current user's new notifications. RLS scopes
// Realtime to the recipient, and the explicit filter keeps it tight. On any new
// row we just re-count (cheap, always correct).
let channel: RealtimeChannel | null = null;

export async function subscribeUnread(): Promise<void> {
  const { data } = await supabase.auth.getSession();
  const uid = data.session?.user?.id;
  if (!uid) return;
  await unsubscribeUnread();
  channel = supabase
    .channel(`notif-unread-${uid}`)
    .on(
      'postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'notification', filter: `recipient=eq.${uid}` },
      () => refreshUnread()
    )
    .subscribe();
}

export async function unsubscribeUnread(): Promise<void> {
  if (channel) {
    await supabase.removeChannel(channel);
    channel = null;
  }
}
