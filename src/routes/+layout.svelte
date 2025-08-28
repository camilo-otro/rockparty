<script lang="ts">
  import { onMount } from 'svelte'
  import { invalidate } from '$app/navigation'
  import "../app.css";
  import { scale, fade } from 'svelte/transition';
  export let data

  $: ({ supabase, session } = data)

  let showMenu = false;
  let menuRef: HTMLDivElement | null = null;

  function toggleMenu() {
    showMenu = !showMenu;
  }

  function handleClickOutside(event: MouseEvent) {
    if (showMenu && menuRef && !menuRef.contains(event.target as Node)) {
      showMenu = false;
    }
  }

  onMount(() => {
    const { data } = supabase.auth.onAuthStateChange((event, _session) => {
      if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') {
        invalidate('supabase:auth')
      }
    })

    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      data.subscription.unsubscribe();
      document.removeEventListener('mousedown', handleClickOutside);
    }
  })
</script>

<nav class="bg-slate-800 text-slate-200 p-4 flex flex-row gap-4 items-center">
  <a href="/" class="text-xl basis-3/4 grow px-3 font-bold">Rock Party</a>
  {#if session}
    <div class="relative">
      <img src={session.user?.user_metadata?.avatar_url} alt="User Avatar" class="w-8 h-8 rounded-full mx-3 cursor-pointer object-right" on:click={toggleMenu} />
      {#if showMenu}
        <div bind:this={menuRef} class="absolute right-0 top-full w-40 bg-white rounded shadow-lg z-10" in:scale={{ duration: 200 }}>
          <button class="block w-full text-left px-4 py-2 text-slate-800 hover:bg-slate-100" on:click={() => { supabase.auth.signOut(); showMenu = false; }}>Sign Out</button>
        </div>
      {/if}
    </div>
  {:else}
    <a href="/login" class="font-bold basis-1/4 text-right">Sign In</a>
  {/if}
</nav>

<slot />
