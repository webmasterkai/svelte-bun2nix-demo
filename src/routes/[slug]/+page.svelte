<script lang="ts">
	let { data } = $props();
</script>

<svelte:head>
	<title>{data.title} — Grimoire</title>
</svelte:head>

<main>
	<p><a href="/">← all archetypes</a></p>
	<h1>{data.title}</h1>
	{#if data.description}<p class="description">{data.description}</p>{/if}

	{#each data.features as feature (feature.name)}
		<section>
			<h2>{feature.title ?? feature.name} <code>{feature.name}</code></h2>
			{#if feature.props.length}
				<ul>
					{#each feature.props as prop (prop.name)}
						<li>
							<code>{prop.name}</code>
							{#if prop.title}— {prop.title}{/if}
							{#if prop.props.length}
								<ul>
									{#each prop.props as sub (sub.name)}
										<li><code>{sub.name}</code>{#if sub.title}&nbsp;— {sub.title}{/if}</li>
									{/each}
								</ul>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/each}
</main>

<style>
	main {
		max-width: 40rem;
		margin: 4rem auto;
		padding: 0 1rem;
		font-family: system-ui, sans-serif;
		line-height: 1.6;
	}

	.description {
		color: #555;
	}

	section {
		margin-top: 1.5rem;
	}

	h2 {
		font-size: 1.1rem;
		margin-bottom: 0.25rem;
	}

	h2 code {
		font-weight: 400;
		font-size: 0.8rem;
		color: #777;
	}

	ul {
		margin: 0;
		padding-left: 1.25rem;
	}
</style>
