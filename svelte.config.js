import adapter from '@sveltejs/adapter-auto';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Consult https://svelte.dev/docs/kit/integrations
	// for more information about preprocessors
	preprocess: vitePreprocess(),

	kit: {
		// adapter-auto only supports some environments, see https://svelte.dev/docs/kit/adapter-auto for a list.
		// If your environment is not supported, or you settled on a specific environment, switch out the adapter.
		// See https://svelte.dev/docs/kit/adapters for more information about adapters.
		adapter: adapter(),

		// Absolute asset paths (`/_app/...`) instead of SvelteKit's default
		// relative ones (`./` or `../`, chosen per route depth).
		//
		// Required by the service worker (#103). With relative paths the shell
		// HTML differs by how deep the route is — `/songs` ships `./_app/...`
		// while `/parties/25` ships `../_app/...` and computes
		// `base: new URL("..", location)`. The worker caches ONE shell as the
		// offline fallback, so a shell captured at one depth and replayed at
		// another resolves its entry chunks against the wrong directory and the
		// app never boots.
		//
		// Safe here because the app is served from the domain root
		// (rockthehouse.app) and `base` is empty. Only a subpath deploy would
		// need the relative form.
		paths: { relative: false }
	}
};

export default config;
