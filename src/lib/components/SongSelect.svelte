<!-- SongSelect.svelte -->
<script lang="ts">
  import { createEventDispatcher } from 'svelte';

  export let songs: any[] = [];
  export let value: string = '';
  export let selectedSongId: string = '';
  export let error: string = '';
  // Multi-add mode (#77): a pick emits `select` and clears the box for the next
  // search instead of filling the field. Single-add behavior is the default.
  export let multiAdd: boolean = false;
  // Server-ranked mode (#82): `songs` is already the ranked/filtered result, so
  // don't re-filter it client-side (that would undo cross-field matches).
  export let serverFiltered: boolean = false;

  const dispatch = createEventDispatcher();
  export function focus() { inputRef?.focus(); }

  let isOpen = false;
  let inputRef: HTMLInputElement;
  let filteredSongs: any[] = [];

  $: {
    if (serverFiltered) {
      filteredSongs = songs;
    } else if (value) {
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
      if (!multiAdd) validateSelection(); // multi-add commits on pick, not on blur
    }, 150);
  }
  
  function selectSong(song: any) {
    dispatch('select', song);
    if (multiAdd) {
      // Clear for the next search and keep the box focused for rapid entry.
      value = '';
      selectedSongId = '';
      error = '';
      filteredSongs = songs;
      inputRef.focus();
    } else {
      value = `${song.title} - ${song.artist}`;
      selectedSongId = song.id;
      error = '';
      isOpen = false;
      inputRef.blur();
    }
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
    class="w-full p-2 mb-4 border rounded-lg {error ? 'border-red-500' : ''}"
    placeholder="Buscar canción..."
    autocomplete="off"
  />
  
  {#if isOpen && filteredSongs.length > 0}
    <div class="absolute z-10 w-full mt-1 bg-base-950 border rounded-lg shadow-lg max-h-60 overflow-y-auto">
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