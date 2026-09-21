<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { PartyPopper, Check, LogIn, MapPin } from 'lucide-svelte';
  import { reportError, toastSuccess } from '$lib/stores/toasts';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';

  // Accept an invitation to a private toque (#113 part B). Mirrors the band
  // claim link (#79) deliberately — same shape, same RPC names, because it is
  // the same problem: the scene runs on WhatsApp, and an invite that requires an
  // account before you can send it never gets sent.
  //
  // The token in the URL IS the credential. Whoever holds this link was sent it,
  // and that is the consent.
  const token = page.params.token;

  let loading = true;
  let claiming = false;
  // null once loaded = unknown OR revoked token. peek_party_invite cannot tell
  // those apart on purpose, so neither can this page — and neither can someone
  // guessing.
  let preview: {
    party_id: number;
    title: string | null;
    party_date: string | null;
    venue_name: string | null;
    venue_area: string | null;
    is_test: boolean;
  } | null = null;
  let currentUserId: string | null = null;
  let unsubscribeUser: () => void;

  onMount(async () => {
    unsubscribeUser = user.subscribe((u) => { currentUserId = u?.id ?? null; });
    // peek is granted to anon, so a signed-out visitor sees WHAT they are being
    // invited to before deciding to create an account.
    const { data } = await supabase.rpc('peek_party_invite', { p_token: token });
    preview = ((data as any[]) ?? [])[0] ?? null;
    loading = false;
  });

  // Not returned from the async onMount: that returns a Promise, which Svelte
  // will not call as a cleanup function.
  onDestroy(() => unsubscribeUser?.());

  function loginWithGoogle() {
    // Back to this same URL signed in — the flyer's ?rsvp=1 flow is the
    // precedent for surviving the OAuth round trip.
    supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.href }
    });
  }

  async function claim() {
    if (claiming) return;
    claiming = true;
    const { data, error } = await supabase.rpc('claim_party_invite', { p_token: token });
    if (error) {
      // A link can go stale between peek and claim — an organiser regenerating
      // it is exactly the "this got out" remedy. Re-peek so the page stops
      // claiming something that is no longer true.
      reportError(error);
      const { data: again } = await supabase.rpc('peek_party_invite', { p_token: token });
      preview = ((again as any[]) ?? [])[0] ?? null;
      claiming = false;
      return;
    }
    toastSuccess('¡Listo! Ya puedes ver el toque.');
    goto(`/parties/${data}`);
  }
</script>

<svelte:head><title>Te invitaron a un toque · Rock the House</title></svelte:head>

<div class="p-4 max-w-md mx-auto">
  {#if loading}
    <div class="mt-8 p-6 bg-base-900 text-white rounded-lg text-center">Cargando…</div>

  {:else if !preview}
    <!-- Inline, not a toast: a dead end has to stay on screen (see CLAUDE.md on
         page-load errors). Deliberately does not distinguish "never existed"
         from "regenerated". -->
    <div class="mt-8 p-6 bg-base-900 rounded-lg text-center flex flex-col gap-3">
      <h1 class="text-2xl text-yellow">Este enlace ya no sirve</h1>
      <p class="text-white/90">
        Puede que quien organiza el toque haya generado uno nuevo. Pídele que te
        mande el actual.
      </p>
      <a href="/" class="text-cold-light underline">Ir al inicio</a>
    </div>

  {:else}
    <div class="mt-8 p-6 bg-base-900 rounded-lg flex flex-col gap-4">
      <div class="flex items-center gap-2 text-cold-light">
        <PartyPopper size={18} /> <span class="text-sm uppercase tracking-widest">Invitación</span>
      </div>

      <div class="flex items-center gap-2 flex-wrap">
        <h1 class="text-3xl text-yellow leading-tight">{preview.title}</h1>
        {#if preview.is_test}
          <span class="text-[0.65rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-warm-base text-warm-base">Datos de prueba</span>
        {/if}
      </div>

      {#if preview.party_date}
        <p class="text-white/90 first-letter:uppercase">
          {dayjs(preview.party_date).locale('es').format('dddd D [de] MMMM, YYYY')}
        </p>
      {/if}

      <!-- Venue NAME and AREA only. The exact address lives in venue_contact and
           arrives once the invite exists — showing it here would make the invite
           link the leak this whole feature exists to close (#113). -->
      {#if preview.venue_name}
        <div class="flex items-start gap-2 text-white">
          <MapPin size={18} class="text-yellow shrink-0 mt-0.5" />
          <div>
            <div>{preview.venue_name}</div>
            {#if preview.venue_area}<div class="text-sm text-cold-light">{preview.venue_area}</div>{/if}
          </div>
        </div>
      {/if}

      {#if currentUserId}
        <!-- An explicit tap, never a claim on load: a link pasted into a group
             chat gets opened by people it was not meant for, so the tap is the
             consent. -->
        <p class="text-cold-light text-sm">Al aceptar podrás ver el toque y confirmar tu asistencia.</p>
        <div class="flex flex-col gap-2">
          <button type="button" on:click={claim} disabled={claiming}
            class="bg-cold-base text-white rounded-lg px-4 py-3 inline-flex items-center justify-center gap-2 disabled:opacity-60">
            <Check size={18} /> {claiming ? 'Aceptando…' : 'Aceptar invitación'}
          </button>
          <a href="/" class="text-cold-light text-center px-4 py-2">Ahora no</a>
        </div>
      {:else}
        <p class="text-cold-light text-sm">Ingresa para aceptar la invitación y ver el toque.</p>
        <button type="button" on:click={loginWithGoogle}
          class="bg-cold-base text-white rounded-lg px-4 py-3 inline-flex items-center justify-center gap-2">
          <LogIn size={18} /> Ingresar con Google
        </button>
      {/if}
    </div>
  {/if}
</div>
