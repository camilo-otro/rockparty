<script lang="ts">
  // Imports
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ArrowLeft, GripHorizontal, Share2 } from 'lucide-svelte';
  import { user } from '$lib/stores/user';
  import Sortable from 'sortablejs';
  import ShareModal from '$lib/components/ShareModal.svelte';

  // State variables
  let party: any = null;
  let venue: any = null;
  let performances: any[] =   [];
  let songs: any[] = [];
  let users: any[] = [];
  let loading = true;
  let error: string | null = null;
  let loadingPerformances = true;
  let errorPerformances: string | null = null;
  let currentUserId: string | null = null;
  let unsubscribeUser: () => void;
  let sortableInstance: Sortable | null = null;
  let sortableList: HTMLElement;
  let showShareModal = false;

  // Derived helpers
  function getSongTitle(songId: number) {
    const song = songs.find(s => s.id === songId);
    return song ? song.title : 'Sin título';
  }
  function getUserNickname(userId: number) {
    const userObj = users.find(u => u.id === userId);
    return userObj ? userObj.nickname : 'Sin nombre';
  }

  // Sortable functionality
  function initializeSortable() {
    if (sortableList && party?.created_by === currentUserId) {
      sortableInstance = new Sortable(sortableList, {
        animation: 150,
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        handle: '.drag-handle',
        delay: 200,
        delayOnTouchOnly: true,
        onEnd: (evt) => {
          if (evt.oldIndex !== undefined && evt.newIndex !== undefined && evt.oldIndex !== evt.newIndex) {
            const newPerformances = [...performances];
            const draggedItem = newPerformances[evt.oldIndex];
            const draggableList = evt.to.children;
            evt.item.onclick = function(event) {
              event.preventDefault();
            }
            updatePerformanceOrder(performances, draggableList);
          }
        }
      });
    }
  }

  function destroySortable() {
    if (sortableInstance) {
      sortableInstance.destroy();
      sortableInstance = null;
    }
  }

  // Async functions
  async function updatePerformanceOrder(performanceList = performances, draggableList: HTMLCollection | null) {
    if(draggableList && draggableList.length>0){
      for(let i = 0; i<draggableList.length; i++){
        const id = Number(draggableList[i].getAttribute('data-id'));
        const perf = performanceList.find(p => p.id === id);
        if (perf?.order !== i) {
          perf.order = i;
          await supabase
            .from('performance')
            .update({ order: i })
            .eq('id', perf.id);
        }
      }
    }
    else {
      for (let i = 0; i < performanceList.length; i++) {
        if (performanceList[i].order !== i) {
          performanceList[i].order = i;
          await supabase
            .from('performance')
            .update({ order: i })
            .eq('id', performanceList[i].id);
        }
      }
    }
    performances = performanceList;
  }

  function handleShare() {
    const url = window.location.href;
    const title = party?.title || 'te invito a esta Rock Party';
    const text = party?.description || '';
    if (navigator.share) {
      navigator.share({ title, text, url });
    } else {
      showShareModal = true;
    }
  }

  function closeShareModal() {
    showShareModal = false;
  }

  // Lifecycle
  onMount(async () => {
    unsubscribeUser = user.subscribe(u => {
      currentUserId = u?.id ?? null;
      // Reinitialize sortable when user changes
      destroySortable();
      setTimeout(initializeSortable, 0);
    });
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('party').select('*').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      party = data;
      if (party?.venue) {
        const { data: venueData, error: venueErr } = await supabase.from('venue').select('name, address').eq('id', party.venue).single();
        if (!venueErr) {
          venue = venueData;
        }
      }
      // Fetch performances for this party
      const { data: perfData, error: perfErr } = await supabase.from('performance').select('id, song, suggested_by, ref_link, key, order').eq('party', id);
      if (perfErr) {
        errorPerformances = perfErr.message;
      } else {
        let performanceList = perfData ?? [];
        // Check if any performance has a null or undefined order
        const hasNullOrder = performanceList.some(perf => perf.order === null || perf.order === undefined);
        if (hasNullOrder) {
          performanceList.forEach((perf, index) => {
            perf.order = index;
          });
          await updatePerformanceOrder(performanceList, null);
        }
        performances = performanceList.sort((a, b) => (a.order || 0) - (b.order || 0));
        // Fetch all songs and users referenced in performances
        const songIds = [...new Set(performances.map(p => p.song))];
        const userIds = [...new Set(performances.map(p => p.suggested_by))];
        const { data: songData } = await supabase.from('song').select('id, title').in('id', songIds);
        const { data: userData } = await supabase.from('user').select('id, nickname').in('id', userIds);
        songs = songData ?? [];
        users = userData ?? [];
        // Initialize sortable after performances are loaded
        setTimeout(initializeSortable, 0);
      }
      loadingPerformances = false;
    }
    loading = false;
  });

  onDestroy(() => {
    destroySortable();
    if (unsubscribeUser) unsubscribeUser();
  });
</script>

<style>
  :global(.sortable-ghost) {
    opacity: 0.4;
  }
  :global(.sortable-chosen) {
    transform: scale(1.02);
  }
  :global(.sortable-drag) {
    transform: rotate(2deg);
  }
  .drag-handle {
    touch-action: none;
  }
</style>

<div class="max-w-xl mx-auto mt-2">
  <a href="/parties" class="text-lg text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> Volver</a>
  {#if loading}
    <div class="text-white p-4">Cargando...</div>
  {:else if error}
    <div class="text-red-500 p-4">Error: {error}</div>
  {:else if party}
    <div class="px-6 p-2 bg-base-900 rounded shadow mx-4">
      <div class="flex flex-row justify-between">
        <h2 class="text-3xl text-yellow font-bold mb-2">{party.title}</h2>
        <button class="ml-auto flex items-center gap-1 bg-cold-base hover:bg-cold-light text-white rounded px-3 py-1" on:click={handleShare} title="Compartir">
          <Share2 size={18} /> Compartir
        </button>
      </div>
      <div class="mb-2 text-white">{party.description}</div>
      <div class="mb-2 text-cold-light">Fecha: {party.date}</div>
      <div class="mb-2 text-cold-light">Lugar: {venue ? venue.name : 'Cargando...'} - {venue ? venue.address : ''}</div>
      <h3 class="text-2xl text-white font-semibold mt-4 mb-2">Setlist</h3>
      {#if loadingPerformances}
        <div class="text-white">Cargando Setlist...</div>
      {:else if errorPerformances}
        <div class="text-red-500">Error: {errorPerformances}</div>
      {:else if performances.length === 0}
        <div class="text-white">No hay canciones en el Setlist.</div>
      {:else}
        <ul bind:this={sortableList} class="mb-4 grid grid-cols-1 gap-2">
          {#each performances as perf, index (perf.id)}
            <li 
              class="bg-cold-base rounded shadow px-4 p-2 transition-all duration-200"
              data-id={perf.id}
            >
              <a href={`/performance/${perf.id}`} class="block">
                <div class="flex items-center gap-2">
                  <span class="text-cold-light text-sm font-mono">{index + 1}.</span>
                  <div class="flex-1">
                    <h4 class="text-md text-yellow font-semibold mb-1">{getSongTitle(perf.song)}</h4>
                    <div class="text-xs text-cold-light mb-1">Sugerido por: {getUserNickname(perf.suggested_by)}</div>
                    {#if perf.key}
                      <div class="mb-1 text-white">Tonalidad: {perf.key}</div>
                    {/if}
                  </div>
                  {#if party?.created_by === currentUserId}
                    <div class="drag-handle cursor-move">
                      <GripHorizontal class="text-cold-light" />
                    </div>
                  {/if}
                </div>
              </a>
            </li>
          {/each}
        </ul>
      {/if}
      <div class="flex flex-row justify-between mb-4">
        <a href={`/performance/create?partyId=${party.id}`} class="bg-cold-base text-white rounded p-2 px-4 inline-block mt-2">Sugerir otra cancion</a>
        <div class="mt-2">
          <button on:click={handleShare} class="bg-yellow text-black rounded p-2 px-4 inline-flex items-center gap-2">
            <Share2 class="w-5 h-5" />
            Compartir
          </button>
        </div>
      </div>
      {#if showShareModal}
        <ShareModal url={window.location.href} title={party?.title} on:close={closeShareModal} />
      {/if}
    </div>
    <div class="flex flex-row items-center">
      <a href="/parties" class="text-lg text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> Volver</a>
    </div>
  {/if}
</div>
