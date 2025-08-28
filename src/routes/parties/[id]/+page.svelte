<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ArrowLeft } from 'lucide-svelte';

  let party: any = null;
  let venue: any = null;
  let performances: any[] = [];
  let songs: any[] = [];
  let users: any[] = [];
  let loading = true;
  let error: string | null = null;
  let loadingPerformances = true;
  let errorPerformances: string | null = null;

  onMount(async () => {
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
      const { data: perfData, error: perfErr } = await supabase.from('performance').select('id, song, suggested_by, ref_link, key').eq('party', id);
      if (perfErr) {
        errorPerformances = perfErr.message;
      } else {
        performances = perfData ?? [];
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
          {#each performances as perf}
            <li class="bg-white rounded shadow px-4 p-2">
              <a href={`/performance/${perf.id}`} class="block">
                <h4 class="text-lg font-semibold mb-1">{getSongTitle(perf.song)}</h4>
                <div class="text-xs text-slate-500 mb-1">Sugerido por: {getUserNickname(perf.suggested_by)}</div>
                {#if perf.key}
                  <div class="mb-1">Tonalidad: {perf.key}</div>
                {/if}
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
