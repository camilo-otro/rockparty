<script lang="ts">
	import { page } from '$app/stores';
</script>

<div class="max-w-xl mx-auto mt-16 text-center px-4">
	<h1 class="text-6xl text-yellow mb-3">{$page.status}</h1>
	<p class="text-white text-lg mb-8">
		{$page.error?.message ?? 'Algo salió mal.'}
	</p>
	<a href="/" class="inline-block bg-cold-base text-white px-6 py-3 rounded-lg">Volver al inicio</a>
</div>
