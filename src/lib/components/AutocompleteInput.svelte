<!-- AutocompleteInput.svelte -->
<script lang="ts">
  export let value: string = '';
  export let suggestions: string[] = [];
  export let placeholder: string = '';
  export let onInput: (value: string) => void = () => {};
  export let required: boolean = false;
  export let id: string = '';
  export let maxlength: number | undefined = undefined;
  export let ariaLabel: string | undefined = undefined;
  
  let isOpen = false;
  let inputRef: HTMLInputElement;
  let filteredSuggestions: string[] = [];
  
  $: {
    if (value && suggestions.length > 0) {
      filteredSuggestions = suggestions.filter(suggestion => 
        suggestion.toLowerCase().includes(value.toLowerCase())
      );
    } else {
      filteredSuggestions = suggestions;
    }
  }
  
  function handleFocus() {
    isOpen = true;
    if (!value) {
      filteredSuggestions = suggestions;
    }
  }
  
  function handleBlur() {
    // Delay closing to allow for clicks on options
    setTimeout(() => {
      isOpen = false;
    }, 150);
  }
  
  function selectSuggestion(suggestion: string) {
    value = suggestion;
    isOpen = false;
    inputRef.blur();
  }
  
  function handleInput(e: Event) {
    const target = e.target as HTMLInputElement;
    value = target.value;
    onInput(value);
  }
</script>

<div class="relative">
  <input
    {id}
    bind:this={inputRef}
    bind:value
    on:focus={handleFocus}
    on:blur={handleBlur}
    on:input={handleInput}
    {required}
    {placeholder}
    {maxlength}
    aria-label={ariaLabel}
    class="w-full p-2 border rounded-lg"
    autocomplete="off"
  />
  
  {#if isOpen && filteredSuggestions.length > 0}
    <div class="absolute z-10 w-full mt-1 bg-base-950 border rounded-lg shadow-lg max-h-60 overflow-y-auto">
      {#each filteredSuggestions as suggestion}
        <button
          type="button"
          class="w-full text-left p-3 hover:bg-base-900 border-b last:border-b-0"
          on:mousedown={() => selectSuggestion(suggestion)}
        >
          {suggestion}
        </button>
      {/each}
    </div>
  {/if}
</div>