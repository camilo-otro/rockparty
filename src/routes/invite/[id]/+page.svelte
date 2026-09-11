<script lang="ts">
	import { page } from '$app/state';
	import { Music, MapPin, Calendar, Check, ExternalLink, ArrowRight } from 'lucide-svelte';
	import dayjs from 'dayjs';
	import 'dayjs/locale/es';

	export let data;

	// Everything here comes from the server load (+page.ts) so crawlers get real
	// per-song Open Graph tags. There is deliberately no interactive state: this
	// page recruits, it does not sign anyone up. The signup lives one tap away on
	// /performance/[id], which already handles auth.
	$: song = data.song;
	$: party = data.party;
	$: venue = data.venue;
	$: bandName = data.bandName as string | null;
	$: taken = (data.taken ?? []) as string[];
	$: open = (data.open ?? []) as string[];
	$: perfId = data.performance?.id ?? null;
	$: isBand = !!data.performance?.band_id;
	// False when the instrument lookup failed, which also empties `open`.
	// Without it an outage would tell every visitor the song is full.
	$: lineupKnown = data.lineupKnown !== false;

	// Belt and braces over RLS, mirroring the flyer: RLS already withholds test,
	// draft, pending_venue and cancelled toques from anon, but a preview is cheap
	// to withhold and expensive to get wrong.
	$: publicPreview = !!song && !!party && !party.is_test;

	// The server clock decides this during SSR, so near midnight a visitor in
	// another timezone can see the other wording for a few hours. It only changes
	// copy — never what is shown — so it is not worth a timezone round trip.
	$: isPast = !!party?.date && dayjs(party.date).endOf('day').isBefore(dayjs());
	// A band brings its own lineup (#40): there are no open spots to offer, so the
	// page becomes an announcement with a route to the toque instead of a pitch.
	$: recruiting = publicPreview && !isBand && !isPast && open.length > 0;
	// Only claim a song is full when the lineup is actually known.
	$: isFull = lineupKnown && !isBand && !isPast && open.length === 0;

	$: dateLong = party?.date ? dayjs(party.date).locale('es').format('dddd D [de] MMMM, YYYY') : '';
	// The year only earns its space when it is not the current one — otherwise a
	// 2025 toque and a 2026 one both read "sáb. 7 de nov" in the preview.
	$: dateShort = party?.date
		? dayjs(party.date)
				.locale('es')
				.format(
					dayjs(party.date).year() === dayjs().year() ? 'ddd D [de] MMM' : 'ddd D [de] MMM YYYY'
				)
		: '';

	// "Bajo" -> "Falta Bajo"; "Bajo","Teclado" -> "Faltan Bajo y Teclado". The join
	// is Spanish-shaped rather than a comma list because this string is the whole
	// pull in a WhatsApp preview, where it has to read like a sentence.
	function listEs(items: string[]): string {
		if (items.length <= 1) return items[0] ?? '';
		return `${items.slice(0, -1).join(', ')} y ${items[items.length - 1]}`;
	}
	// Naming the instrument is the pull — "falta bajo" is what makes a bass player
	// tap. But there are only six, so naming them all is what happens when NOBODY
	// has signed up, and "Faltan Voz Lider, Guitarra Lider, Guitarra Ritmica, Bajo,
	// Teclado y Bateria" is a wall that says less than "nobody yet" does. Name them
	// while the list is still a pull; fall back to a count when it stops being one.
	$: openLine =
		taken.length === 0
			? 'Todos los puestos libres'
			: open.length === 1
				? `Falta ${listEs(open)}`
				: open.length <= 4
					? `Faltan ${listEs(open)}`
					: `Faltan ${open.length} puestos`;

	$: shareUrl = `${page.url.origin}${page.url.pathname}`;
	$: ogTitle =
		publicPreview && song
			? [song.title, song.artist].filter(Boolean).join(' · ')
			: 'Rock the House';
	// The lead of the preview: the one fact that decides whether a recipient taps.
	// Null when we have nothing true to say — better a shorter description than a
	// confident wrong one.
	$: statusLine = isBand
		? bandName
			? `La toca ${bandName}`
			: null
		: recruiting
			? openLine
			: isPast
				? 'Ya pasó'
				: isFull
					? 'Ya está completa'
					: null;

	// What a recipient needs in order to decide: is there room for me, and where/when.
	$: ogDesc =
		publicPreview && party
			? [statusLine, party.title, dateShort, venue?.name].filter(Boolean).join(' · ')
			: 'Organiza toques y jam sessions con otros músicos.';
</script>

<!-- Per-song Open Graph, rendered server-side (ssr=true in +page.ts) so the link
     previews in a WhatsApp group instead of arriving as a bare URL. Anything
     RLS-hidden or test falls back to the generic brand card. og:image is the
     shared 1200x630 card for now; #109 covers generated per-event artwork. -->
<svelte:head>
	<title>{publicPreview && song ? `${song.title} · Rock the House` : 'Rock the House'}</title>
	<meta name="description" content={ogDesc} />
	<meta property="og:type" content="article" />
	<meta property="og:site_name" content="Rock the House" />
	<meta property="og:title" content={ogTitle} />
	<meta property="og:description" content={ogDesc} />
	<meta property="og:url" content={shareUrl} />
	<meta property="og:image" content="{page.url.origin}/og-default.png" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content={ogTitle} />
	<meta name="twitter:description" content={ogDesc} />
	<meta name="twitter:image" content="{page.url.origin}/og-default.png" />
</svelte:head>

<div class="mx-auto flex max-w-xl flex-col gap-4 px-4 py-6">
	<!-- `|| !party` is redundant at runtime (publicPreview already requires it) but
	     it is what narrows `party` to non-null for the else branch below. -->
	{#if !publicPreview || !party}
		<div class="flex flex-col gap-2 rounded-lg bg-base-900 p-8 text-center">
			<p class="text-lg text-white">Esta invitación no está disponible.</p>
			<p class="text-sm text-cold-light">
				El toque puede ser privado, un borrador, o el enlace es incorrecto.
			</p>
			<a href="/" class="mt-2 text-cold-light hover:text-white">Ir al inicio</a>
		</div>
	{:else}
		<div class="overflow-hidden rounded-2xl shadow-lg">
			<!-- The song is the largest thing on the page: the question a recipient is
           answering is "do I want to play THAT?", not "what is Rock the House?". -->
			<div
				class="relative p-7 pt-16 text-white"
				style="background:linear-gradient(150deg,#6C04FF 0%,#71118E 55%,#FF4000 100%)"
			>
				<div class="absolute left-5 top-4 text-xs uppercase tracking-[0.25em] text-white/80">
					Rock the House
				</div>
				<div class="mb-2 text-xs uppercase tracking-[0.18em] text-white/80">
					{#if isBand}Suena en este toque{:else if isPast}Se tocó en{:else if recruiting}Te invitan
						a tocar{:else}Se toca en{/if}
				</div>
				<h1 class="text-4xl font-medium leading-tight" style="text-wrap:balance">{song.title}</h1>
				{#if song.artist}<p class="mt-1 text-lg text-white/90">{song.artist}</p>{/if}
			</div>

			<div class="flex flex-col gap-5 bg-base-900 p-6">
				<!-- The toque: where and when this happens. -->
				<div class="flex flex-col gap-2">
					<div class="text-xl leading-tight text-white">{party.title}</div>
					<div class="flex items-center gap-2 text-sm text-cold-light">
						<Calendar size={16} class="shrink-0" />
						<span class="first-letter:uppercase">{dateLong}</span>
					</div>
					{#if venue?.name}
						<div class="flex items-center gap-2 text-sm text-cold-light">
							<MapPin size={16} class="shrink-0 text-yellow" />
							<span>{venue.name}</span>
						</div>
					{/if}
				</div>

				<!-- Instruments, never names. The flyer publishes a musician COUNT and no
             nicknames; this publishes which spots are taken and which are open.
             "Falta bajo" is what a recipient needs — "Yorch is playing guitar" is
             a person-to-event mapping published to anyone with the link, which is
             the thing #102 just finished removing elsewhere. The load never even
             selects user_id. -->
				{#if isBand}
					<div class="rounded-lg bg-base-950 p-4 text-center">
						<p class="text-white">
							{#if bandName}La toca <span class="text-yellow">{bandName}</span>{:else}La toca una
								banda{/if}
						</p>
						<p class="mt-1 text-sm text-cold-light">Esta canción ya tiene su alineación.</p>
					</div>
				{:else if recruiting}
					<div>
						<!-- The pills below already name what is open, so repeating openLine
						     here would be the same list twice, in caps. It earns its keep in
						     the og:description, where there are no pills. -->
						<div class="mb-2 text-xs uppercase tracking-wide text-cold-light">Puestos libres</div>
						<div class="flex flex-wrap gap-2">
							{#each open as name (name)}
								<span class="rounded-lg border border-yellow/60 px-3 py-1 text-sm text-yellow"
									>{name}</span
								>
							{/each}
							{#each taken as name (name)}
								<span
									class="inline-flex items-center gap-1 rounded-lg border border-cold-light/20 px-3 py-1 text-sm text-cold-light/60"
								>
									<Check size={14} />
									{name}
								</span>
							{/each}
						</div>
					</div>
				{:else}
					<div class="rounded-lg bg-base-950 p-4 text-center">
						<p class="text-white">
							{#if isPast}Este toque ya pasó.{:else if isFull}Esta canción ya está completa.{:else}Mira
								el toque para ver qué falta.{/if}
						</p>
						{#if isFull}<p class="mt-1 text-sm text-cold-light">
								Pero el toque tiene más canciones.
							</p>{/if}
					</div>
				{/if}

				{#if song.ref_link}
					<!-- Spotify's Developer Terms require attributing their metadata with
               the Marks and a link back; title/artist here came from the
               spotify-track function (#80), same as the add-song UI. -->
					<a
						href={song.ref_link}
						target="_blank"
						rel="noopener"
						class="inline-flex items-center gap-2 self-start text-sm text-cold-light hover:text-white"
					>
						<img
							src="/images/spotify-logo.svg"
							alt="Spotify"
							class="h-3"
							on:error={(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')}
						/>
						Escúchala en Spotify <ExternalLink size={14} />
					</a>
				{/if}
			</div>
		</div>

		<!-- One CTA. When there is nothing to sign up for the link stays useful by
         pointing at the toque rather than becoming a dead end. -->
		{#if recruiting}
			<a
				href={`/performance/${perfId}`}
				class="inline-flex items-center justify-center gap-2 rounded-lg bg-cold-base px-5 py-3 text-lg text-white transition hover:bg-cold-light hover:text-black"
			>
				<Music size={20} /> Inscríbete para tocar
			</a>
			<a
				href={`/flyer/${party.id}`}
				class="inline-flex items-center justify-center gap-1 py-1 text-sm text-cold-light/70 hover:text-white"
			>
				Ver el toque completo <ArrowRight size={15} />
			</a>
		{:else}
			<a
				href={`/flyer/${party.id}`}
				class="inline-flex items-center justify-center gap-2 rounded-lg bg-cold-base px-5 py-3 text-lg text-white transition hover:bg-cold-light hover:text-black"
			>
				<ArrowRight size={20} /> Ver el toque
			</a>
		{/if}
	{/if}
</div>
