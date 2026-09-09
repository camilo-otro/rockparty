<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ChevronLeft } from 'lucide-svelte';

    let performers: any[] = [];
    let loading = true;
    let error: string | null = null;
    // Profiles are behind a login wall. 'loading' until auth is known so the gate
    // never flashes during session restore.
    //
    // Honest about what this is: a UI gate, not a security boundary. `profile`
    // stays world-readable in RLS, so the data is still reachable with the public
    // key — this stops casual browsing of people, not scraping. Deliberate call:
    // a nickname, an avatar and which toques someone played are low-sensitivity,
    // and restricting RLS would blank out the names on the party and band pages
    // that shared flyers funnel strangers into.
    let authState: 'loading' | 'in' | 'out' = 'loading';

    onMount(async () => {
        const { data: { session } } = await supabase.auth.getSession();
        if (!session?.user) { authState = 'out'; loading = false; return; }
        authState = 'in';
        const { data, error: err } = await supabase.from('profile').select('id, nickname, avatar_url');
        if (err) {
            error = err.message;
        } else {
            performers = data ?? [];
        }
        loading = false;
    });

  function loginWithGoogle() {
    supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.href } });
  }
</script>
<div class="flex flex-col items-left">
    <div class="flex flex-row items-center">
        <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft/>VOLVER</a>
    </div>
    <section>
        <h2 class="text-3xl text-white m-4 mb-4">INTÉRPRETES</h2>

    {#if authState === 'out'}
      <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
        Debes <button type="button" class="text-cold-light underline" on:click={loginWithGoogle}>iniciar sesión</button> para ver los perfiles de los músicos.
      </div>
    {:else}
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
    {/if}
    </section>
    {#if authState !== 'out'}
      <div class="flex justify-center p-4">
        <a class="text-center bg-cold-base text-white w-2/3 p-4 rounded-lg" href="/performers/create">Agregar un intérprete</a>
      </div>
    {/if}
</div>
