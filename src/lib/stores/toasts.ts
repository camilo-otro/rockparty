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

// Postgres speaks English, and reportError used to put its message straight in
// front of the user — so a refused write said "new row violates row-level
// security policy for table \"performance\"" in a Spanish app.
//
// Our own RPCs raise Spanish already (they are UI copy). These are the codes the
// DATABASE raises on its own, where there is no message of ours to read.
const DB_MESSAGES: Record<string, string> = {
	'42501': 'No tienes permiso para hacer eso.',
	'23505': 'Eso ya existe.',
	'23503': 'Eso ya no existe, o algo que depende de ello sigue ahí.',
	'23502': 'Falta un dato obligatorio.',
	'23514': 'Ese valor no es válido.',
	PGRST116: 'No encontramos eso.'
};

// Storage errors are shaped differently: no SQLSTATE `code`, just a numeric
// `statusCode` string. They fell straight through the mapping above and reached
// people as raw English — two users hit "mime type image/png is not supported"
// while trying to set a band photo.
//
// Nothing we send to Storage is ever Spanish copy of ours, so anything with a
// statusCode we do not recognise still gets a generic Spanish message rather
// than whatever English the API chose.
const STORAGE_MESSAGES: Record<string, string> = {
	'403': 'No tienes permiso para subir esa imagen.',
	'409': 'Ya existe una imagen con ese nombre. Intenta de nuevo.',
	'413': 'La imagen es muy pesada. Intenta con una más pequeña.',
	'415': 'Ese formato de imagen no es compatible.'
};
const STORAGE_FALLBACK = 'No se pudo subir la imagen. Intenta de nuevo.';

/**
 * Extract a human-readable message from a Supabase/JS error (or string) and
 * surface it as an error toast. Returns the message shown.
 */
export function reportError(err: unknown, fallback = 'Algo salió mal. Intenta de nuevo.') {
	let message = fallback;
	if (typeof err === 'string' && err.trim()) {
		message = err;
	} else if (err && typeof err === 'object') {
		const code = (err as { code?: unknown }).code;
		// The code wins over the message: a Postgres-generated message is
		// developer-shaped English, while our own raised messages carry no code
		// we map and fall through to the text, which is already Spanish.
		const statusCode = (err as { statusCode?: unknown }).statusCode;
		if (typeof code === 'string' && DB_MESSAGES[code]) {
			message = DB_MESSAGES[code];
		} else if (typeof statusCode === 'string') {
			message = STORAGE_MESSAGES[statusCode] ?? STORAGE_FALLBACK;
		} else if ('message' in err) {
			const m = (err as { message?: unknown }).message;
			if (typeof m === 'string' && m.trim()) message = m;
		}
	}
	toastError(message);
	return message;
}
