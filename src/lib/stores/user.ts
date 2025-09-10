export type UserRecord = {
  id?: string;
  email: string;
  role?: string;
  nickname?: string;
};

import { writable } from 'svelte/store';

export const user = writable<UserRecord | null>(null);