<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { enhance } from '$app/forms';
    import { fade, fly } from 'svelte/transition';
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    export let form;
    let submitting = false;
    let venues: any[] = [];
    let loadingVenues = true;
    let errorVenues: string | null = null;
    let userId: string | null = null;

    onMount(async () => {
        userId = get(user)?.id;
        const { data, error } = await supabase.from('venue').select('id, name');
        if (error) {
            errorVenues = error.message;
        } else {
            venues = data ?? [];
        }
        loadingVenues = false;
    });
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVA FIESTA</h2>
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
    <input type="hidden" name="suggested_by" value={userId} />
    <div class="flex flex-col w-3/4 p-5 mb-4">
        <label for="date" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Fecha</label>
        <input id="date" type="date" name="date" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400 }} />
        <label for="venue" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Venue</label>
        {#if loadingVenues}
          <div class="text-slate-600">Cargando venues...</div>
        {:else if errorVenues}
          <div class="text-red-600">Error: {errorVenues}</div>
        {:else}
          <select id="venue" name="venue" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }}>
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
{#if form?.success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nueva Fiesta Creada!
    </div>
{/if}
{#if form?.error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {form.error}
    </div>
{/if}
