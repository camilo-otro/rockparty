<script lang="ts">
  // Thin wrapper: the page body lives in PerformanceDetail so the party page can
  // render the same thing as an overlay (#94). This route still exists and still
  // works on its own — a notification link, a shared URL, or a hard refresh all
  // land here and get the full page.
  import { page } from '$app/state';
  import PerformanceDetail from '$lib/components/PerformanceDetail.svelte';
</script>

<PerformanceDetail performanceId={page.params.id} />
