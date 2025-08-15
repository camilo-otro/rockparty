<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { enhance } from '$app/forms';
    import { fade, fly } from 'svelte/transition';
    export let form;
    let submitting = false;
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVO INTÉRPRETE</h2>
    <a href="/performers" class="text-lg text-bold text-slate-700"><ArrowLeft/></a>
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
        <label for="nickname" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Nickname</label>
        <input id="nickname" type="text" name="nickname" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400 }} />
        <label for="role" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Role ID</label>
        <input id="role" type="number" name="role" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }} />
    </div>
    <button class="bg-slate-700 text-slate-200 rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 100 }}>
        {submitting ? 'Creando...' : 'Crear Intérprete'}
    </button>
</form>
{/if}
{#if form?.success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nuevo Intérprete Creado!
    </div>
{/if}
{#if form?.error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {form.error}
    </div>
{/if}
