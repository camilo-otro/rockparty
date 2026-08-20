<script lang="ts">
  import type { Database } from '$lib/database.types';

  export let status: Database['public']['Enums']['party_status'];

  const meta: Record<string, { label: string; cls: string }> = {
    draft:         { label: 'Borrador',           cls: 'bg-base-900 text-cold-light border border-cold-light/40' },
    pending_venue: { label: 'Pendiente de local', cls: 'bg-yellow text-black' },
    confirmed:     { label: 'Confirmado',         cls: 'bg-cold-base text-white' },
    live:          { label: 'En vivo',            cls: 'bg-warm-base text-white' },
    completed:     { label: 'Finalizado',         cls: 'bg-base-900 text-cold-light' },
    cancelled:     { label: 'Cancelado',          cls: 'bg-red-600 text-white' }
  };

  $: m = meta[status] ?? { label: status, cls: 'bg-base-900 text-cold-light' };
</script>

<span class="inline-flex items-center rounded-full px-3 py-1 text-xs font-medium uppercase tracking-wide whitespace-nowrap {m.cls}">
  {m.label}
</span>
