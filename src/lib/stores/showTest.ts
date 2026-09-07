import { writable } from 'svelte/store';

// Whether test data (`is_test` rows) is shown in the app's lists.
//
// Only developers ever RECEIVE test rows — that's enforced in RLS via is_dev(),
// see the party/venue SELECT policies. This store is the second, softer filter
// on top: a dev who isn't actively testing doesn't want their own toques buried
// under "Prueba rechazo UI". Hence OFF by default, even for devs.
//
// Persisted in localStorage rather than the database: it's a per-device view
// preference, not user data, so it isn't worth a round trip or a column. It
// survives reloads and is scoped to the browser the dev is testing in.
const KEY = 'rp:show-test';
const canStore = typeof localStorage !== 'undefined';

function stored(): boolean {
  if (!canStore) return false;
  try {
    return localStorage.getItem(KEY) === '1';
  } catch {
    return false; // private mode / blocked storage — just default to hidden
  }
}

export const showTest = writable(stored());

showTest.subscribe((v) => {
  if (!canStore) return;
  try {
    localStorage.setItem(KEY, v ? '1' : '0');
  } catch {
    /* nothing to do — the toggle still works for this session */
  }
});

// Convenience for the list pages. Reference `$showTest` textually in the `$:`
// that calls this (Svelte legacy mode tracks dependencies by NAME, so a helper
// reading the store internally would never re-run):
//   $: visible = keepTest(rows, $showTest)
export function keepTest<T extends { is_test?: boolean | null }>(rows: T[], show: boolean): T[] {
  return show ? rows : rows.filter((r) => !r.is_test);
}
