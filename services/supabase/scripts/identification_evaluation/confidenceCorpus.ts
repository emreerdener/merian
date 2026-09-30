import type { EvaluationInput, ReferenceLabel } from "./contracts.ts";
import {
  CONFIDENCE_PROTOCOL as P,
  type ConfidenceCategory,
  type ConfidenceGroup,
} from "./confidenceProtocol.ts";
import {
  array,
  fields,
  member,
  parseEvaluationInput,
  requireCondition as check,
  token,
  validateReference,
} from "./validation.ts";
import { parseTaxonomy, type ReviewedTaxonomy } from "./taxonomy.ts";
import { fingerprintJson } from "./evidence.ts";
import { assignConfidenceSplits } from "./confidenceSampling.ts";

export interface ConfidenceCase {
  input: EvaluationInput;
  reference: ReferenceLabel;
  category: ConfidenceCategory;
  taxaGroup: ConfidenceGroup;
  curation: { kind: "synthetic" } | {
    kind: "reviewed";
    permission: "openai_evaluation";
    sourceRecordRef: string;
    referenceRecordRef: string;
    answerabilityRecordRef: string;
    independentEvidenceRefs: string[];
    reviewMethod: typeof P.referenceReviewMethod;
    reviewerRef: string;
    independentHumanValidation: false;
    rightsApproved: true;
    personalDataExcluded: true;
    nearDuplicatesReviewed: true;
    referenceVerified: true;
    developmentOnly: boolean;
  };
}
export interface ConfidenceCorpus {
  version: typeof P.corpusVersion;
  kind: "synthetic" | "reference";
  id: string;
  splitSeed: typeof P.splitSeed;
  taxonomyVersion: string;
  referenceStatus: "valid" | "invalidated";
  cases: ConfidenceCase[];
}
/** Does not silently relabel, resplit, omit, or repair an observation. */
export function parseConfidenceCorpus(value: unknown, taxonomyValue: unknown): {
  corpus: ConfidenceCorpus;
  taxonomy: ReviewedTaxonomy;
} {
  const v = fields(value, [
    "version",
    "kind",
    "id",
    "splitSeed",
    "taxonomyVersion",
    "referenceStatus",
    "cases",
  ]);
  check(v.version === P.corpusVersion && v.splitSeed === P.splitSeed);
  member(v.kind, ["synthetic", "reference"]);
  member(v.referenceStatus, ["valid", "invalidated"]);
  token(v.id);
  token(v.taxonomyVersion);
  const taxonomy = parseTaxonomy(taxonomyValue);
  check(
    taxonomy.version === "evaluation_taxonomy_v2" &&
      taxonomy.taxonomyVersion === v.taxonomyVersion,
  );
  const ids = new Set<string>(),
    groups = new Map<string, string>(),
    hashes = new Set<string>();
  for (const raw of array(v.cases, 200, 200)) {
    const c = fields(raw, [
      "input",
      "reference",
      "category",
      "taxaGroup",
      "curation",
    ]);
    const input = parseEvaluationInput(c.input);
    check(
      input.inputGroup === "photos" && input.observationTexts.length === 0 &&
        input.clips.length === 0 && input.assets.length > 0 &&
        input.assets.every((a) => a.kind === "image"),
    );
    check(!ids.has(input.caseId), "duplicate_case");
    ids.add(input.caseId);
    check(
      !groups.has(input.groupId) || groups.get(input.groupId) === input.split,
      "split_leakage",
    );
    groups.set(input.groupId, input.split);
    for (const asset of input.assets) {
      check(!hashes.has(asset.sha256), "duplicate_evidence");
      hashes.add(asset.sha256);
    }
    validateReference(c.reference, v.kind === "synthetic");
    const ref = c.reference as ReferenceLabel;
    check(ref.subject !== "human", "invalid_reference");
    for (const accepted of ref.acceptableTaxa) {
      check(
        taxonomy.taxa.some((t) =>
          t.taxon.id === accepted.id && t.taxon.rank === accepted.rank
        ),
        "invalid_reference",
      );
    }
    member(c.category, P.categories);
    member(c.taxaGroup, [...P.taxaGroups, "none"]);
    if (c.category === "nonbiological") {
      check(
        c.taxaGroup === "none" && ref.subject === "non_biological" &&
          ref.resolution === "unresolved",
      );
    } else {
      check(ref.subject === "biological" && c.taxaGroup !== "none");
      if (c.category === "cultivated") check(c.taxaGroup === "plant");
      if (c.category === "limited") {
        check(ref.supportedRank === "genus" || ref.resolution === "unresolved");
      } else {check(
          ref.supportedRank === "species" && ref.resolution === "named",
        );}
    }
    if (v.kind === "synthetic") {
      check(fields(c.curation, ["kind"]).kind === "synthetic");
    } else {
      const r = fields(c.curation, [
        "kind",
        "permission",
        "sourceRecordRef",
        "referenceRecordRef",
        "answerabilityRecordRef",
        "independentEvidenceRefs",
        "reviewMethod",
        "reviewerRef",
        "independentHumanValidation",
        "rightsApproved",
        "personalDataExcluded",
        "nearDuplicatesReviewed",
        "referenceVerified",
        "developmentOnly",
      ]);
      check(
        r.kind === "reviewed" && r.permission === "openai_evaluation" &&
          r.rightsApproved === true && r.personalDataExcluded === true &&
          r.nearDuplicatesReviewed === true && r.referenceVerified === true,
        "unapproved_evidence",
      );
      token(r.sourceRecordRef);
      token(r.referenceRecordRef);
      token(r.answerabilityRecordRef);
      token(r.reviewerRef);
      const evidence = array(r.independentEvidenceRefs, 1, 8);
      evidence.forEach(token);
      check(new Set(evidence).size === evidence.length, "invalid_reference");
      check(
        new Set([
              r.sourceRecordRef,
              r.referenceRecordRef,
              r.answerabilityRecordRef,
            ]).size === 3 &&
          evidence.every((ref) =>
            ![
              r.sourceRecordRef,
              r.referenceRecordRef,
              r.answerabilityRecordRef,
            ].includes(ref)
          ) &&
          r.reviewMethod === P.referenceReviewMethod &&
          r.independentHumanValidation === false,
        "invalid_reference",
      );
      check(typeof r.developmentOnly === "boolean");
    }
  }
  const corpus = structuredClone(v) as unknown as ConfidenceCorpus;
  const seeded = assignConfidenceSplits(corpus.cases);
  check(
    seeded.every((c, i) => c.input.split === corpus.cases[i].input.split),
    "split_leakage",
  );
  for (const split of ["development", "held_out"]) {
    const cases = corpus.cases.filter((c) => c.input.split === split);
    check(cases.length === P.casesPerSplit);
    for (const category of P.categories) {
      const members = cases.filter((c) => c.category === category);
      check(members.length === 20);
      if (["clear", "lookalike", "limited"].includes(category)) {
        for (const group of P.taxaGroups) {
          check(members.filter((c) => c.taxaGroup === group).length === 5);
        }
      }
      if (category === "limited") {
        check(
          members.filter((c) => c.reference.supportedRank === "genus")
                .length === 10 &&
            members.filter((c) => c.reference.resolution === "unresolved")
                .length === 10,
        );
      }
    }
  }
  return { corpus, taxonomy };
}

/** Fixed within-split dispatch order, independent of scores or filesystem order. */
export async function confidenceOrder(
  corpus: ConfidenceCorpus,
): Promise<ConfidenceCase[]> {
  const keyed = await Promise.all(corpus.cases.map(async (c) => ({
    c,
    key: await fingerprintJson({ seed: P.splitSeed, group: c.input.groupId }),
  })));
  return keyed.sort((
    a,
    b,
  ) => (a.c.input.split === b.c.input.split
    ? a.key.localeCompare(b.key)
    : a.c.input.split === "development"
    ? -1
    : 1)
  ).map((v) => v.c);
}
