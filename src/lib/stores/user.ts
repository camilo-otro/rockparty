export type UserRecord = {
  id?: string;
  email: string;
  role?: string;
  nickname?: string;
  avatarUrl?: string | null;
};

import { writable } from 'svelte/store';

export const user = writable<UserRecord | null>(null);