<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fade, fly } from 'svelte/transition';
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    let submitting = false;
    let venues: any[] = [];
    let loadingVenues = true;
    let errorVenues: string | null = null;
    let userId: string | null = null;
    let date = '';
    let selectedVenue = '';
    let success = false;
    let error = '';

    onMount(async () => {
        userId = get(user)?.id ?? null;
        const { data, error } = await supabase.from('venue').select('id, name');
        if (error) {
            errorVenues = error.message;
        } else {
            venues = data ?? [];
        }
        loadingVenues = false;
    });

    async function handleSubmit() {
        if (!date || !selectedVenue) {
            error = 'All fields are required.';
            return;
        }
        
        submitting = true;
        error = '';
        
        try {
            const { data, error: dbError } = await supabase
                .from('party')
                .insert([{ date, venue: selectedVenue, suggested_by: userId }])
                .select();
                
            if (dbError) {
                error = `Database error: ${dbError.message}`;
            } else {
                success = true;
                setTimeout(() => {
                    window.location.href = '/parties';
                }, 1000);
            }
        } catch (e) {
            error = 'Could not connect to the server.';
        }
        
        submitting = false;
    }
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVA FIESTA</h2>
    <a href="/parties" class="text-lg text-bold text-slate-700"><ArrowLeft/></a>
</div>
{#if !success && !error}
<form on:submit|preventDefault={handleSubmit}>
    <div class="flex flex-col w-3/4 p-5 mb-4">
        <label for="date" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Fecha</label>
        <input id="date" type="date" bind:value={date} required class="p-2 border rounded" in:fly={{ y: -30, duration: 400 }} />
        <label for="venue" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Venue</label>
        {#if loadingVenues}
          <div class="text-slate-600">Cargando venues...</div>
        {:else if errorVenues}
          <div class="text-red-600">Error: {errorVenues}</div>
        {:else}
          <select id="venue" bind:value={selectedVenue} required class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }}>
            <option value="" disabled selected>Selecciona un venue</option>
            {#each venues as venue}
              <option value={venue.id}>{venue.name}</option>
            {/each}
          </select>
        {/if}
    </div>
    <button class="bg-slate-700 text-slate-200 rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 100 }}>
        {submitting ? 'Creando...' : 'Crear Fiesta'}
    </button>
</form>
{/if}
{#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nueva Fiesta Creada!
    </div>
{/if}
{#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
{/if}
