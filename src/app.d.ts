// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		interface Locals {
			session?: any;
			supabase?: any;
		}
		// interface PageData {}
		// Shallow-routing state (#94). `perfId` is set by pushState on the party
		// detail page to render a song as an overlay without unmounting the page.
		interface PageState {
			perfId?: number;
		}
		// interface Platform {}
	}
}

export {};
