<script lang="ts">
  import { fetchSongTitles, fetchArtistNames } from '$lib/musicbrainz';
  
  let songQuery = '';
  let artistQuery = '';
  let songResults: string[] = [];
  let artistResults: string[] = [];
  let searchingSongs = false;
  let searchingArtists = false;
  
  async function searchSongs() {
    if (!songQuery.trim()) {
      songResults = [];
      return;
    }
    searchingSongs = true;
    songResults = (await fetchSongTitles(songQuery)).slice(0, 5);
    searchingSongs = false;
  }
  
  async function searchArtists() {
    if (!artistQuery.trim()) {
      artistResults = [];
      return;
    }
    searchingArtists = true;
    artistResults = (await fetchArtistNames(artistQuery)).slice(0, 5);
    searchingArtists = false;
  }
</script>

<div class="max-w-2xl mx-auto mt-8 p-6">
  <h1 class="text-2xl font-bold mb-8">Test Search Forms (MusicBrainz)</h1>
  
  <!-- Song Search Form -->
  <div class="mb-8">
    <h2 class="text-xl font-semibold mb-4">Search Songs</h2>
    <form on:submit|preventDefault={searchSongs}>
      <input 
        type="text" 
        bind:value={songQuery} 
        placeholder="Search for songs..." 
        class="w-full p-3 border rounded-lg"
      />
      <button type="submit" class="mt-2 px-4 py-2 bg-slate-700 text-slate-200 rounded-lg">Buscar</button>
    </form>
    
    {#if searchingSongs}
      <div class="mt-4 text-gray-600">Searching...</div>
    {:else if songResults.length > 0}
      <div class="mt-4">
        <h3 class="font-medium mb-2">Song Results:</h3>
        <ul class="space-y-2">
          {#each songResults as title}
            <li class="p-3 bg-slate-100 rounded-lg">
              <div class="font-medium">{title}</div>
            </li>
          {/each}
        </ul>
      </div>
    {:else if songQuery.trim()}
      <div class="mt-4 text-gray-600">No songs found</div>
    {/if}
  </div>
  
  <!-- Artist Search Form -->
  <div class="mb-8">
    <h2 class="text-xl font-semibold mb-4">Search Artists</h2>
    <form on:submit|preventDefault={searchArtists}>
      <input 
        type="text" 
        bind:value={artistQuery} 
        placeholder="Search for artists..." 
        class="w-full p-3 border rounded-lg"
      />
      <button type="submit" class="mt-2 px-4 py-2 bg-slate-700 text-slate-200 rounded-lg">Buscar</button>
    </form>
    
    {#if searchingArtists}
      <div class="mt-4 text-gray-600">Searching...</div>
    {:else if artistResults.length > 0}
      <div class="mt-4">
        <h3 class="font-medium mb-2">Artist Results:</h3>
        <ul class="space-y-2">
          {#each artistResults as artist}
            <li class="p-3 bg-slate-100 rounded-lg">
              <div class="font-medium">{artist}</div>
            </li>
          {/each}
        </ul>
      </div>
    {:else if artistQuery.trim()}
      <div class="mt-4 text-gray-600">No artists found</div>
    {/if}
  </div>
  
  <a href="/" class="text-blue-600 hover:underline">&larr; Back to home</a>
</div>