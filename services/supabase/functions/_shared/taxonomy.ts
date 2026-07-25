export interface TaxonomyLike {
  kingdom?: string | null;
  phylum?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
  genus?: string | null;
}

export function normalizeTaxonomyValue(
  value: string | null | undefined,
): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;
  return trimmed.toLowerCase() == "unknown" ? null : trimmed;
}

export function coalesceTaxonomyValue(
  ...values: Array<string | null | undefined>
): string | null {
  for (const value of values) {
    const normalized = normalizeTaxonomyValue(value);
    if (normalized) return normalized;
  }
  return null;
}

export function hasUsableLookalikeTaxonomy(
  taxonomy:
    | Pick<TaxonomyLike, "kingdom" | "order" | "family">
    | null
    | undefined,
): boolean {
  return normalizeTaxonomyValue(taxonomy?.kingdom) !== null &&
    (
      normalizeTaxonomyValue(taxonomy?.order) !== null ||
      normalizeTaxonomyValue(taxonomy?.family) !== null
    );
}
