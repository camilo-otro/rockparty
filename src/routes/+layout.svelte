<script>
  import { onMount } from 'svelte'
  import { invalidate } from '$app/navigation'

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

<nav>
  {#if session}
    <p>Welcome, {session.user.email}</p>
    <button on:click={() => supabase.auth.signOut()}>Sign Out</button>
  {:else}
    <a href="/login">Sign In</a>
  {/if}
</nav>

<slot />
