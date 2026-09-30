import type { Taxon } from "./contracts.ts";
import {
  array,
  fields,
  requireCondition as check,
  taxon,
  text,
  token,
} from "./validation.ts";

export interface LegacyTaxonomy {
  version: "evaluation_taxonomy_v1";
  taxonomyVersion: string;
  taxa: { taxon: Taxon; names: string[] }[];
}
export interface ReviewedTaxonomy {
  version: "evaluation_taxonomy_v2";
  taxonomyVersion: string;
  catalogRef: string;
  reviewRef: string;
  taxa: { taxon: Taxon; canonicalName: string; synonyms: string[] }[];
}
export type Taxonomy = LegacyTaxonomy | ReviewedTaxonomy;
export const MEASUREMENT_SCORER = "identification_exploratory_decisions_v2";
export type IdentityMapping = {
  status: "matched" | "ambiguous" | "unmapped" | "not_applicable";
  match: "canonical" | "synonym" | null;
};
export const noIdentityMapping = (): IdentityMapping => ({
  status: "not_applicable",
  match: null,
});
export const normalizedTaxonomyName = (name: string) =>
  name.normalize("NFC").trim().replace(/\s+/gu, " ").toLowerCase();

/** Frozen catalogs only; never consult a provider, live taxonomy service or label. */
export function parseTaxonomy(value: unknown): Taxonomy {
  const version = (value as { version?: unknown } | null)?.version;
  const reviewed = version === "evaluation_taxonomy_v2";
  const v = fields(value, [
    "version",
    "taxonomyVersion",
    "taxa",
    ...(reviewed ? ["catalogRef", "reviewRef"] : []),
  ]);
  check(reviewed || version === "evaluation_taxonomy_v1");
  token(v.taxonomyVersion);
  if (reviewed) {
    token(v.catalogRef);
    token(v.reviewRef);
  }
  const ids = new Set<string>(), legacyNames = new Set<string>();
  for (const raw of array(v.taxa, 1, 100000)) {
    const item = fields(
      raw,
      reviewed ? ["taxon", "canonicalName", "synonyms"] : ["taxon", "names"],
    );
    const identity = taxon(item.taxon);
    check(!ids.has(identity.id));
    ids.add(identity.id);
    const names = reviewed
      ? [item.canonicalName, ...array(item.synonyms, 0, 31)]
      : array(item.names, 1, 32);
    const local = new Set<string>();
    for (const name of names) {
      text(name, 255);
      const key = reviewed ? normalizedTaxonomyName(name) : name.toLowerCase();
      check(key.length > 0 && !local.has(key));
      local.add(key);
      if (!reviewed) {
        check(!legacyNames.has(key));
        legacyNames.add(key);
      }
    }
  }
  return structuredClone(v) as unknown as Taxonomy;
}

export function resolveTaxon(
  taxonomy: Taxonomy,
  name: string,
): { taxon: Taxon | null; mapping: IdentityMapping } {
  if (taxonomy.version === "evaluation_taxonomy_v1") {
    const found = taxonomy.taxa.find((t) =>
      t.names.some((n) => n.toLowerCase() === name.toLowerCase())
    );
    return {
      taxon: found?.taxon ?? null,
      mapping: {
        status: found ? "matched" : "unmapped",
        match: found ? "canonical" : null,
      },
    };
  }
  const key = normalizedTaxonomyName(name);
  const matches = taxonomy.taxa.flatMap((t) => {
    const canonical = normalizedTaxonomyName(t.canonicalName) === key;
    return canonical ||
        t.synonyms.some((n) => normalizedTaxonomyName(n) === key)
      ? [{
        taxon: t.taxon,
        match: canonical ? "canonical" as const : "synonym" as const,
      }]
      : [];
  });
  if (matches.length !== 1) {
    return {
      taxon: null,
      mapping: {
        status: matches.length ? "ambiguous" : "unmapped",
        match: null,
      },
    };
  }
  return {
    taxon: matches[0].taxon,
    mapping: { status: "matched", match: matches[0].match },
  };
}

export function parseIdentityMapping(
  value: unknown,
  identity: Taxon | null,
): IdentityMapping {
  const v = fields(value, ["status", "match"]);
  check(
    ["matched", "ambiguous", "unmapped", "not_applicable"].includes(
      v.status as string,
    ),
  );
  check(
    v.status === "matched"
      ? identity !== null &&
        ["canonical", "synonym"].includes(v.match as string)
      : identity === null && v.match === null,
  );
  return structuredClone(v) as IdentityMapping;
}
