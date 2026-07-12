import adapter from 'svelte-adapter-bun';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},

			// svelte-adapter-bun emits a standalone Bun server (build/index.js) that
			// we AOT-compile into a single binary with `bun build --compile` in Nix.
			adapter: adapter()
		})
	]
});
