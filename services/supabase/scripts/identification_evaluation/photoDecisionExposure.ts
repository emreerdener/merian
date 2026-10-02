import type { ConfidenceCorpus } from "./confidenceCorpus.ts";
import {
  array,
  fields,
  requireCondition as check,
  token,
} from "./validation.ts";
import { hash, timestamp } from "./runContracts.ts";
import { fingerprintJson } from "./evidence.ts";

/** An explicit review receipt, not a claim to discover unrecorded outside exposure. */
export async function validateDecisionExposure(
  value: unknown,
  corpus: ConfidenceCorpus,
  developmentIds: readonly string[],
  validationIds: readonly string[],
) {
  const v = fields(value, [
    "version",
    "reviewRef",
    "reviewedAt",
    "corpusDigest",
    "priorJournalDigest",
    "inventoryDigest",
    "scope",
    "independentHumanValidation",
    "cases",
    "clusters",
  ]);
  check(
    v.version === "photo_decision_exposure_v1" &&
      v.scope === "available_local_records_only" &&
      v.independentHumanValidation === false,
  );
  token(v.reviewRef);
  timestamp(v.reviewedAt);
  hash(v.corpusDigest);
  hash(v.priorJournalDigest);
  hash(v.inventoryDigest);
  check(v.corpusDigest === await fingerprintJson(corpus));
  const selected = corpus.cases.filter((c) =>
    validationIds.includes(c.input.caseId) ||
    developmentIds.includes(c.input.caseId)
  );
  const clusters = array(v.clusters, 200, 200).map((raw) => {
    const r = fields(raw, ["caseId", "clusterId"]);
    token(r.caseId);
    token(r.clusterId);
    return { caseId: String(r.caseId), clusterId: String(r.clusterId) };
  });
  check(
    new Set(clusters.map((r) => r.caseId)).size === 200 &&
      corpus.cases.every((c) =>
        clusters.some((r) => r.caseId === c.input.caseId)
      ),
  );
  const exposed = new Set(
    corpus.cases.filter((c) => c.input.split === "development").map((c) =>
      clusters.find((r) => r.caseId === c.input.caseId)!.clusterId
    ),
  );
  const chosen = validationIds.map((id) =>
    clusters.find((r) => r.caseId === id)!.clusterId
  );
  check(
    new Set(chosen).size === chosen.length &&
      chosen.every((id) => !exposed.has(id)),
  );
  const records = array(v.cases, 80, 80);
  const ids = new Set<string>();
  for (const raw of records) {
    const r = fields(raw, [
      "caseId",
      "groupId",
      "assetDigests",
      "priorAttempted",
      "sourceAndNearDuplicatesReviewed",
    ]);
    token(r.caseId);
    token(r.groupId);
    check(!ids.has(String(r.caseId)));
    ids.add(String(r.caseId));
    const c = selected.find((c) => c.input.caseId === r.caseId);
    check(
      c && r.groupId === c.input.groupId &&
        r.sourceAndNearDuplicatesReviewed === true,
    );
    check(
      await fingerprintJson(r.assetDigests) ===
        await fingerprintJson(c.input.assets.map((a) => a.sha256)),
    );
    check(r.priorAttempted === (c.input.split === "development"));
    check(
      c.curation.kind === "reviewed" &&
        (c.input.split !== "held_out" || !c.curation.developmentOnly),
    );
  }
  check(
    selected.length === ids.size &&
      selected.every((c) => ids.has(c.input.caseId)),
  );
}
