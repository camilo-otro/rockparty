<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { enhance } from '$app/forms';
    import { fade, fly } from 'svelte/transition';
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { page } from '$app/state';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    export let form;
    let submitting = false;
    let songs: any[] = [];
    let loadingSongs = true;
    let errorSongs: string | null = null;
    let partyId: string | null = null;
    let userId: string | null = null;

    onMount(async () => {
        partyId =  page.url.searchParams.get('partyId') ?? null;
        console.log('Party ID:', partyId);
        const id = get(user)?.id;
        userId = id??null;
        const { data, error } = await supabase.from('song').select('id, title');
        if (error) {
            errorSongs = error.message;
        } else {
            songs = data ?? [];
        }
        loadingSongs = false;
    });
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVA PERFORMANCE {partyId}</h2>
    <p>Currently at {page.params.length}</p>
    <a href="/parties" class="text-lg text-bold text-slate-700"><ArrowLeft/></a>
</div>
{#if !form?.success && !form?.error}
<form method="POST"
      use:enhance={() => {
        submitting = true;
        return async ({ update }) => {
          await update();
          submitting = false;
        };
      }}>
    <input type="hidden" name="party" value={partyId} />
    <input type="hidden" name="suggested_by" value={userId} />
    <div class="flex flex-col w-3/4 p-5 mb-4">
        <label for="song" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Canción</label>
        {#if loadingSongs}
          <div class="text-slate-600">Cargando canciones...</div>
        {:else if errorSongs}
          <div class="text-red-600">Error: {errorSongs}</div>
        {:else}
          <select id="song" name="song" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }}>
            <option value="" disabled selected>Selecciona una canción</option>
            {#each songs as song}
              <option value={song.id}>{song.title}</option>
            {/each}
          </select>
        {/if}
        <label for="ref_link" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 100 }}>Referencia</label>
        <input id="ref_link" type="text" name="ref_link" class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 100 }} />
        <label for="key" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Tonalidad</label>
        <input id="key" type="text" name="key" class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 150 }} />
    </div>
    <button class="bg-slate-700 text-slate-200 rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 200 }}>
        {submitting ? 'Creando...' : 'Crear Performance'}
    </button>
</form>
{/if}
{#if form?.success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nueva Performance Creada!
    </div>
{/if}
{#if form?.error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {form.error}
    </div>
{/if}
