import { join } from "node:path";
import type { ReferenceLabel } from "./contracts.ts";
import type { ConfidenceCorpus } from "./confidenceCorpus.ts";
import { fingerprintJson } from "./evidence.ts";
import { readJson } from "./files.ts";
import {
  array,
  fields,
  member,
  requireCondition as check,
  text,
  token,
  validateReference,
} from "./validation.ts";

/** Private reviewed facts, never provider input or prediction/report prose. */
export interface ConfidenceEvidenceRecord {
  id: string;
  kind: "source" | "reference" | "answerability" | "independent";
  reviewerRef: string;
  caseId: string | null;
  assetDigests: string[];
  reference: ReferenceLabel | null;
  relatedRefs: string[];
  sourceUrls: string[];
  sourceRevisionRefs: string[];
  findings: string[];
}
export interface ConfidenceEvidence {
  version: "openai_confidence_evidence_v1";
  records: ConfidenceEvidenceRecord[];
}

const same = async (a: unknown, b: unknown) =>
  await fingerprintJson(a) === await fingerprintJson(b);
function strings(value: unknown, min: number, max: number) {
  const values = array(value, min, max);
  values.forEach(token);
  check(new Set(values).size === values.length, "invalid_reference");
  return values as string[];
}

/** Freeze the record contents behind every curation reference, not just its ID. */
export async function confidenceEvidenceDigest(
  root: string,
  corpus: ConfidenceCorpus,
): Promise<string | null> {
  if (corpus.kind === "synthetic") return null;
  const bundle = fields(
    await readJson(join(root, "confidence-evidence.json")),
    [
      "version",
      "records",
    ],
  );
  check(bundle.version === "openai_confidence_evidence_v1");
  const records = new Map<string, ConfidenceEvidenceRecord>();
  for (const raw of array(bundle.records, 1, 2200)) {
    const r = fields(raw, [
      "id",
      "kind",
      "reviewerRef",
      "caseId",
      "assetDigests",
      "reference",
      "relatedRefs",
      "sourceUrls",
      "sourceRevisionRefs",
      "findings",
    ]);
    token(r.id);
    token(r.reviewerRef);
    check(!records.has(r.id), "invalid_reference");
    member(r.kind, ["source", "reference", "answerability", "independent"]);
    if (r.caseId !== null) token(r.caseId);
    for (const digest of strings(r.assetDigests, 0, 10)) {
      check(/^[a-f0-9]{64}$/.test(digest));
    }
    strings(r.relatedRefs, 0, 10);
    strings(r.sourceRevisionRefs, 0, 16);
    for (const source of array(r.sourceUrls, 0, 8)) {
      text(source, 2048);
      const url = new URL(source);
      check(url.protocol === "https:" && !url.username && !url.password);
    }
    array(r.findings, 1, 32).forEach((v) => text(v));
    if (r.reference !== null) validateReference(r.reference, false);
    records.set(r.id, r as unknown as ConfidenceEvidenceRecord);
  }
  const used = new Set<string>();
  function get(id: string, kind: ConfidenceEvidenceRecord["kind"]) {
    const record = records.get(id);
    check(record?.kind === kind, "invalid_reference");
    used.add(id);
    return record;
  }
  for (const c of corpus.cases) {
    const r = c.curation;
    check(r.kind === "reviewed");
    const assets = c.input.assets.map((a) => a.sha256).toSorted();
    for (
      const [ref, kind, related, reference] of [
        [r.sourceRecordRef, "source", [], null],
        [
          r.referenceRecordRef,
          "reference",
          [r.sourceRecordRef, ...r.independentEvidenceRefs],
          c.reference,
        ],
        [
          r.answerabilityRecordRef,
          "answerability",
          [
            r.sourceRecordRef,
            r.referenceRecordRef,
            ...r.independentEvidenceRefs,
          ],
          c.reference,
        ],
      ] as const
    ) {
      const record = get(ref, kind);
      check(
        record.caseId === c.input.caseId &&
          record.reviewerRef === r.reviewerRef &&
          (kind !== "source" || record.sourceRevisionRefs.length > 0) &&
          await same(record.assetDigests.toSorted(), assets) &&
          await same(record.reference, reference) &&
          await same(record.relatedRefs.toSorted(), [...related].toSorted()),
        "invalid_reference",
      );
    }
    for (const ref of r.independentEvidenceRefs) {
      const record = get(ref, "independent");
      check(
        record.caseId === null && record.reference === null &&
          record.assetDigests.length === 0 && record.relatedRefs.length === 0 &&
          record.sourceUrls.length > 0 && record.sourceRevisionRefs.length > 0,
        "invalid_reference",
      );
    }
  }
  check(used.size === records.size, "invalid_reference");
  return await fingerprintJson(bundle);
}
