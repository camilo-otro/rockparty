<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ArrowLeft, GripHorizontal } from 'lucide-svelte';
  import { user } from '$lib/stores/user';

  let party: any = null;
  let venue: any = null;
  let performances: any[] = [];
  let songs: any[] = [];
  let users: any[] = [];
  let loading = true;
  let error: string | null = null;
  let loadingPerformances = true;
  let errorPerformances: string | null = null;
  let draggedIndex: number | null = null;
  let dragOverIndex: number | null = null;
  let currentUserId: string | null = null;

  function handleDragStart(e: DragEvent, index: number) {
    draggedIndex = index;
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData('text/html', '');
    }
  }

  function handleDragOver(e: DragEvent, index: number) {
    e.preventDefault();
    dragOverIndex = index;
    if (e.dataTransfer) {
      e.dataTransfer.dropEffect = 'move';
    }
  }

  function handleDragLeave() {
    dragOverIndex = null;
  }

  function handleDrop(e: DragEvent, dropIndex: number) {
    e.preventDefault();
    if (draggedIndex === null || draggedIndex === dropIndex) {
      draggedIndex = null;
      dragOverIndex = null;
      return;
    }

    // Reorder the performances array
    const newPerformances = [...performances];
    const draggedItem = newPerformances[draggedIndex];
    newPerformances.splice(draggedIndex, 1);
    newPerformances.splice(dropIndex, 0, draggedItem);
    
    performances = newPerformances;

    // Update order in database
    updatePerformanceOrder();

    draggedIndex = null;
    dragOverIndex = null;
  }

  async function updatePerformanceOrder(performanceList = performances) {
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

  onMount(async () => {
    currentUserId = get(user)?.id ?? null;
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
          // Assign initial order values
          performanceList.forEach((perf, index) => {
            perf.order = index;
          });
          // Update database with initial order
          await updatePerformanceOrder(performanceList);
        }
        
        // Sort by order after assigning values
        performances = performanceList.sort((a, b) => (a.order || 0) - (b.order || 0));
        // Fetch all songs and users referenced in performances
        const songIds = [...new Set(performances.map(p => p.song))];
        const userIds = [...new Set(performances.map(p => p.suggested_by))];
        const { data: songData } = await supabase.from('song').select('id, title').in('id', songIds);
        const { data: userData } = await supabase.from('user').select('id, nickname').in('id', userIds);
        songs = songData ?? [];
        users = userData ?? [];
      }
      loadingPerformances = false;
    }
    loading = false;
  });

  function getSongTitle(songId: number) {
    const song = songs.find(s => s.id === songId);
    return song ? song.title : 'Sin título';
  }
  function getUserNickname(userId: number) {
    const user = users.find(u => u.id === userId);
    return user ? user.nickname : 'Sin nombre';
  }
</script>

<div class="max-w-xl mx-auto mt-2">
  <div class="flex flex-row items-center">
    <a href="/parties" class="text-lg text-bold text-slate-700 flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> Volver</a>
  </div>
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if party}
    <div class="px-6 p-2 bg-slate-100 rounded shadow">
      <h2 class="text-2xl font-bold mb-2">{party.title}</h2>
      <div class="mb-2 text-slate-700">{party.description}</div>
      <div class="mb-2 text-slate-700">Fecha: {party.date}</div>
      <div class="mb-2 text-slate-700">Lugar: {venue ? venue.name : 'Cargando...'} - {venue ? venue.address : ''}</div>
      <h3 class="text-lg font-semibold mt-4 mb-2">Setlist</h3>
      {#if loadingPerformances}
        <div>Cargando Setlist...</div>
      {:else if errorPerformances}
        <div class="text-red-500">Error: {errorPerformances}</div>
      {:else if performances.length === 0}
        <div>No hay canciones en el Setlist.</div>
      {:else}
        <ul class="mb-4 grid grid-cols-1 gap-2">
          {#each performances as perf, index}
            <li 
              class="bg-white rounded shadow px-4 p-2 transition-all duration-200 {dragOverIndex === index ? 'border-2 border-blue-400 bg-blue-50' : ''} {draggedIndex === index ? 'opacity-50' : ''} {party?.created_by === currentUserId ? 'cursor-move' : ''}"
              draggable={party?.created_by === currentUserId}
              on:dragstart={party?.created_by === currentUserId ? (e) => handleDragStart(e, index) : undefined}
              on:dragover={party?.created_by === currentUserId ? (e) => handleDragOver(e, index) : undefined}
              on:dragleave={party?.created_by === currentUserId ? handleDragLeave : undefined}
              on:drop={party?.created_by === currentUserId ? (e) => handleDrop(e, index) : undefined}
            >
              <a href={`/performance/${perf.id}`} class="block">
                <div class="flex items-center gap-2">
                  <span class="text-gray-400 text-sm font-mono">{index + 1}.</span>
                  <div class="flex-1">
                    <h4 class="text-md font-semibold mb-1">{getSongTitle(perf.song)}</h4>
                    <div class="text-xs text-slate-500 mb-1">Sugerido por: {getUserNickname(perf.suggested_by)}</div>
                    {#if perf.key}
                      <div class="mb-1">Tonalidad: {perf.key}</div>
                    {/if}
                  </div>
                  {#if party?.created_by === currentUserId}
                    <GripHorizontal class="text-gray-400" />
                  {/if}
                </div>
              </a>
            </li>
          {/each}
        </ul>
      {/if}
      <a href={`/performance/create?partyId=${party.id}`} class="bg-slate-700 text-slate-200 rounded p-2 px-4 inline-block mt-2">Sugerir otra cancion</a>
    </div>
    <div class="flex flex-row items-center">
      <a href="/parties" class="text-lg text-bold text-slate-700 flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> Volver</a>
    </div>
  {/if}
</div>
