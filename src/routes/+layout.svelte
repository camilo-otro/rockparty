<script lang="ts">
  import { onMount } from 'svelte'
  import { invalidate } from '$app/navigation'
  import "../app.css";
  import { scale, fade } from 'svelte/transition';
  import logo from '$lib/assets/images/Logo.png';
  import Toasts from '$lib/components/Toasts.svelte';
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

  function loginWithGoogle() {
    supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.href }
    });
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

<nav class="bg-base-950 text-slate-200 p-4">
  <div class="max-w-2xl mx-auto flex flex-row gap-4 items-center">
    <div class="basis-3/4">
      <a href="/" class="">
        <img src={logo} alt="Rock Party Logo" class="h-20 w-auto" />
      </a>
    </div>
    {#if session}
      <div class="relative basis-1/4 flex justify-end items-center gap-4">
        <img src={session.user?.user_metadata?.avatar_url && session.user.user_metadata.avatar_url.trim() !== '' ? session.user.user_metadata.avatar_url : '/images/avatar-default.svg'} alt="User Avatar" class="w-8 h-8 mx-3 rounded-full cursor-pointer ring-2 ring-yellow ring-offset-2 ring-offset-base-950" on:click={toggleMenu} />
        {#if showMenu}
          <div bind:this={menuRef} class="absolute right-0 top-full w-40 bg-base-900 rounded-lg shadow-lg z-10 overflow-hidden" in:scale={{ duration: 200 }}>
            <a href={`/performers/${session.user.id}`} class="block w-full text-left px-4 py-2 text-white font-medium hover:bg-base-950">Ver mi perfil</a>
            <button class="block w-full text-left px-4 py-2 text-white font-medium hover:bg-base-950" on:click={() => { supabase.auth.signOut(); showMenu = false; }}>Cerrar sesión</button>
          </div>
        {/if}
      </div>
    {:else}
      <button class="bg-cold-base text-white text-sm rounded-full p-2 px-6" on:click={loginWithGoogle}>Ingresar</button>
    {/if}
  </div>
</nav>

<div class="max-w-2xl mx-auto w-full">
  <slot />
</div>

<Toasts />
