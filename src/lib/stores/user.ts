export type UserRecord = {
  id: string;
  email?: string;
  role: any;
  nickname: any;
};

import { writable } from 'svelte/store';

export const user = writable<UserRecord | null>(null);