import { writable } from 'svelte/store';

export type ToastType = 'error' | 'success' | 'info';
export interface Toast {
	id: number;
	type: ToastType;
	message: string;
}

let nextId = 1;

export const toasts = writable<Toast[]>([]);

export function dismissToast(id: number) {
	toasts.update((list) => list.filter((t) => t.id !== id));
}

/** Show a toast. `timeout` in ms; pass 0 to keep it until dismissed. */
export function showToast(message: string, type: ToastType = 'info', timeout = 4000) {
	const id = nextId++;
	toasts.update((list) => [...list, { id, type, message }]);
	if (timeout > 0) setTimeout(() => dismissToast(id), timeout);
	return id;
}

export const toastError = (message: string, timeout = 6000) => showToast(message, 'error', timeout);
export const toastSuccess = (message: string, timeout = 4000) => showToast(message, 'success', timeout);
export const toastInfo = (message: string, timeout = 4000) => showToast(message, 'info', timeout);

/**
 * Extract a human-readable message from a Supabase/JS error (or string) and
 * surface it as an error toast. Returns the message shown.
 */
export function reportError(err: unknown, fallback = 'Algo salió mal. Intenta de nuevo.') {
	let message = fallback;
	if (typeof err === 'string' && err.trim()) {
		message = err;
	} else if (err && typeof err === 'object' && 'message' in err) {
		const m = (err as { message?: unknown }).message;
		if (typeof m === 'string' && m.trim()) message = m;
	}
	toastError(message);
	return message;
}
