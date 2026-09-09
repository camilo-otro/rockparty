<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, Trash2, Lock, AlertTriangle, ExternalLink } from 'lucide-svelte';
  import { reportError, toastSuccess, toastError } from '$lib/stores/toasts';

  // Song moderation (#99). #98 made adding a song to the shared catalogue a
  // one-tap action from the setlist page, so the catalogue now needs a cleanup
  // path for typos, wrong versions and joke entries.
  //
  // The list comes from songs_for_moderation(), a SECURITY DEFINER function,
  // rather than a plain select with embeds. That is not an optimisation — a
  // client query reads performance/party under RLS, which hides another
  // organizer's draft, pending_venue or cancelled toque, so a song that IS on a
  // real set list would look free to delete. The definer function sees the same
  // rows the delete policy's guard sees, so the screen and the database agree.
  type PartyRef = { id: number | null; title: string | null };
  type Row = {
    id: number;
    title: string | null;
    artist: string | null;
    ref_link: string | null;
    created_at: string;
    added_by_nickname: string | null;
    real_uses: number;
    test_uses: number;
    real_parties: PartyRef[];
  };

  let authState: 'loading' | 'out' | 'denied' | 'in' = 'loading';
  let rows: Row[] = [];
  let loadError = '';
  let confirming: number | null = null;
  let busy: number | null = null;

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) { authState = 'out'; return; }

    const { data: mod } = await supabase
      .from('song_moderator').select('user_id').eq('user_id', session.user.id).maybeSingle();
    if (!mod) { authState = 'denied'; return; }

    await load();
    authState = 'in';
  });

  async function load() {
    const { data, error } = await supabase.rpc('songs_for_moderation');
    if (error) {
      // Inline, not a toast: a toast over an empty list reads as "nobody has
      // added songs", which is the opposite of what happened. (Page-load errors
      // stay inline by design in this app.)
      loadError = error.message;
      rows = [];
      return;
    }
    loadError = '';
    rows = (data ?? []) as Row[];
  }

  $: deletable = rows.filter((r) => r.real_uses === 0).length;

  const fmt = (iso: string) =>
    new Date(iso).toLocaleDateString('es', { day: 'numeric', month: 'short', year: 'numeric' });

  async function remove(r: Row) {
    if (busy !== null) return;
    busy = r.id;
    // `.select()` matters: without it PostgREST answers a delete that matched
    // ZERO rows with 204 and no error, so a policy refusal would look like
    // success. The returned array length is the only honest signal — and it is
    // how an earlier manual cleanup appeared to work while changing nothing.
    const { data, error } = await supabase.from('song').delete().eq('id', r.id).select('id');
    busy = null;
    confirming = null;

    if (error) { reportError(error); return; }
    if (!data?.length) {
      toastError('La base de datos no permitió borrarla. Puede que ya esté en el repertorio de un toque.');
      await load();
      return;
    }
    rows = rows.filter((x) => x.id !== r.id);
    toastSuccess(`"${r.title ?? 'Canción'}" fue borrada del catálogo.`);
  }
</script>

<svelte:head><title>Moderar canciones · Rock the House</title></svelte:head>

<div class="flex flex-col items-left">
  <div class="flex flex-row items-center">
    <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft />VOLVER</a>
  </div>

  <section>
    <h2 class="text-3xl text-white mx-4 mb-1">MODERAR CANCIONES</h2>

    {#if authState === 'loading'}
      <div class="text-white p-4 mx-4">Cargando…</div>

    {:else if authState === 'out'}
      <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
        Debes iniciar sesión.
      </div>

    {:else if authState === 'denied'}
      <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center flex flex-col gap-3">
        <span>No tienes permiso para moderar el catálogo.</span>
        <a href="/songs" class="text-cold-light underline">Ver las canciones</a>
      </div>

    {:else if loadError}
      <div class="mt-8 mx-4 p-6 bg-base-900 rounded-lg text-center flex flex-col gap-3">
        <span class="text-warm-base">No se pudo cargar la lista.</span>
        <span class="text-cold-light text-sm">{loadError}</span>
        <button type="button" on:click={load} class="bg-cold-base text-white rounded-lg px-4 py-2 self-center">
          Reintentar
        </button>
      </div>

    {:else}
      <p class="text-cold-light text-sm mx-4 mb-4">
        Canciones que agregó alguien desde la app. Las que ya están en el repertorio
        de un toque no se pueden borrar.
      </p>

      {#if !rows.length}
        <div class="mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
          Nadie ha agregado canciones todavía.
        </div>
      {:else}
        <p class="text-cold-light text-xs mx-4 mb-2">
          {rows.length} agregadas · {deletable} se pueden borrar
        </p>

        <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
          {#each rows as r (r.id)}
            <li class="bg-base-900 px-4 py-3 flex flex-col gap-2">
              <div class="flex items-start gap-3">
                <div class="grow min-w-0">
                  <a href="/songs/{r.id}" class="text-white block truncate">{r.title ?? 'Sin título'}</a>
                  <div class="text-cold-light text-sm truncate">{r.artist ?? 'Sin artista'}</div>
                  <div class="text-cold-light/70 text-xs mt-1">
                    {r.added_by_nickname ?? 'Alguien'} · {fmt(r.created_at)}
                    {#if r.ref_link}
                      · <a href={r.ref_link} target="_blank" rel="noopener noreferrer"
                           class="text-cold-light inline-flex items-center gap-0.5 underline">
                          Spotify <ExternalLink size={11} />
                        </a>
                    {/if}
                  </div>
                </div>

                {#if r.real_uses > 0}
                  <span class="shrink-0 inline-flex items-center gap-1 text-[0.6rem] uppercase tracking-wide px-2 py-1 rounded-full border border-cold-light/40 text-cold-light">
                    <Lock size={11} /> En uso
                  </span>
                {:else if confirming !== r.id}
                  <button type="button" on:click={() => (confirming = r.id)}
                    aria-label="Borrar {r.title ?? 'canción'}"
                    class="shrink-0 w-9 h-9 rounded-full border border-warm-base/60 text-warm-base inline-flex items-center justify-center">
                    <Trash2 size={16} />
                  </button>
                {/if}
              </div>

              {#if r.real_uses > 0}
                <!-- Name the toques rather than just counting them: "en 2 toques"
                     is not enough to judge whether the block is correct. -->
                <div class="text-xs text-cold-light/70">
                  En el repertorio de
                  {#each r.real_parties as p, i}{i > 0 ? ', ' : ''}{#if p.id}<a href="/parties/{p.id}" class="text-cold-light underline">{p.title ?? 'Toque #' + p.id}</a>{:else}<span class="text-yellow">un toque desconocido</span>{/if}{/each}.
                </div>

              {:else if confirming === r.id}
                <div class="flex flex-col gap-2 border-t border-base-950 pt-2">
                  <div class="text-xs text-warm-base flex items-start gap-1">
                    <AlertTriangle size={14} class="shrink-0 mt-px" />
                    <span>
                      Se borra del catálogo para todos y no se puede deshacer.
                      {#if r.test_uses}
                        También se {r.test_uses === 1 ? 'quita' : 'quitan'} {r.test_uses}
                        {r.test_uses === 1 ? 'entrada' : 'entradas'} en toques de prueba.
                      {/if}
                    </span>
                  </div>
                  <div class="flex gap-2">
                    <button type="button" on:click={() => remove(r)} disabled={busy === r.id}
                      class="bg-warm-base text-white rounded-lg px-3 py-2 text-sm grow disabled:opacity-60">
                      {busy === r.id ? 'Borrando…' : 'Sí, borrar'}
                    </button>
                    <button type="button" on:click={() => (confirming = null)}
                      class="text-cold-light px-3 py-2 text-sm">Cancelar</button>
                  </div>
                </div>

              {:else if r.test_uses}
                <div class="text-xs text-cold-light/70">
                  Solo en {r.test_uses} {r.test_uses === 1 ? 'toque' : 'toques'} de prueba.
                </div>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
    {/if}
  </section>
</div>
