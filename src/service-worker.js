/// <reference types="@sveltejs/kit" />
import { build, files, version } from '$service-worker';

// Offline app shell (#103). SvelteKit registers this file automatically in a
// production build; it does nothing in `pnpm run dev`.
//
// The whole point is a home-screen launch that opens instantly and does not show
// the browser's offline dinosaur on a bad connection at a venue. It is NOT an
// offline mode: every piece of data still comes from Supabase over the network.
// What is cached is the shell — the JS, CSS and static assets — so the app
// paints, and then tells you it cannot reach the server.

const CACHE = `rockthehouse-${version}`;

// `build` is the hashed JS/CSS (immutable, safe to cache forever). `files` is
// static/. Two of those are big and are only ever read by a crawler or a link we
// hand out by hand, so precaching them would cost every installer ~275 KB for
// nothing.
const SKIP_FILES = new Set(['/og-default.png', '/roadmap.html']);
const ASSETS = [...build, ...files.filter((f) => !SKIP_FILES.has(f))];
const ASSET_PATHS = new Set(ASSETS);

// The navigation fallback. One entry, not one per route: with `ssr = false`
// (#48) every route returns the same empty shell and the client router takes it
// from there, so caching `/parties`, `/parties/25`, `/performance/125`… would
// store N copies of one document and grow without bound.
const SHELL = '/';

// ---------------------------------------------------------------------------
// The routes this service worker must keep its hands off.
//
// `/flyer/[id]` (#68), `/invite/[id]` (#111) and `/toque/[id]` are the ONLY
// server-rendered routes in the app — they set `ssr = true`, overriding the
// layout. They exist so WhatsApp, Facebook and Google get real per-event Open
// Graph tags. Serving them from cache would break that in two ways that are both
// invisible until someone complains:
//
//   1. The generic app shell has no og:title/og:image, so a shared link would
//      preview as nothing.
//   2. A cached page would show a stranger a stale event — old date, old lineup,
//      a spot that has since been filled, or a toque that has been cancelled.
//
// Any new public, server-rendered, per-event route belongs in this list.
//
// Crawlers never run a service worker, so this only affects a human who opens a
// shared link in an installed app. That is exactly the person who must see the
// live page. Bypass entirely: no cache read, no cache write.
// ---------------------------------------------------------------------------
const ALWAYS_FRESH = /^\/(flyer|invite|toque)\//;

self.addEventListener('install', (event) => {
	event.waitUntil(
		(async () => {
			const cache = await caches.open(CACHE);
			await cache.addAll(ASSETS);
			// Best-effort: without it the first offline launch has no document to
			// fall back to. A failure here must not fail the install.
			try {
				const shell = await fetch(SHELL, { cache: 'reload' });
				if (shell.ok) await cache.put(SHELL, shell);
			} catch {
				// offline at install time — the next successful navigation fills it in
			}
			await self.skipWaiting();
		})()
	);
});

self.addEventListener('activate', (event) => {
	event.waitUntil(
		(async () => {
			for (const key of await caches.keys()) {
				if (key !== CACHE) await caches.delete(key);
			}
			await self.clients.claim();
		})()
	);
});

self.addEventListener('fetch', (event) => {
	const { request } = event;

	// Never touch writes, and never touch anything that is not ours: Supabase
	// (REST, Realtime, Storage), the Google avatar CDN and the Spotify metadata
	// all live on other origins and must go straight to the network.
	if (request.method !== 'GET') return;

	const url = new URL(request.url);
	if (url.origin !== self.location.origin) return;
	if (ALWAYS_FRESH.test(url.pathname)) return;

	// Hashed build output and static files: cache-first. The filename changes when
	// the content does, so a hit is always correct.
	if (ASSET_PATHS.has(url.pathname)) {
		event.respondWith(
			(async () => {
				// Scoped to CACHE: between a new worker's install and its activate both
				// caches exist, and an unscoped match could answer from the old one.
				const hit = await caches.match(url.pathname, { cacheName: CACHE });
				return hit ?? fetch(request);
			})()
		);
		return;
	}

	// Documents: network-first, so a reachable server always wins and a deploy is
	// picked up on the next launch. The cache is only there for the offline case.
	if (request.mode === 'navigate') {
		event.respondWith(
			(async () => {
				try {
					const response = await fetch(request);
					if (response.ok) {
						const cache = await caches.open(CACHE);
						await cache.put(SHELL, response.clone());
					}
					return response;
				} catch {
					const hit = await caches.match(SHELL, { cacheName: CACHE });
					if (hit) return hit;
					throw new Error('offline and no cached shell');
				}
			})()
		);
	}

	// Anything else same-origin falls through to the network untouched.
});
