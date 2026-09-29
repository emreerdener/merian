/** Offline preparation identities; neither object grants execution authority. */
import { hash, timestamp, unique } from "./runContracts.ts";
import type { Taxon } from "./contracts.ts";
import {
  array,
  fields,
  id,
  member,
  requireCondition as check,
  taxon,
  text,
  token,
} from "./validation.ts";

export const PRIMARY_REVIEW_ROLES = [
  "domestic_dog",
  "domestic_cat",
  "species_lookalike",
  "mineral_object",
] as const;
export type PrimaryReviewRole = typeof PRIMARY_REVIEW_ROLES[number];
export interface PrimaryPreparationPlan {
  version: "sol_photo_primary_preparation_plan_v1";
  corpusDigest: string;
  taxonomyDigest: string;
  factsDigest: string;
  referenceReviewDigest: string;
  screenCaseIds: string[];
  challengeCaseIds: string[];
}
export function parsePrimaryPreparationPlan(value: unknown) {
  const v = fields(value, [
    "version",
    "corpusDigest",
    "taxonomyDigest",
    "factsDigest",
    "referenceReviewDigest",
    "screenCaseIds",
    "challengeCaseIds",
  ]);
  check(v.version === "sol_photo_primary_preparation_plan_v1");
  for (
    const k of [
      "corpusDigest",
      "taxonomyDigest",
      "factsDigest",
      "referenceReviewDigest",
    ]
  ) hash(v[k]);
  const ids = [
    ...array(v.screenCaseIds, 6, 6),
    ...array(v.challengeCaseIds, 6, 6),
  ];
  ids.forEach((v) => id(v, "c"));
  unique(ids);
  return structuredClone(v) as unknown as PrimaryPreparationPlan;
}

type Source = { kind: "retained_review" | "synthetic"; recordRef: string } | {
  kind: "public_source";
  recordRef: string;
  page: string;
  asset: string;
  license: "public_domain" | "cc_by_4_0";
  attribution: string;
};
export interface PrimaryReferenceReview {
  version: "sol_photo_primary_reference_review_v1";
  corpusDigest: string;
  taxonomyDigest: string;
  factsDigest: string;
  method: "assistant_input_review_v1";
  reviewerRef: string;
  reviewedAt: string;
  catalogCoverage: "finite_not_exhaustive";
  independentTruthVerified: false;
  cases: {
    caseId: string;
    inputDigest: string;
    referenceDigest: string;
    factsDigest: string;
    identitySupport: "usable_provisional" | "limited_reference";
    missingEvidenceRecorded: true;
    roles: PrimaryReviewRole[];
    confusableTaxa: Taxon[];
    source: Source;
  }[];
}
export function parsePrimaryReferenceReview(value: unknown) {
  const v = fields(value, [
    "version",
    "corpusDigest",
    "taxonomyDigest",
    "factsDigest",
    "method",
    "reviewerRef",
    "reviewedAt",
    "catalogCoverage",
    "independentTruthVerified",
    "cases",
  ]);
  check(
    v.version === "sol_photo_primary_reference_review_v1" &&
      v.method === "assistant_input_review_v1" &&
      v.catalogCoverage === "finite_not_exhaustive" &&
      v.independentTruthVerified === false,
  );
  for (const k of ["corpusDigest", "taxonomyDigest", "factsDigest"]) hash(v[k]);
  token(v.reviewerRef);
  timestamp(v.reviewedAt);
  const cases = array(v.cases, 12, 12).map((raw) => {
    const c = fields(raw, [
      "caseId",
      "inputDigest",
      "referenceDigest",
      "factsDigest",
      "identitySupport",
      "missingEvidenceRecorded",
      "roles",
      "confusableTaxa",
      "source",
    ]);
    id(c.caseId, "c");
    for (const k of ["inputDigest", "referenceDigest", "factsDigest"]) {
      hash(c[k]);
    }
    member(c.identitySupport, ["usable_provisional", "limited_reference"]);
    check(c.missingEvidenceRecorded === true);
    const roles = array(c.roles, 0, PRIMARY_REVIEW_ROLES.length);
    roles.forEach((r) => member(r, PRIMARY_REVIEW_ROLES));
    unique(roles);
    const confusable = array(c.confusableTaxa, 0, 8).map(taxon);
    check(confusable.every((t) => t.rank === "species"));
    unique(confusable.map((t) => t.id));
    check(roles.includes("species_lookalike") === (confusable.length > 0));
    check(c.source !== null && typeof c.source === "object");
    const publicSource = "kind" in c.source &&
      c.source.kind === "public_source";
    const s = fields(
      c.source,
      publicSource
        ? ["kind", "recordRef", "page", "asset", "license", "attribution"]
        : ["kind", "recordRef"],
    );
    token(s.recordRef);
    if (publicSource) {
      member(s.license, ["public_domain", "cc_by_4_0"]);
      text(s.attribution, 200);
      for (const k of ["page", "asset"]) {
        text(s[k], 1000);
        const url = new URL(s[k] as string);
        check(
          url.protocol === "https:" && !url.username && !url.password &&
            !url.hash,
        );
      }
    } else member(s.kind, ["retained_review", "synthetic"]);
    return c;
  });
  unique(cases.map((c) => c.caseId));
  return structuredClone(v) as unknown as PrimaryReferenceReview;
}
