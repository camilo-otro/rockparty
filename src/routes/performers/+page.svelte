<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ChevronLeft } from 'lucide-svelte';

    let performers: any[] = [];
    let loading = true;
    let error: string | null = null;

    onMount(async () => {
        const { data, error: err } = await supabase.from('profile').select('id, nickname, avatar_url');
        if (err) {
            error = err.message;
        } else {
            performers = data ?? [];
        }
        loading = false;
    });
</script>
<div class="flex flex-col items-left">
    <div class="flex flex-row items-center">
        <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft/>VOLVER</a>
    </div>
    <section>
        <h2 class="text-3xl text-white m-4 mb-4">INTÉRPRETES</h2>
        <div class="m-4 rounded-lg overflow-clip flex flex-col">
            {#if loading}
                <div class="text-white p-4">Cargando...</div>
            {:else if error}
                <div class="text-red-500 p-4">Error: {error}</div>
            {:else if performers.length === 0}
                <div class="text-white p-4">No hay ningún intérprete registrado.</div>
            {:else}
                <ul class="p-0 space-y-[1px]">
                    {#each performers as performer}
                        <a href={`/performers/${performer.id}`} class="block">
                            <li class="bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-3 flex flex-row items-center gap-3">
                                <img
                                    src={performer.avatar_url && performer.avatar_url.trim() !== '' ? performer.avatar_url : '/images/avatar-default.svg'}
                                    alt=""
                                    class="w-8 h-8 rounded-full border border-cold-base"
                                />
                                <div class="text-lg text-yellow">{performer.nickname}</div>
                            </li>
                        </a>
                    {/each}
                </ul>
            {/if}
        </div>
    </section>
    <div class="flex justify-center p-4">
        <a class="text-center bg-cold-base text-white w-2/3 p-4 rounded-lg" href="/performers/create">Agregar un intérprete</a>
    </div>
</div>
