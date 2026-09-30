/** Offline catalog consistency, not biological validation or dispatch readiness. */
import type { Taxon } from "./contracts.ts";
import { fingerprintJson } from "./evidence.ts";
import { fingerprintRunCorpus, parseExploratoryCorpus } from "./exploratory.ts";
import { normalizedTaxonomyName, parseTaxonomy } from "./taxonomy.ts";
import { requireCondition as check } from "./validation.ts";

const MAX_COLLISIONS = 100;
const MAX_COLLISION_TAXA = 32;
interface NameOwner {
  taxon: Taxon;
  role: "canonical" | "synonym";
}

/** Names never leave this function; references use the catalog's exact ID/rank. */
export async function auditPhotoTaxonomy(
  corpusValue: unknown,
  taxonomyValue: unknown,
) {
  const corpus = parseExploratoryCorpus(corpusValue);
  const taxonomy = parseTaxonomy(taxonomyValue);
  check(taxonomy.version === "evaluation_taxonomy_v2");
  check(corpus.taxonomyVersion === taxonomy.taxonomyVersion);
  check(corpus.cases.every((c) => c.input.inputGroup === "photos"));
  const names = new Map<string, NameOwner[]>();
  const ids = new Map(taxonomy.taxa.map((t) => [t.taxon.id, t.taxon]));
  for (const t of taxonomy.taxa) {
    const entries = [
      { name: t.canonicalName, role: "canonical" as const },
      ...t.synonyms.map((name) => ({ name, role: "synonym" as const })),
    ];
    for (const { name, role } of entries) {
      const key = normalizedTaxonomyName(name);
      const owners = names.get(key) ?? [];
      owners.push({ taxon: t.taxon, role });
      names.set(key, owners);
    }
  }
  let collisionCount = 0, duplicateCanonicalCount = 0;
  const collisions: {
    kind: "duplicate_canonical" | "canonical_synonym" | "synonym_overlap";
    taxonCount: number;
    taxa: NameOwner[];
    taxaTruncated: boolean;
  }[] = [];
  for (const owners of names.values()) {
    if (owners.length < 2) continue;
    collisionCount++;
    const canonicalCount = owners.filter((o) => o.role === "canonical").length;
    if (canonicalCount > 1) duplicateCanonicalCount++;
    if (collisions.length >= MAX_COLLISIONS) continue;
    collisions.push({
      kind: canonicalCount > 1
        ? "duplicate_canonical"
        : canonicalCount === 1
        ? "canonical_synonym"
        : "synonym_overlap",
      taxonCount: owners.length,
      taxa: owners.slice(0, MAX_COLLISION_TAXA),
      taxaTruncated: owners.length > MAX_COLLISION_TAXA,
    });
  }
  const referenceIssues: {
    caseId: string;
    taxon: Taxon;
    issue: "missing_id" | "rank_mismatch";
  }[] = [];
  const unreferencedCaseIds: string[] = [];
  for (const c of corpus.cases) {
    if (c.provisionalReference === null) {
      unreferencedCaseIds.push(c.input.caseId);
      continue;
    }
    for (const taxon of c.provisionalReference.acceptableTaxa) {
      const catalogTaxon = ids.get(taxon.id);
      if (!catalogTaxon || catalogTaxon.rank !== taxon.rank) {
        referenceIssues.push({
          caseId: c.input.caseId,
          taxon,
          issue: catalogTaxon ? "rank_mismatch" : "missing_id",
        });
      }
    }
  }
  return {
    version: "photo_taxonomy_audit_v1" as const,
    dispatchAuthorized: false,
    referenceReviewComplete: false,
    catalogConsistency:
      collisionCount || referenceIssues.length || unreferencedCaseIds.length
        ? "blocked" as const
        : "clear" as const,
    corpusDigest: await fingerprintRunCorpus(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    counts: {
      taxa: taxonomy.taxa.length,
      nameCollisions: collisionCount,
      duplicateCanonicalNames: duplicateCanonicalCount,
      brokenReferences: referenceIssues.length,
      unreferencedCases: unreferencedCaseIds.length,
    },
    collisions,
    collisionDetailsTruncated: collisionCount > collisions.length,
    referenceIssues,
    unreferencedCaseIds,
  };
}
