export type UserRecord = {
  id?: string;
  email: string;
  role?: any;
  nickname?: any;
  auth_id: any;
};

import { writable } from 'svelte/store';

export const user = writable<UserRecord | null>(null);