<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ArrowLeft } from 'lucide-svelte';
  import { user } from '$lib/stores/user';
  import { Share2 } from 'lucide-svelte';
  import ShareModal from '$lib/components/ShareModal.svelte';

  let performance: any = null;
  let songTitle: string = '';
  let loading = true;
  let error: string | null = null;
  let suggestedBy: any = null;
  let suggestedByAvatar: string = '';
  let showModal = false;
  let instruments: any[] = [];
  let loadingInstruments = false;
  let signedUpUsers: any[] = [];
  let showShareModal = false;

  async function fetchSignedUpUsers(performanceId: string) {
    const { data: perfUsers } = await supabase.from('performance_user').select('user_id, instrument_id').eq('performance_id', performanceId);
    const users: any[] = [];
    for (const perfUser of perfUsers ?? []) {
      const { data: userData } = await supabase.from('profile').select('nickname').eq('id', perfUser.user_id).single();
      const { data: instrumentData } = await supabase.from('instrument').select('name').eq('id', perfUser.instrument_id).single();
      users.push({
        nickname: userData?.nickname ?? perfUser.user_id,
        instrument: instrumentData?.name ?? '',
        user_id: perfUser.user_id
      });
    }
    return users;
  }

  onMount(async () => {
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('performance').select('*').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      performance = data;
      // Fetch song title
      if (performance?.song) {
        const { data: songData } = await supabase.from('song').select('title').eq('id', performance.song).single();
        songTitle = songData?.title ?? '';
      }
      // Fetch suggested by user nickname from user table
      if (performance?.suggested_by) {
        const { data: userData } = await supabase.from('user').select('nickname').eq('id', performance.suggested_by).single();
        suggestedBy = userData;
        // Fetch Google avatar from auth.users
        const { data: authUser } = await supabase.from('auth.users').select('user_metadata').eq('id', performance.suggested_by).single();
        suggestedByAvatar = authUser?.user_metadata?.avatar_url || authUser?.user_metadata?.picture || '';
      }
      // Fetch signed up users for this performance
      signedUpUsers = await fetchSignedUpUsers(id);
    }
    // Fetch instruments once on mount
    const { data: instrumentData } = await supabase.from('instrument').select('id, name');
    instruments = instrumentData ?? [];
    loading = false;
  });

  async function refreshSignedUpUsers() {
    if (!performance?.id) return;
    signedUpUsers = await fetchSignedUpUsers(performance.id);
  }

  function openModal() {
    showModal = true;
  }

  function selectInstrument(instrument: any) {
    const userId = get(user)?.id;
    if (!userId || !performance?.id) {
        showModal = false;
        return;
    }
    supabase.from('performance_user').upsert({
        performance_id: performance.id,
        user_id: userId,
        instrument_id: instrument.id
    }, { onConflict: 'performance_id,user_id' })
    .then(() => {
        showModal = false;
        refreshSignedUpUsers();
    });
  }

  function closeModal() {
    showModal = false;
  }

  function loginWithGoogle() {
    import('$lib/supabaseClient').then(({ supabase }) => {
      supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: window.location.href }
      });
    });
  }

  function handleShare() {
    const url = window.location.href;
    const title = songTitle ? `¡Inscríbete para tocar ${songTitle}!` : '¡Inscríbete para tocar una canción!';
    const text = songTitle ? `Te invito a tocar ${songTitle} en Rock Party.` : 'Te invito a tocar una canción en Rock Party.';
    if (navigator.share) {
      navigator.share({ title, text, url });
    } else {
      showShareModal = true;
    }
  }
  function closeShareModal() {
    showShareModal = false;
  }
</script>

<div class="max-w-xl mx-auto mt-8">
  <div class="mb-4">
    <div class="flex flex-row items-center justify-between">
      <a href="/parties/{performance?.party}" class="text-bold text-slate-700 flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> volve</a>
      <button class="ml-auto flex items-center gap-1 bg-cold-base hover:bg-cold-light text-white rounded px-3 py-1" on:click={handleShare} title="Compartir">
        <Share2 size={18} /> Compartir
      </button>
    </div>
  </div>
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if performance}
    <div class="bg-base-900 rounded shadow mx-4 px-6 p-4">
      <h2 class="text-3xl text-yellow font-bold mb-2">{songTitle}</h2>
      <div class="mb-2 text-cold-light">Sugerido por:
        {#if suggestedByAvatar}
          <img src={suggestedByAvatar} alt="Foto de perfil" class="w-6 h-6 rounded-full inline-block mr-2" />
        {/if}
        <span>{suggestedBy?.nickname ?? performance.suggested_by}</span>
      </div>
      <div class="mb-2 text-cold-light">Tonalidad: {performance.key}</div>
      {#if performance.ref_link}
        <a href={performance.ref_link} target="_blank" class="text-yellow underline">Ver referencia</a>
      {/if}
      <h3 class="text-2xl text-white font-bold mt-6 mb-2">Participantes</h3>
      <ul class="mb-4">
        {#each signedUpUsers as u}
          <li class="mb-2 p-2 bg-cold-base rounded flex gap-2 items-center justify-between">
            <div>
              <span class="font-semibold text-yellow">{u.nickname}</span>
              <span class="text-cold-light">— {u.instrument}</span>
            </div>
            {#if get(user)?.id === u.user_id}
              <button class="bg-cold-base text-white rounded px-3 py-1 ml-2" on:click={openModal}>cambiar</button>
            {/if}
          </li>
        {/each}
        {#if signedUpUsers.length === 0}
          <li class="text-cold-light">Nadie se ha anotado aún.</li>
        {/if}
      </ul>
      {#if get(user)?.id}
        <div class="w-full flex justify-center">
          <button class="bg-yellow text-black rounded p-2 px-4 mb-4" on:click={openModal}>Inscríbete para tocar</button>
        </div>
      {:else}
        <div class="w-full flex justify-center">
          <button class="bg-cold-base text-white rounded p-2 px-4 mb-4" on:click={loginWithGoogle}>Inicia sesión para tocar</button>
        </div>
      {/if}
    </div>
  {/if}
</div>

<!-- Modal -->
{#if showModal}
  <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" on:click={closeModal}>
    <div class="bg-base-900 rounded-lg p-6 max-w-md w-full mx-4" on:click|stopPropagation>
      <h3 class="text-xl text-yellow font-bold mb-4">Selecciona tu instrumento</h3>
      {#if loadingInstruments}
        <div class="text-center text-white">Cargando instrumentos...</div>
      {:else}
        <div class="space-y-2">
          {#each instruments as instrument}
            <button 
              class="w-full text-left p-3 border border-cold-base rounded bg-cold-base text-white hover:bg-cold-light transition active:bg-yellow active:text-black"
              on:mousedown={() => instrument._down = true}
              on:mouseup={() => { instrument._down = false; selectInstrument(instrument); }}
              on:touchstart={() => instrument._down = true}
              on:touchend={() => { instrument._down = false; selectInstrument(instrument); }}
            >
              {instrument.name}
            </button>
          {/each}
        </div>
      {/if}
      <button class="mt-4 px-4 py-2 bg-cold-base text-white rounded hover:bg-cold-light" on:click={closeModal}>Cancelar</button>
    </div>
  </div>
{/if}

<!-- Share Modal -->
{#if showShareModal}
  <ShareModal url={window.location.href} title={songTitle} on:close={closeShareModal} />
{/if}
