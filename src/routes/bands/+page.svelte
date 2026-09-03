<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { Plus, ChevronRight, Crown, Users } from 'lucide-svelte';

  let currentUserId: string | null = null;
  let isAuthenticated = false;
  let loading = true;
  let bands: { id: number; name: string; role: string; is_test: boolean; avatar_url: string | null }[] = [];
  let unsub: () => void;

  onMount(async () => {
    unsub = user.subscribe((u) => { currentUserId = u?.id ?? null; isAuthenticated = !!u?.id; });
    if (currentUserId) {
      const { data } = await supabase
        .from('band_member')
        .select('role, band ( id, name, is_test, avatar_url )')
        .eq('user_id', currentUserId);
      bands = (data ?? [])
        .filter((r: any) => r.band)
        .map((r: any) => ({ id: r.band.id, name: r.band.name, role: r.role, is_test: r.band.is_test, avatar_url: r.band.avatar_url }))
        .sort((a, b) => a.name.localeCompare(b.name));
    }
    loading = false;
  });
  onDestroy(() => unsub?.());
</script>

<div class="mt-8 flex flex-col gap-4">
  <section>
    <h2 class="text-3xl text-white m-4 mb-4">TUS BANDAS</h2>
    <div class="m-4 rounded-lg overflow-clip flex flex-col">
      <a href="/bands/create" class="w-full bg-cold-base text-white text-sm block text-center p-2">Crear una banda <Plus class="inline-block" /></a>
      {#if loading}
        <div class="bg-base-900 p-4 text-cold-light">Cargando…</div>
      {:else if !isAuthenticated}
        <div class="bg-base-900 p-6 text-white text-center">Inicia sesión para ver y crear tus bandas.</div>
      {:else if bands.length === 0}
        <div class="bg-base-900 p-6 text-cold-light text-center">Aún no tienes bandas. Crea una para agendarla en toques.</div>
      {:else}
        <ul class="p-0 space-y-[1px]">
          {#each bands as b}
            <a href={`/bands/${b.id}`} class="block">
              <li class="flex flex-row items-center bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-3">
                {#if b.avatar_url}
                  <img src={b.avatar_url} alt={b.name} class="w-8 h-8 rounded-full object-cover mr-3 border border-cold-base" />
                {:else}
                  <Users class="text-cold-light mr-3" size={20} />
                {/if}
                <div class="grow">
                  <div class="text-xl text-yellow flex items-center gap-2">
                    {b.name}
                    {#if b.role === 'manager'}<span class="text-[0.6rem] uppercase tracking-wide px-2 py-0.5 rounded-full bg-cold-base text-white inline-flex items-center gap-1"><Crown size={11} /> Manager</span>{/if}
                    {#if b.is_test}<span class="text-[0.6rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-warm-base text-warm-base">Prueba</span>{/if}
                  </div>
                </div>
                <ChevronRight class="text-yellow" size={28} stroke-width={6} />
              </li>
            </a>
          {/each}
        </ul>
      {/if}
    </div>
  </section>
</div>
