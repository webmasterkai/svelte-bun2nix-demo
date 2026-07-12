<script lang="ts">
	let count = $state(0);
	const doubled = $derived(count * 2);
</script>

<svelte:head>
	<title>SvelteKit × bun2nix</title>
</svelte:head>

<main>
	<h1>SvelteKit → single Bun binary</h1>
	<p>
		This demo is built with <a href="https://svelte.dev/docs/kit">SvelteKit</a>, served by
		<a href="https://bun.sh">Bun</a>, and packaged reproducibly for Nix with
		<a href="https://github.com/nix-community/bun2nix">bun2nix</a>. The whole server is
		AOT-compiled into one standalone executable — no <code>node_modules</code> at runtime.
	</p>

	<button onclick={() => count++}>
		clicked {count} {count === 1 ? 'time' : 'times'}
	</button>
	<p>doubled: {doubled}</p>
</main>

<style>
	main {
		max-width: 40rem;
		margin: 4rem auto;
		padding: 0 1rem;
		font-family: system-ui, sans-serif;
		line-height: 1.6;
	}

	button {
		font: inherit;
		padding: 0.5rem 1rem;
		border-radius: 0.5rem;
		border: 1px solid currentColor;
		cursor: pointer;
	}
</style>
