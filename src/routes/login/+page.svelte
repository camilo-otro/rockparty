<script>
  import { supabase } from '$lib/supabaseClient'

/**
 * Initiates the sign-in process using Google as the OAuth provider.
 * Utilizes Supabase authentication to handle the OAuth flow.
 * 
 * @async
 * @function
 * @returns {Promise<void>} Resolves when the sign-in process is complete.
 * @throws Will throw an error if the authentication process fails.
 */
  async function signInWithGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
  })
}
</script>

<h1>Sign In</h1>
<!-- svelte-ignore a11y_invalid_attribute -->
<a href="#" on:click|preventDefault={signInWithGoogle}>
  Sign in with Google
</a>