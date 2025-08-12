<script>
  import { onMount } from 'svelte'
  import { invalidate } from '$app/navigation'
  import { User } from 'lucide-svelte';
  import "../app.css";
  export let data

  $: ({ supabase, session } = data)

  onMount(() => {
    const { data } = supabase.auth.onAuthStateChange((event, _session) => {
      if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') {
        invalidate('supabase:auth')
      }
    })

    return () => data.subscription.unsubscribe()
  })
</script>

<nav class="bg-slate-800 text-slate-200 p-4 flex flex-row gap-8">
  <h1 class="text-xl basis-3/4">Rock Party</h1>
  {#if session}
    <p>Welcome, {session.user.email}</p>
    <button on:click={() => supabase.auth.signOut()}>Sign Out</button>
    <User />
  {:else}
    <a href="/login" class="font-bold basis-1/4 text-right">Sign In</a>
  {/if}
</nav>

<slot />
