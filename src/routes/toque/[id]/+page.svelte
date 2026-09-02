<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { MapPin, Music, Users, PartyPopper, Share2, Copy, Check, ArrowRight } from 'lucide-svelte';
  import { user } from '$lib/stores/user';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';

  export let data;
  // Toque + counts come from the server load (+page.ts) so crawlers get real
  // per-event Open Graph tags; the interactive bits (RSVP, share) stay
  // client-side below.
  $: party = data.party;
  $: venue = data.venue;
  $: songs = (data.songs ?? []) as string[];
  $: songCount = data.songCount as number;
  $: musicianCount = data.musicianCount as number;

  let rsvpCount = data.rsvpCount ?? 0; // seeded from load; mutated on RSVP toggle
  let copied = false;
  let currentUserId: string | null = null;
  let iAmGoing = false;
  let rsvpBusy = false;

  // Canonical flyer URL — resolves server-side too (for og:url) via page.url.
  $: shareUrl = `${page.url.origin}${page.url.pathname}`;
  $: dateLong = party?.date ? dayjs(party.date).locale('es').format('dddd D [de] MMMM, YYYY') : '';
  // Only a real, non-test toque gets its own preview; anything RLS-hidden (null
  // server-side for a crawler) or test data falls back to the generic brand card.
  $: publicPreview = !!party && !party.is_test;
  $: ogTitle = publicPreview && party ? (party.title ?? 'Rock the House') : 'Rock the House';
  $: ogDesc = publicPreview && party
    ? [dayjs(party.date).locale('es').format('ddd D [de] MMMM'), venue?.name].filter(Boolean).join(' · ')
    : 'Organiza toques y jam sessions con otros músicos.';

  onMount(async () => {
    user.subscribe((u) => { currentUserId = u?.id ?? null; })();
    if (!party?.id || !currentUserId) return;
    const { data: mine } = await supabase
      .from('party_rsvp').select('user_id').eq('party_id', party.id).eq('user_id', currentUserId).maybeSingle();
    iAmGoing = !!mine;
    // Complete a pending RSVP after the login round-trip (?rsvp=1), then clean
    // the param so a refresh doesn't re-trigger it.
    const params = new URLSearchParams(location.search);
    if (params.get('rsvp') === '1') {
      if (!iAmGoing) await doRsvp(true);
      history.replaceState({}, '', location.pathname);
    }
  });

  function rsvpClick() {
    if (rsvpBusy) return;
    if (!currentUserId) {
      // Log in, return to this flyer, and auto-RSVP on the way back.
      supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: `${location.origin}${location.pathname}?rsvp=1` }
      });
      return;
    }
    doRsvp(!iAmGoing);
  }
  async function doRsvp(going: boolean) {
    if (!currentUserId || !party?.id || rsvpBusy) return;
    rsvpBusy = true;
    try {
      if (going) {
        const { error } = await supabase.from('party_rsvp').insert({ party_id: party.id, user_id: currentUserId });
        if (!error) { iAmGoing = true; rsvpCount += 1; }
      } else {
        const { error } = await supabase.from('party_rsvp').delete().eq('party_id', party.id).eq('user_id', currentUserId);
        if (!error) { iAmGoing = false; rsvpCount = Math.max(0, rsvpCount - 1); }
      }
    } finally {
      rsvpBusy = false;
    }
  }

  function shareWhatsApp() {
    const lines = [
      `🎸 ${party?.title ?? 'Toque'}`,
      [dayjs(party?.date).locale('es').format('ddd D [de] MMM'), venue?.name].filter(Boolean).join(' · '),
      shareUrl
    ].filter(Boolean);
    window.open(`https://wa.me/?text=${encodeURIComponent(lines.join('\n'))}`, '_blank');
  }
  function copyLink() {
    navigator.clipboard.writeText(shareUrl).then(() => {
      copied = true;
      setTimeout(() => (copied = false), 2000);
    });
  }
</script>

<!-- Per-event Open Graph, rendered server-side (ssr=true in +page.ts) so social
     crawlers get the real title/preview. RLS-hidden/test toques → generic card. -->
<svelte:head>
  <title>{publicPreview && party ? `${ogTitle} · Rock the House` : 'Rock the House'}</title>
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

<div class="max-w-xl mx-auto px-4 py-6 flex flex-col gap-4">
  {#if !party}
    <div class="bg-base-900 rounded-lg p-8 text-center flex flex-col gap-2">
      <p class="text-white text-lg">Este toque no está disponible.</p>
      <p class="text-cold-light text-sm">Puede ser privado, un borrador, o el enlace es incorrecto.</p>
      <a href="/" class="text-cold-light hover:text-white mt-2">Ir al inicio</a>
    </div>
  {:else}
    <!-- Poster: a bold brand-gradient banner is the flyer's face. -->
    <div class="rounded-2xl overflow-hidden shadow-lg">
      <div class="relative p-7 pt-16 text-white" style="background:linear-gradient(150deg,#6C04FF 0%,#71118E 55%,#FF4000 100%)">
        <div class="absolute top-4 left-5 text-xs uppercase tracking-[0.25em] text-white/80">Rock the House</div>
        {#if party.is_test}
          <span class="absolute top-4 right-5 text-[0.6rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-white/60 text-white/90">Prueba</span>
        {/if}
        <h1 class="text-4xl leading-tight font-medium" style="text-wrap:balance">{party.title}</h1>
        <p class="mt-2 text-lg text-white/90 first-letter:uppercase">{dateLong}</p>
      </div>
      <div class="bg-base-900 p-6 flex flex-col gap-5">
        {#if venue}
          <div class="flex items-start gap-2 text-white">
            <MapPin size={20} class="text-yellow shrink-0 mt-0.5" />
            <div>
              <div class="text-lg leading-tight">{venue.name}</div>
              {#if venue.address}<div class="text-sm text-cold-light">{venue.address}</div>{/if}
            </div>
          </div>
        {/if}

        {#if party.description}
          <p class="text-white/90 leading-snug">{party.description}</p>
        {/if}

        <!-- Stat row: social proof composed from the event data. -->
        <div class="grid grid-cols-3 gap-2 text-center">
          <div class="bg-base-950 rounded-lg py-3">
            <Music size={18} class="text-cold-light mx-auto" />
            <div class="text-2xl text-white leading-none mt-1">{songCount}</div>
            <div class="text-[0.7rem] uppercase tracking-wide text-cold-light mt-1">Canciones</div>
          </div>
          <div class="bg-base-950 rounded-lg py-3">
            <Users size={18} class="text-cold-light mx-auto" />
            <div class="text-2xl text-white leading-none mt-1">{musicianCount}</div>
            <div class="text-[0.7rem] uppercase tracking-wide text-cold-light mt-1">Músicos</div>
          </div>
          <div class="bg-base-950 rounded-lg py-3">
            <PartyPopper size={18} class="text-cold-light mx-auto" />
            <div class="text-2xl text-white leading-none mt-1">{rsvpCount}</div>
            <div class="text-[0.7rem] uppercase tracking-wide text-cold-light mt-1">Asisten</div>
          </div>
        </div>

        {#if songs.length}
          <div>
            <div class="text-xs uppercase tracking-wide text-cold-light mb-1">En el setlist</div>
            <p class="text-white/90 text-sm leading-snug">
              {songs.join(' · ')}{songCount > songs.length ? ` +${songCount - songs.length} más` : ''}
            </p>
          </div>
        {/if}
      </div>
    </div>

    <!-- Primary conversions — musicians first (play), then attend. -->
    <div class="flex flex-col gap-2">
      <a href={`/parties/${party.id}`}
        class="bg-cold-base text-white hover:bg-cold-light hover:text-black rounded-lg px-5 py-3 text-lg inline-flex items-center justify-center gap-2 transition">
        <Music size={20} /> Quiero tocar
      </a>
      <button on:click={rsvpClick} disabled={rsvpBusy}
        class="{iAmGoing ? 'border-2 border-cold-base text-cold-light' : 'border-2 border-cold-light/50 text-cold-light hover:border-cold-light hover:text-white'} rounded-lg px-5 py-[10px] text-lg inline-flex items-center justify-center gap-2 transition disabled:opacity-60">
        {#if iAmGoing}<Check size={20} /> Vas a asistir{:else}<PartyPopper size={20} /> Voy a este toque{/if}
      </button>
    </div>

    <!-- Share is secondary — for spreading the flyer. -->
    <div class="flex flex-col gap-2 pt-1">
      <div class="text-center text-xs uppercase tracking-wide text-cold-light">Compártelo</div>
      <div class="flex gap-2">
        <button on:click={shareWhatsApp} class="flex-1 border border-cold-light/40 text-cold-light hover:text-white hover:border-cold-light rounded-lg px-4 py-2 text-sm inline-flex items-center justify-center gap-2 transition">
          <Share2 size={16} /> WhatsApp
        </button>
        <button on:click={copyLink} class="flex-1 border border-cold-light/40 text-cold-light hover:text-white hover:border-cold-light rounded-lg px-4 py-2 text-sm inline-flex items-center justify-center gap-2 transition">
          {#if copied}<Check size={16} /> ¡Copiado!{:else}<Copy size={16} /> Copiar{/if}
        </button>
      </div>
    </div>

    <a href={`/parties/${party.id}`} class="text-cold-light/70 hover:text-white text-sm inline-flex items-center justify-center gap-1 py-1">
      Ver setlist y detalles <ArrowRight size={15} />
    </a>
  {/if}
</div>
