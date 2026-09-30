/** Explicit duplicate-ID consolidation for a new offline packet, never old scores. */
import { fingerprintJson } from "./evidence.ts";
import { fingerprintRunCorpus, parseExploratoryCorpus } from "./exploratory.ts";
import { auditPhotoTaxonomy } from "./photoTaxonomyAudit.ts";
import { hash } from "./runContracts.ts";
import { normalizedTaxonomyName, parseTaxonomy } from "./taxonomy.ts";
import {
  array,
  fields,
  requireCondition as check,
  token,
} from "./validation.ts";

export interface PhotoTaxonomyRemap {
  version: "photo_taxonomy_remap_v1";
  sourceCorpusDigest: string;
  sourceTaxonomyDigest: string;
  corpusId: string;
  taxonomyVersion: string;
  catalogRef: string;
  reviewRef: string;
  merges: { from: string; to: string }[];
}

export function parsePhotoTaxonomyRemap(value: unknown): PhotoTaxonomyRemap {
  const v = fields(value, [
    "version",
    "sourceCorpusDigest",
    "sourceTaxonomyDigest",
    "corpusId",
    "taxonomyVersion",
    "catalogRef",
    "reviewRef",
    "merges",
  ]);
  check(v.version === "photo_taxonomy_remap_v1");
  hash(v.sourceCorpusDigest);
  hash(v.sourceTaxonomyDigest);
  for (const k of ["corpusId", "taxonomyVersion", "catalogRef", "reviewRef"]) {
    token(v[k]);
  }
  const sources = new Set<string>(), targets = new Set<string>();
  for (const raw of array(v.merges, 1, 100)) {
    const item = fields(raw, ["from", "to"]);
    token(item.from);
    token(item.to);
    const from = item.from as string, to = item.to as string;
    check(from !== to && !sources.has(from));
    sources.add(from);
    targets.add(to);
  }
  // No chains or cycles: every destination is a retained identity.
  check([...sources].every((from) => !targets.has(from)));
  return structuredClone(v) as unknown as PhotoTaxonomyRemap;
}

export async function repairPhotoTaxonomy(
  corpusValue: unknown,
  taxonomyValue: unknown,
  remapValue: unknown,
) {
  const corpus = parseExploratoryCorpus(corpusValue);
  const taxonomy = parseTaxonomy(taxonomyValue);
  const remap = parsePhotoTaxonomyRemap(remapValue);
  check(taxonomy.version === "evaluation_taxonomy_v2");
  check(
    await fingerprintRunCorpus(corpus) === remap.sourceCorpusDigest &&
      await fingerprintJson(taxonomy) === remap.sourceTaxonomyDigest &&
      corpus.taxonomyVersion === taxonomy.taxonomyVersion &&
      corpus.id !== remap.corpusId &&
      taxonomy.taxonomyVersion !== remap.taxonomyVersion &&
      taxonomy.catalogRef !== remap.catalogRef &&
      taxonomy.reviewRef !== remap.reviewRef,
  );
  const before = await auditPhotoTaxonomy(corpus, taxonomy);
  check(
    before.counts.brokenReferences === 0 &&
      before.counts.unreferencedCases === 0,
  );
  const ids = new Map(taxonomy.taxa.map((t) => [t.taxon.id, t]));
  for (const { from, to } of remap.merges) {
    const removed = ids.get(from), kept = ids.get(to);
    check(removed && kept);
    check(
      removed.taxon.rank === kept.taxon.rank &&
        normalizedTaxonomyName(removed.canonicalName) ===
          normalizedTaxonomyName(kept.canonicalName),
    );
    const names = new Map(
      [kept.canonicalName, ...kept.synonyms, ...removed.synonyms]
        .map((n) => [normalizedTaxonomyName(n), n]),
    );
    names.delete(normalizedTaxonomyName(kept.canonicalName));
    kept.synonyms = [...names.values()];
  }
  const map = new Map(remap.merges.map(({ from, to }) => [from, to]));
  taxonomy.taxa = taxonomy.taxa.filter((t) => !map.has(t.taxon.id));
  taxonomy.taxonomyVersion = remap.taxonomyVersion;
  taxonomy.catalogRef = remap.catalogRef;
  taxonomy.reviewRef = remap.reviewRef;
  corpus.id = remap.corpusId;
  corpus.taxonomyVersion = remap.taxonomyVersion;
  let rewrittenReferences = 0, deduplicatedReferences = 0;
  for (const c of corpus.cases) {
    const reference = c.provisionalReference!;
    const acceptable = new Map<
      string,
      typeof reference.acceptableTaxa[number]
    >();
    for (const taxon of reference.acceptableTaxa) {
      const id = map.get(taxon.id) ?? taxon.id;
      if (id !== taxon.id) rewrittenReferences++;
      if (acceptable.has(id)) deduplicatedReferences++;
      acceptable.set(id, { ...taxon, id });
    }
    c.provisionalReference = {
      ...reference,
      acceptableTaxa: [...acceptable.values()],
    };
  }
  const repairedCorpus = parseExploratoryCorpus(corpus);
  const repairedTaxonomy = parseTaxonomy(taxonomy);
  const after = await auditPhotoTaxonomy(repairedCorpus, repairedTaxonomy);
  check(after.catalogConsistency === "clear");
  return {
    corpus: repairedCorpus,
    taxonomy: repairedTaxonomy,
    remap,
    report: {
      version: "photo_taxonomy_repair_v1" as const,
      dispatchAuthorized: false,
      referenceReviewComplete: false,
      remapDigest: await fingerprintJson(remap),
      sourceCorpusDigest: remap.sourceCorpusDigest,
      sourceTaxonomyDigest: remap.sourceTaxonomyDigest,
      mergedIdentities: remap.merges.length,
      rewrittenReferences,
      deduplicatedReferences,
      audit: after,
    },
  };
}
