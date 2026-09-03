<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { goto } from '$app/navigation';
  import { ChevronLeft, Bell, CheckCircle2, XCircle, Clock, Zap, CalendarClock, UserPlus } from 'lucide-svelte';
  import { reportError } from '$lib/stores/toasts';
  import { refreshUnread } from '$lib/stores/notifications';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';
  import relativeTime from 'dayjs/plugin/relativeTime';
  dayjs.extend(relativeTime);
  dayjs.locale('es');

  // 'loading' until auth is known, so we don't flash the logged-out gate (#48).
  let authState: 'loading' | 'in' | 'out' = 'loading';
  let items: any[] = [];

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) { authState = 'out'; return; }
    // RLS scopes this to the current user's own notifications.
    const { data } = await supabase.from('notification').select('*').order('created_at', { ascending: false }).limit(50);
    items = data ?? [];
    authState = 'in';
  });

  // Map a notification type + payload to an icon, text, optional reason, and link.
  function describe(n: any): { icon: any; cls: string; text: string; reason: string | null; href: string | null } {
    const p = (n.payload ?? {}) as any;
    const title = p.party_title || 'un toque';
    const song = p.song_title || 'una canción';
    // Signup notifications point at the song; party ones at the toque.
    const href = p.performance_id ? `/performance/${p.performance_id}` : (p.party_id ? `/parties/${p.party_id}` : null);
    switch (n.type) {
      case 'party_approved':
        return { icon: CheckCircle2, cls: 'text-green-500', text: `Tu toque «${title}» fue aprobado por el local.`, reason: null, href };
      case 'party_declined':
        return { icon: XCircle, cls: 'text-warm-base', text: `El local rechazó tu toque «${title}».`, reason: p.reason ?? null, href };
      case 'party_venue_cancelled':
        return { icon: XCircle, cls: 'text-warm-base', text: `El local canceló tu toque «${title}».`, reason: p.reason ?? null, href };
      case 'party_pending_venue':
        return { icon: Clock, cls: 'text-yellow', text: `El toque «${title}» espera tu aprobación.`, reason: null, href };
      case 'party_live':
        return { icon: Zap, cls: 'text-warm-base', text: `¡El show «${title}» está por empezar!`, reason: null, href };
      case 'party_reminder':
        return { icon: CalendarClock, cls: 'text-cold-light', text: `Recordatorio: el toque «${title}» es mañana.`, reason: null, href };
      case 'signup_requested':
        return { icon: UserPlus, cls: 'text-cold-light', text: `Alguien quiere tocar «${song}» en «${title}».`, reason: null, href };
      case 'band_signup_requested':
        return { icon: UserPlus, cls: 'text-cold-light', text: `La banda «${p.band_name ?? 'una banda'}» quiere tocar «${song}» en «${title}».`, reason: null, href };
      case 'signup_approved':
        return { icon: CheckCircle2, cls: 'text-green-500', text: `Te aprobaron para tocar «${song}» en «${title}».`, reason: null, href };
      case 'signup_declined':
        return { icon: XCircle, cls: 'text-warm-base', text: `No fuiste elegido para «${song}» en «${title}».`, reason: null, href };
      default:
        return { icon: Bell, cls: 'text-cold-light', text: 'Nueva notificación.', reason: null, href };
    }
  }

  async function markRead(n: any) {
    if (n.read_at) return;
    const { error } = await supabase.from('notification').update({ read_at: new Date().toISOString() }).eq('id', n.id);
    if (error) { reportError(error); return; }
    n.read_at = new Date().toISOString();
    items = items;
    refreshUnread();
  }

  async function open(n: any) {
    await markRead(n);
    const href = describe(n).href;
    if (href) goto(href);
  }

  async function markAllRead() {
    const now = new Date().toISOString();
    const { error } = await supabase.from('notification').update({ read_at: now }).is('read_at', null);
    if (error) { reportError(error); return; }
    items = items.map((n) => ({ ...n, read_at: n.read_at ?? now }));
    refreshUnread();
  }

  $: hasUnread = items.some((n) => !n.read_at);
</script>

<div class="flex flex-col">
  <div class="flex flex-row items-center justify-between mx-4 m-2">
    <a href="/" class="text-bold text-cold-light flex flex-row gap-2"><ChevronLeft />VOLVER</a>
    {#if authState === 'in' && hasUnread}
      <button on:click={markAllRead} class="text-cold-light text-sm hover:text-white transition">Marcar todas como leídas</button>
    {/if}
  </div>
  <h2 class="text-3xl text-white m-4 mb-4">NOTIFICACIONES</h2>

  {#if authState === 'loading'}
    <div class="text-white p-4 mx-4">Cargando...</div>
  {:else if authState === 'out'}
    <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
      Debes iniciar sesión para ver tus notificaciones.
    </div>
  {:else if items.length === 0}
    <div class="mx-4 p-6 bg-base-900 text-cold-light rounded-lg text-center">Aún no tienes notificaciones.</div>
  {:else}
    <ul class="m-4 mt-0 rounded-lg overflow-clip space-y-[1px]">
      {#each items as n (n.id)}
        {@const d = describe(n)}
        <li>
          <button
            type="button"
            on:click={() => open(n)}
            class="w-full text-left flex gap-3 items-start px-4 py-3 bg-base-900 hover:bg-base-950 transition {n.read_at ? '' : 'border-l-2 border-cold-base'}"
          >
            <svelte:component this={d.icon} class="{d.cls} shrink-0 mt-0.5" size={20} />
            <div class="flex-1 min-w-0">
              <div class="text-white text-sm {n.read_at ? 'opacity-60' : ''}">{d.text}</div>
              {#if d.reason}<div class="text-cold-light text-sm">Motivo: {d.reason}</div>{/if}
              <div class="text-cold-light text-xs mt-0.5">{dayjs(n.created_at).fromNow()}</div>
            </div>
            {#if !n.read_at}<span class="w-2 h-2 rounded-full bg-warm-base shrink-0 mt-1.5"></span>{/if}
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</div>
