export type UserRecord = {
  id?: string;
  email: string;
  role?: number | null;
  nickname?: string | null;
  avatarUrl?: string | null;
};

import { writable } from 'svelte/store';

export const user = writable<UserRecord | null>(null);