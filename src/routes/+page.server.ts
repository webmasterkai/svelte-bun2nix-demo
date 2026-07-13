import { archetype } from '@nodeve/grimoire/archetypes';

export const load = () => ({
	archetypes: Object.entries(archetype).map(([slug, node]) => ({
		slug,
		title: node.title?.en ?? slug,
		description: node.description?.en ?? ''
	}))
});
