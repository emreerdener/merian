/** Coverage describes supplied provisional references, never model accuracy. */
import { fingerprintEvidence, fingerprintJson } from "./evidence.ts";
import type { ExploratoryCorpus } from "./exploratory.ts";
import { parsePhotoModelFacts } from "./photoModelContracts.ts";
import type {
  PrimaryReferenceReview,
  PrimaryReviewRole,
} from "./solPhotoPrimaryPreparationContracts.ts";
import { PRIMARY_REVIEW_ROLES } from "./solPhotoPrimaryPreparationContracts.ts";
import { normalizedTaxonomyName, type ReviewedTaxonomy } from "./taxonomy.ts";
import { member, requireCondition as check } from "./validation.ts";

export const PRIMARY_RESOLUTIONS = [
  "species",
  "genus",
  "family",
  "unresolved_biological",
  "non_biological",
] as const;

export async function primaryReferenceCoverage(
  corpus: ExploratoryCorpus,
  taxonomy: ReviewedTaxonomy,
  facts: ReturnType<typeof parsePhotoModelFacts>,
  review: PrimaryReferenceReview,
) {
  check(corpus.cases.length === 12 && facts.cards.length === 12);
  check(
    review.corpusDigest === await fingerprintJson(corpus) &&
      review.taxonomyDigest === await fingerprintJson(taxonomy) &&
      review.factsDigest === await fingerprintJson(facts),
  );
  const cases: {
    caseId: string;
    resolution: typeof PRIMARY_RESOLUTIONS[number];
    identitySupport: "usable_provisional" | "limited_reference";
    roles: PrimaryReviewRole[];
  }[] = [];
  for (const c of corpus.cases) {
    const r = review.cases.find((r) => r.caseId === c.input.caseId);
    const f = facts.cards.find((f) => f.caseId === c.input.caseId);
    const ref = c.provisionalReference;
    check(r && f && ref);
    check(
      c.input.inputGroup === "photos" &&
        c.input.observationTexts.length === 0 &&
        c.input.clips.length === 0 && c.input.assets.every((a) =>
          a.kind === "image"
        ),
    );
    check(
      r.inputDigest === await fingerprintEvidence(c.input) &&
        f.inputDigest === r.inputDigest &&
        r.referenceDigest === await fingerprintJson(ref) &&
        r.factsDigest === await fingerprintJson(f),
    );
    check(
      (corpus.evidenceOrigin === "synthetic") ===
        (r.source.kind === "synthetic"),
    );
    if (c.curation.kind === "eligibility_reviewed") {
      check(r.source.recordRef === c.curation.sourceRecordRef);
    }
    check(ref.subject === "biological" || ref.subject === "non_biological");
    const resolution = ref.subject === "non_biological"
      ? "non_biological"
      : ref.resolution === "unresolved"
      ? "unresolved_biological"
      : ref.supportedRank;
    member(resolution, PRIMARY_RESOLUTIONS);
    check(
      ref.subject !== "non_biological" ||
        f.requirements.includes("non_biological_reason"),
    );
    check(
      ref.subject !== "biological" || f.requirements.includes("rank_limit"),
    );
    check(
      ref.resolution !== "unresolved" ||
        f.requirements.includes("abstention_reason"),
    );
    for (const role of r.roles) {
      if (role === "mineral_object") check(resolution === "non_biological");
      else {
        check(resolution === "species");
        if (role === "species_lookalike") {
          // A confusable species is a comparison target, not another accepted answer.
          check(
            r.confusableTaxa.length > 0 && r.confusableTaxa.every((t) =>
              !ref.acceptableTaxa.some((accepted) => accepted.id === t.id) &&
              taxonomy.taxa.some((row) =>
                row.taxon.id === t.id && row.taxon.rank === "species"
              )
            ),
          );
          continue;
        }
        const name = role === "domestic_dog"
          ? "canis lupus familiaris"
          : "felis catus";
        check(
          ref.acceptableTaxa.some((t) =>
            taxonomy.taxa.some((row) =>
              row.taxon.id === t.id && row.taxon.rank === "species" &&
              normalizedTaxonomyName(row.canonicalName) === name
            )
          ),
        );
      }
    }
    cases.push({
      caseId: c.input.caseId,
      resolution,
      identitySupport: r.identitySupport,
      roles: r.roles,
    });
  }
  const bucket = (matching: typeof cases) => ({
    caseIds: matching.map((c) => c.caseId),
    usableProvisionalCaseIds: matching.filter((c) =>
      c.identitySupport === "usable_provisional"
    ).map((c) => c.caseId),
    limitedReferenceCaseIds: matching.filter((c) =>
      c.identitySupport === "limited_reference"
    ).map((c) => c.caseId),
  });
  const resolutions = Object.fromEntries(
    PRIMARY_RESOLUTIONS.map((
      resolution,
    ) => [
      resolution,
      bucket(cases.filter((c) => c.resolution === resolution)),
    ]),
  );
  const roles = Object.fromEntries(
    PRIMARY_REVIEW_ROLES.map((role) => [
      role,
      bucket(cases.filter((c) => c.roles.includes(role))),
    ]),
  );
  const missing = Object.entries({ ...resolutions, ...roles })
    .filter(([, row]) => row.caseIds.length === 0).map(([key]) => key);
  const limitedOnly = Object.entries({ ...resolutions, ...roles })
    .filter(([, row]) =>
      row.caseIds.length > 0 && row.usableProvisionalCaseIds.length === 0
    )
    .map(([key]) => key);
  return {
    version: "sol_photo_primary_coverage_v1" as const,
    evidenceStatus: corpus.evidenceOrigin === "synthetic"
      ? "synthetic_mechanics_only"
      : "provisional_development_cases",
    independentTruthVerified: false,
    qualityQualified: false,
    catalogCoverage: "finite_not_exhaustive",
    referenceCoverage: missing.length
      ? "missing_cases"
      : limitedOnly.length
      ? "present_with_reference_limits"
      : "provisional_cases_present",
    missing,
    limitedOnly,
    resolutions,
    roles,
    limitedReferenceCaseIds: cases.filter((c) =>
      c.identitySupport === "limited_reference"
    ).map((c) => c.caseId),
  };
}
