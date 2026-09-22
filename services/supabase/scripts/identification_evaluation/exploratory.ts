/** Separate development evidence. It never satisfies the formal corpus contract. */
import type {
  EvaluationCorpus,
  EvaluationInput,
  ReferenceLabel,
} from "./contracts.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  array,
  fields,
  id,
  integer,
  member,
  parseEvaluationCorpus,
  parseEvaluationInput,
  requireCondition as check,
  token,
  validateInputSeparation,
  validateReference,
} from "./validation.ts";

export const EXPLORATORY_CORPUS_VERSION =
  "identification_exploratory_corpus_v1" as const;
export const EXPLORATORY_SPEC_VERSION =
  "identification_exploratory_run_spec_v1" as const;
export interface ExploratoryCase {
  input: EvaluationInput;
  provisionalReference: ReferenceLabel | null;
  curation: { kind: "synthetic" } | {
    kind: "eligibility_reviewed";
    source: "purpose_collected" | "licensed";
    sourceRecordRef: string;
    referenceRecordRef: string | null;
    permission: "gemini_evaluation";
    rightsApproved: true;
    personalDataExcluded: true;
    nearDuplicatesReviewed: true;
  };
}
export interface ExploratoryCorpus {
  version: typeof EXPLORATORY_CORPUS_VERSION;
  id: string;
  kind: "exploratory";
  evidenceOrigin: "real" | "synthetic";
  taxonomyVersion: string;
  preparationVersion: string;
  splitSeed: number;
  eligibility: null | {
    recordRef: string;
    reviewerRef: string;
    reviewerKind: "owner" | "automated";
    retainUntil: string;
  };
  cases: ExploratoryCase[];
}
export type RunCorpus = EvaluationCorpus | ExploratoryCorpus;

export function parseExploratoryCorpus(value: unknown): ExploratoryCorpus {
  const v = fields(value, [
    "version",
    "id",
    "kind",
    "evidenceOrigin",
    "taxonomyVersion",
    "preparationVersion",
    "splitSeed",
    "eligibility",
    "cases",
  ]);
  check(v.version === EXPLORATORY_CORPUS_VERSION && v.kind === "exploratory");
  member(v.evidenceOrigin, ["real", "synthetic"]);
  for (const k of ["id", "taxonomyVersion", "preparationVersion"]) token(v[k]);
  integer(v.splitSeed, 0, 0xffffffff);
  const synthetic = v.evidenceOrigin === "synthetic";
  if (synthetic) check(v.eligibility === null);
  else {
    const e = fields(v.eligibility, [
      "recordRef",
      "reviewerRef",
      "reviewerKind",
      "retainUntil",
    ]);
    token(e.recordRef);
    id(e.reviewerRef, "r");
    member(e.reviewerKind, ["owner", "automated"]);
    check(
      typeof e.retainUntil === "string" &&
        /^\d{4}-\d{2}-\d{2}$/.test(e.retainUntil) &&
        Number.isFinite(Date.parse(e.retainUntil)) &&
        new Date(e.retainUntil).toISOString().slice(0, 10) === e.retainUntil,
    );
  }
  const inputs = array(v.cases, 1, 12).map((raw) => {
    const c = fields(raw, ["input", "provisionalReference", "curation"]);
    const input = parseEvaluationInput(c.input);
    check(input.split === "development");
    if (c.provisionalReference !== null) {
      validateReference(c.provisionalReference, synthetic);
    }
    if (synthetic) check(fields(c.curation, ["kind"]).kind === "synthetic");
    else {
      const r = fields(c.curation, [
        "kind",
        "source",
        "sourceRecordRef",
        "referenceRecordRef",
        "permission",
        "rightsApproved",
        "personalDataExcluded",
        "nearDuplicatesReviewed",
      ]);
      check(
        r.kind === "eligibility_reviewed" &&
          r.permission === "gemini_evaluation" && r.rightsApproved === true &&
          r.personalDataExcluded === true && r.nearDuplicatesReviewed === true,
      );
      member(r.source, ["purpose_collected", "licensed"]);
      token(r.sourceRecordRef);
      if (c.provisionalReference === null) check(r.referenceRecordRef === null);
      else token(r.referenceRecordRef);
    }
    return input;
  });
  validateInputSeparation(inputs);
  return structuredClone(v) as unknown as ExploratoryCorpus;
}
export function parseRunCorpus(value: unknown): RunCorpus {
  return value !== null && typeof value === "object" && "kind" in value &&
      value.kind === "exploratory"
    ? parseExploratoryCorpus(value)
    : parseEvaluationCorpus(value);
}
export function fingerprintRunCorpus(value: unknown): Promise<string> {
  return fingerprintJson(parseRunCorpus(value));
}
export function isSyntheticCorpus(corpus: RunCorpus): boolean {
  return corpus.kind === "synthetic" ||
    corpus.kind === "exploratory" && corpus.evidenceOrigin === "synthetic";
}
export function referenceLabels(corpus: RunCorpus): ReferenceLabel[] {
  return corpus.kind === "exploratory"
    ? corpus.cases.flatMap((c) =>
      c.provisionalReference ? [c.provisionalReference] : []
    )
    : corpus.cases.map((c) => c.reference);
}
export function corpusRetention(corpus: RunCorpus): string | null {
  return (corpus.kind === "exploratory"
    ? corpus.eligibility?.retainUntil
    : corpus.approval?.retainUntil) ?? null;
}
