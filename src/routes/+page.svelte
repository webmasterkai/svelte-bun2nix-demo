<script lang="ts">
	let { data } = $props();
</script>

<svelte:head>
	<title>Grimoire archetypes</title>
</svelte:head>

<main>
	<h1>Grimoire archetypes</h1>
	<p>
		Every archetype from <code>@nodeve/grimoire/archetypes</code>, rendered straight off the
		package's generated def nodes — served by a single Bun binary built with bun2nix.
	</p>

	<ul>
		{#each data.archetypes as a (a.slug)}
			<li>
				<a href="/{a.slug}">{a.title}</a>
				{#if a.description}<p>{a.description}</p>{/if}
			</li>
		{/each}
	</ul>
</main>

<style>
	main {
		max-width: 40rem;
		margin: 4rem auto;
		padding: 0 1rem;
		font-family: system-ui, sans-serif;
		line-height: 1.6;
	}

	ul {
		list-style: none;
		padding: 0;
	}

	li {
		padding: 0.75rem 0;
		border-bottom: 1px solid #ddd;
	}

	li a {
		font-weight: 600;
	}

	li p {
		margin: 0.25rem 0 0;
		color: #555;
		font-size: 0.9rem;
	}
</style>
