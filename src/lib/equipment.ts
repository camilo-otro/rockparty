// Equipment catalogue shape (#106 follow-up).
//
// The catalogue is two levels deep: top-level items, and PARTS belonging to one
// of them (`part_of`). Today only the drum kit has parts, but nothing here knows
// that — add a `part_of` row to any item and both the venue form and the toque
// quick-start pick it up with no code change. That is the whole reason this is a
// shared module rather than a bit of grouping logic in each form: the two
// screens have to agree on what "on by default" means, and they drifted the last
// time an equipment rule lived in two places.

export type EquipmentOption = {
	id: number;
	name: string;
	category: string | null;
	part_of: number | null;
	default_on: boolean;
	is_basic?: boolean;
	default_quantity?: number | null;
	sort_order?: number | null;
};

/** One top-level item with the parts that belong to it. */
export type EquipmentItem<T extends EquipmentOption = EquipmentOption> = {
	item: T;
	parts: T[];
};

export type EquipmentGroup<T extends EquipmentOption = EquipmentOption> = {
	category: string;
	label: string;
	items: EquipmentItem<T>[];
};

/** Every column the grouping needs. One string so the fetch sites cannot drift. */
export const EQUIPMENT_COLS =
	'id, name, category, is_basic, default_on, default_quantity, part_of, sort_order';

// The category values are lowercase in the database because they double as
// <optgroup> labels in PartyLogistics' picker. Headings want them cased.
const CATEGORY_LABEL: Record<string, string> = {
	sonido: 'Sonido',
	batería: 'Batería',
	backline: 'Backline',
	escenario: 'Escenario',
	otros: 'Otros'
};

export function categoryLabel(category: string | null): string {
	if (!category) return CATEGORY_LABEL.otros;
	return CATEGORY_LABEL[category] ?? category.charAt(0).toUpperCase() + category.slice(1);
}

/**
 * Nest parts under their parent and group the result by category, preserving
 * `sort_order`. A part whose parent is missing from `options` is promoted to
 * top level rather than dropped — the quick-start fetches only `is_basic` items,
 * and silently swallowing a row there would be a gap nobody could see.
 */
export function groupEquipment<T extends EquipmentOption>(options: T[]): EquipmentGroup<T>[] {
	const sorted = [...options].sort(
		(a, b) => (a.sort_order ?? a.id) - (b.sort_order ?? b.id)
	);
	const present = new Set(sorted.map((o) => o.id));
	const tops = sorted.filter((o) => o.part_of == null || !present.has(o.part_of));
	const partsBy = new Map<number, T[]>();
	for (const o of sorted) {
		if (o.part_of == null || !present.has(o.part_of)) continue;
		const siblings = partsBy.get(o.part_of) ?? [];
		siblings.push(o);
		partsBy.set(o.part_of, siblings);
	}

	const groups: EquipmentGroup<T>[] = [];
	for (const item of tops) {
		const category = item.category ?? 'otros';
		let group = groups.find((g) => g.category === category);
		if (!group) {
			group = { category, label: categoryLabel(category), items: [] };
			groups.push(group);
		}
		group.items.push({ item, parts: partsBy.get(item.id) ?? [] });
	}
	return groups;
}
