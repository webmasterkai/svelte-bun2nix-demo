import { error } from '@sveltejs/kit';
import { archetype } from '@nodeve/grimoire/archetypes';

type PropView = { name: string; title?: string; props: PropView[] };

const propList = (prop: object | undefined, depth = 0): PropView[] =>
	Object.entries(prop ?? {}).map(([name, node]) => ({
		name,
		title: node?.title?.en,
		props: depth < 2 ? propList(node?.prop, depth + 1) : []
	}));

export const load = ({ params }: { params: { slug: string } }) => {
	const node = archetype[params.slug as keyof typeof archetype];
	if (!node) error(404, `no archetype "${params.slug}"`);
	return {
		slug: params.slug,
		title: node.title?.en ?? params.slug,
		description: node.description?.en ?? '',
		features: propList(node.prop)
	};
};
