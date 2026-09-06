<!-- Per-musician applause on one song (#38 Stage B) — "you nailed THAT one".

     Deliberately behind a tap rather than inline on every setlist row: four clap
     buttons per row is exactly the attention sink principle 1 exists to prevent
     (docs/specs/applause.md). The row keeps one control; this panel is opened
     only when someone actually wants to single a musician out.

     `tallies` is passed as the whole map (not a lookup function) so a change to
     it re-renders this component — in legacy mode a function prop keeps its
     identity when the data behind it changes, and the counts would go stale. -->
<script lang="ts">
  import ApplauseButton from './ApplauseButton.svelte';
  import { createEventDispatcher } from 'svelte';

  export let perfId: number;
  export let lineup: { user_id: string; name: string; avatar: string; instruments: string }[] = [];
  export let tallies: Record<string, { count: number; mine: number | null }> = {};
  export let busy = new Set<string>();
  export let canApplaud = false;

  const dispatch = createEventDispatcher();
</script>

{#if lineup.length}
  <div class="px-4 pb-3 pt-1 flex flex-col gap-2 bg-base-950/40">
    <span class="text-[0.65rem] uppercase tracking-widest text-cold-light/60">
      {canApplaud ? 'Aplaude a quien se lució' : 'Quién la tocó'}
    </span>
    {#each lineup as m (m.user_id)}
      {@const t = tallies[perfId + ':' + m.user_id]}
      <div class="flex items-center gap-2">
        <img src={m.avatar} alt="" class="w-6 h-6 rounded-full border border-cold-base shrink-0" />
        <div class="min-w-0 flex-1">
          <div class="text-sm text-white truncate">{m.name}</div>
          {#if m.instruments}<div class="text-xs text-cold-light/70 truncate">{m.instruments}</div>{/if}
        </div>
        {#if canApplaud}
          <ApplauseButton count={t?.count ?? 0} clapped={!!t?.mine}
                          busy={busy.has('sp:' + perfId + ':' + m.user_id)}
                          label={m.name}
                          on:toggle={() => dispatch('toggle', m.user_id)} />
        {:else if t?.count}
          <ApplauseButton count={t.count} readOnly />
        {/if}
      </div>
    {/each}
  </div>
{/if}
