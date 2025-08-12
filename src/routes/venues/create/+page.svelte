<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { enhance } from '$app/forms';
    import { fade, fly } from 'svelte/transition';
    export let form;
    let submitting = false;
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVO LOCAL</h2>
    <a href="/venues" class="text-lg text-bold text-slate-700">-<ArrowLeft/>-</a>
</div>
{#if !form?.success && !form?.error}
<form method="POST"
      use:enhance={() => {
        submitting = true;
        return async ({ update }) => {
          await update();
          submitting = false;
        };
      }}>
    <div class="flex flex-col w-3/4 p-5 mb-4">
        <label for="name" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Nombre del Local</label>
        <input id="name" type="text" name="name" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400 }} />
    
        <label for="address" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Dirección</label>
        <input id="address" type="text" name="address" class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }} />
    
        <label for="contact_name" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 100 }}>Persona de contacto</label>
        <input id="contact_name" type="text" name="contact_name" required class="p-2 border rounded"  in:fly={{ y: -30, duration: 400, delay: 100 }} />

        <label for="contact" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Info de contacto</label>
        <input id="contact" type="text" name="contact" required class="p-2 border rounded" placeholder="telefono, correo, instagram" in:fly={{ y: -30, duration: 400, delay: 150 }}/>
    </div>
    
    <button class="bg-slate-700 text-slate-200 rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 200 }}>
        {submitting ? 'Creando...' : 'Crear Local'}
    </button>
</form>
{/if}
{#if form?.success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nuevo Local {form.venue?.name} Creado!
    </div>
{/if}

{#if form?.error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {form.error}
    </div>
{/if}