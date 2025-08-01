<script>
  import { supabase } from '$lib/supabaseClient'

  let email = ''
  let password = ''

/**
 * Attempts to sign in a user using Supabase authentication with the provided email and password.
 * If authentication fails, displays an alert with the error message.
 */
  async function signIn() {
    const { error } = await supabase.auth.signInWithPassword({
      email: email,
      password: password,
    })
    if (error) {
      alert(error.message)
    }
  }
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
<form on:submit|preventDefault={signIn}>
  <label for="email">Email</label>
  <input id="email" type="email" bind:value={email} />
  <label for="password">Password</label>
  <input id="password" type="password" bind:value={password} />
  <button type="submit">Sign In</button>
</form>
<a href="#" on:click|preventDefault={signInWithGoogle}>
  Sign in with Google
</a>