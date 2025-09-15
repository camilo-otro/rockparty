<!-- SongSelect.svelte -->
<script lang="ts">
  export let songs: any[] = [];
  export let value: string = '';
  export let selectedSongId: string = '';
  export let error: string = '';
  
  let isOpen = false;
  let inputRef: HTMLInputElement;
  let filteredSongs: any[] = [];
  
  $: {
    if (value) {
      filteredSongs = songs.filter(song => 
        song.title.toLowerCase().includes(value.toLowerCase()) ||
        song.artist.toLowerCase().includes(value.toLowerCase())
      );
    } else {
      filteredSongs = songs;
    }
  }
  
  function handleFocus() {
    isOpen = true;
    if (!value) {
      filteredSongs = songs;
    }
  }
  
  function handleBlur() {
    // Delay closing to allow for clicks on options
    setTimeout(() => {
      isOpen = false;
      validateSelection();
    }, 150);
  }
  
  function selectSong(song: any) {
    value = `${song.title} - ${song.artist}`;
    selectedSongId = song.id;
    error = '';
    isOpen = false;
    inputRef.blur();
  }
  
  function validateSelection() {
    const inputTitle = value.split(' - ')[0].trim();
    const found = songs.find(s => s.title === inputTitle);
    selectedSongId = found ? found.id : '';
    error = found ? '' : 'La canción aún no ha sido agregada a la app.';
  }
  
  function handleInput() {
    selectedSongId = '';
    error = '';
  }
</script>

<div class="relative">
  <input
    bind:this={inputRef}
    bind:value
    on:focus={handleFocus}
    on:blur={handleBlur}
    on:input={handleInput}
    class="w-full p-2 border rounded {error ? 'border-red-500' : ''}"
    placeholder="Buscar canción..."
    autocomplete="off"
  />
  
  {#if isOpen && filteredSongs.length > 0}
    <div class="absolute z-10 w-full mt-1 bg-base-950 border rounded shadow-lg max-h-60 overflow-y-auto">
      {#each filteredSongs as song}
        <button
          type="button"
          class="w-full text-left p-3 hover:bg-base-900 border-b last:border-b-0"
          on:mousedown={() => selectSong(song)}
        >
          <div class="font-medium">{song.title}</div>
          <div class="text-sm text-yellow">{song.artist}</div>
        </button>
      {/each}
    </div>
  {/if}
</div>