<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { Users, Check, LogIn } from 'lucide-svelte';
  import { reportError, toastSuccess } from '$lib/stores/toasts';

  // Claim a placeholder band member (#79). The token in the URL is the whole
  // credential: whoever holds this link was sent it by a manager, and that is
  // the consent. No email, nothing sent by us.
  const token = page.params.token;

  let loading = true;
  let claiming = false;
  // null once loaded = unknown OR already-claimed token. peek_band_claim cannot
  // tell those apart on purpose, so neither can this page.
  let preview: { band_id: number; band_name: string; display_name: string; instruments: string[] } | null = null;
  let currentUserId: string | null = null;
  let unsubscribeUser: () => void;

  onMount(async () => {
    unsubscribeUser = user.subscribe((u) => { currentUserId = u?.id ?? null; });
    // peek is granted to anon too, so a signed-out visitor sees what they are
    // being asked to join BEFORE deciding to create an account.
    const { data } = await supabase.rpc('peek_band_claim', { p_token: token });
    preview = (data as any[])?.[0] ?? null;
    loading = false;
  });

  // Not returned from the async onMount above: that returns a Promise, which
  // Svelte will not call as a cleanup function.
  onDestroy(() => unsubscribeUser?.());

  function loginWithGoogle() {
    // Come back to this same URL signed in; the flyer's ?rsvp=1 flow is the
    // precedent for surviving the OAuth round trip.
    supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.href }
    });
  }

  async function claim() {
    if (claiming) return;
    claiming = true;
    const { data, error } = await supabase.rpc('claim_band_member', { p_token: token });
    if (error) {
      // The link can go stale between peek and claim — someone else took it, or
      // a manager regenerated it. Re-peek so the page tells the truth.
      reportError(error);
      const { data: again } = await supabase.rpc('peek_band_claim', { p_token: token });
      preview = (again as any[])?.[0] ?? null;
      claiming = false;
      return;
    }
    toastSuccess(`¡Listo! Ya eres parte de ${preview?.band_name ?? 'la banda'}.`);
    goto(`/bands/${data}`);
  }
</script>

<svelte:head><title>Únete a la banda · Rock the House</title></svelte:head>

<div class="p-4 max-w-md mx-auto">
  {#if loading}
    <div class="mt-8 p-6 bg-base-900 text-white rounded-lg text-center">Cargando…</div>

  {:else if !preview}
    <!-- Inline, not a toast: a dead end needs to stay on screen (see CLAUDE.md
         on page-load errors). Deliberately does not distinguish "never existed"
         from "already claimed". -->
    <div class="mt-8 p-6 bg-base-900 rounded-lg text-center flex flex-col gap-3">
      <h1 class="text-2xl text-yellow">Este enlace ya no sirve</h1>
      <p class="text-white/90">
        Puede que alguien ya lo haya usado, o que el manager haya generado uno nuevo.
        Pídele que te mande otro.
      </p>
      <a href="/" class="text-cold-light underline">Ir al inicio</a>
    </div>

  {:else}
    <div class="mt-8 p-6 bg-base-900 rounded-lg flex flex-col gap-4">
      <div class="flex items-center gap-2 text-cold-light">
        <Users size={18} /> <span class="text-sm uppercase tracking-widest">Invitación</span>
      </div>

      <h1 class="text-3xl text-yellow leading-tight">{preview.band_name}</h1>

      <p class="text-white/90">
        Te agregaron a esta banda como <span class="text-white font-medium">{preview.display_name}</span>{#if preview.instruments.length}, tocando
          <span class="text-white font-medium">{preview.instruments.join(' · ')}</span>{/if}.
      </p>

      {#if currentUserId}
        <!-- An explicit tap, never an automatic claim on load: a link pasted into
             a group chat gets opened by the wrong person, so the tap is the
             consent. -->
        <p class="text-cold-light text-sm">¿Eres tú? Al confirmar quedarás como integrante de la banda.</p>
        <div class="flex flex-col gap-2">
          <button type="button" on:click={claim} disabled={claiming}
            class="bg-cold-base text-white rounded-lg px-4 py-3 inline-flex items-center justify-center gap-2 disabled:opacity-60">
            <Check size={18} /> {claiming ? 'Confirmando…' : 'Sí, soy yo'}
          </button>
          <a href="/" class="text-cold-light text-center px-4 py-2">No soy yo</a>
        </div>
      {:else}
        <p class="text-cold-light text-sm">Ingresa para confirmar que eres tú y unirte a la banda.</p>
        <button type="button" on:click={loginWithGoogle}
          class="bg-cold-base text-white rounded-lg px-4 py-3 inline-flex items-center justify-center gap-2">
          <LogIn size={18} /> Ingresar con Google
        </button>
      {/if}
    </div>
  {/if}
</div>
