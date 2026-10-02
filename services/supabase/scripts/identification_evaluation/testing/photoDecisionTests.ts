import { assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import {
  confidenceFixture,
  confidenceOutcome,
  confidenceSource,
} from "./confidenceFixtures.ts";
import { atomicJson, claimJson, privateDirectory, readJson } from "../files.ts";
import { fingerprintJson } from "../evidence.ts";
import { projectConfidenceOutcome } from "../confidenceProjection.ts";
import { type PhotoDecisionStudy } from "../photoDecisionPreparation.ts";
import {
  freezePhotoValidation,
  photoDecisionReport,
  readPhotoDecision,
} from "../photoDecisionRunner.ts";
import { validateDecisionExposure } from "../photoDecisionExposure.ts";
import { PHOTO_DECISION_PROTOCOL as P } from "../photoDecisionStatistics.ts";

function fixture(): PhotoDecisionStudy {
  const { corpus, taxonomy, pricing } = confidenceFixture();
  const development = corpus.cases.filter((c) =>
    c.input.split === "development"
  ).slice(0, 20);
  const validation = corpus.cases.filter((c) => c.input.split === "held_out");
  const assignments = development.flatMap((c) =>
    (["released", "evidence"] as const).map((arm) => ({
      key: `development-${c.input.caseId}-${arm}`,
      phase: "development" as const,
      caseId: c.input.caseId,
      arm,
      requestDigest: "1".repeat(64),
      settingsDigest: "2".repeat(64),
      reservedNanoUsd: 6_000_000_000,
      gemini: null,
    }))
  );
  // Only ledger mechanics; this object can never pass real-input preparation.
  return {
    plan: {},
    corpus,
    taxonomy,
    development,
    validation,
    openaiPricing: pricing,
    geminiPricing: {} as PhotoDecisionStudy["geminiPricing"],
    digest: "3".repeat(64),
    manifest: {
      version: "photo_decision_manifest_v1",
      protocol: P,
      source: confidenceSource,
      planDigest: "4".repeat(64),
      corpusDigest: "5".repeat(64),
      taxonomyDigest: "6".repeat(64),
      evidenceDigest: null,
      openaiPricingDigest: "7".repeat(64),
      geminiPricingDigest: "8".repeat(64),
      assignments,
    },
  };
}
async function writeResult(
  root: string,
  study: PhotoDecisionStudy,
  index: number,
  unknown = false,
) {
  const a = study.manifest.assignments[index];
  const claim = {
    version: "photo_decision_claim_v1",
    manifestDigest: study.digest,
    assignment: a,
  };
  const base = join(root, "decision-attempts", a.key);
  await claimJson(base + ".claim.json", claim);
  let outcome = confidenceOutcome(
    study.development.find((c) => c.input.caseId === a.caseId)!,
  );
  if (unknown) outcome = { ...outcome, usage: null };
  const p = projectConfidenceOutcome(
    a.caseId,
    outcome,
    study.taxonomy,
    study.openaiPricing,
  );
  const named = p.observation.prediction.outcome === "normalized" &&
    p.observation.prediction.resolution === "named";
  await claimJson(base + ".result.json", {
    version: "photo_decision_result_v1",
    claimDigest: await fingerprintJson(claim),
    observation: p.observation,
    accounting: p.accounting,
    geminiRecord: null,
    settledNanoUsd: p.settledNanoUsd === null
      ? null
      : Math.ceil(p.settledNanoUsd * 1.1),
    providerDurationMs: 20,
    primaryNameDigest: named ? "9".repeat(64) : null,
    nameForm: named ? "plain" : null,
  });
}
export function registerPhotoDecisionTests(scratch: string) {
  Deno.test("photo decision missing result consumes claim and retains reservation without replay", async () => {
    const root = await privateDirectory(
        join(scratch, "photo-decision-interrupt"),
      ),
      study = fixture();
    await readPhotoDecision(root, study);
    const a = study.manifest.assignments[0];
    await claimJson(join(root, "decision-attempts", a.key + ".claim.json"), {
      version: "photo_decision_claim_v1",
      manifestDigest: study.digest,
      assignment: a,
    });
    const ledger = await readPhotoDecision(root, study);
    assertEquals(ledger.attempted, 1);
    assertEquals(ledger.outstandingNanoUsd, 6_000_000_000);
    assertEquals(ledger.stop, "interrupted_attempt");
    assertEquals((await photoDecisionReport(root, study)).next, null);
    await assertRejects(() => freezePhotoValidation(root, study));
  });
  Deno.test("photo decision unknown usage retains reservation and rejects tampered settlement", async () => {
    const root = await privateDirectory(
        join(scratch, "photo-decision-unknown"),
      ),
      study = fixture();
    await readPhotoDecision(root, study);
    await writeResult(root, study, 0, true);
    const ledger = await readPhotoDecision(root, study);
    assertEquals(ledger.stop, "accounting_incomplete");
    assertEquals(ledger.outstandingNanoUsd, 6_000_000_000);
    const path = join(
      root,
      "decision-attempts",
      study.manifest.assignments[0].key + ".result.json",
    );
    const value = await readJson(path) as Record<string, unknown>;
    value.settledNanoUsd = 0;
    await atomicJson(path, value);
    await assertRejects(() => readPhotoDecision(root, study));
  });
  Deno.test("photo decision freezes selection once from all forty development outcomes", async () => {
    const root = await privateDirectory(join(scratch, "photo-decision-select")),
      study = fixture();
    await readPhotoDecision(root, study);
    for (let i = 0; i < 40; i++) await writeResult(root, study, i);
    const selection = await freezePhotoValidation(root, study);
    assertEquals(selection.selection.selected, false);
    assertEquals(
      (await readPhotoDecision(root, study)).selection?.selected,
      false,
    );
    const path = join(root, "validation-freeze.json");
    const value = await readJson(path) as Record<string, unknown>;
    value.developmentResultsDigest = "0".repeat(64);
    await atomicJson(path, value);
    await assertRejects(() => readPhotoDecision(root, study));
  });
  Deno.test("photo exposure receipt binds exact assets, splits and previously attempted status", async () => {
    const { corpus } = confidenceFixture();
    const ids = corpus.cases.filter((c) => c.input.split === "development")
      .slice(0, 20).map((c) => c.input.caseId);
    for (const c of corpus.cases) {
      c.curation = {
        kind: "reviewed",
        permission: "openai_evaluation",
        sourceRecordRef: "source",
        referenceRecordRef: "reference",
        answerabilityRecordRef: "answerability",
        independentEvidenceRefs: ["independent"],
        reviewMethod: "source_grounded_visibility_v1",
        reviewerRef: "reviewer",
        independentHumanValidation: false,
        rightsApproved: true,
        personalDataExcluded: true,
        nearDuplicatesReviewed: true,
        referenceVerified: true,
        developmentOnly: false,
      };
    }
    const validationIds = corpus.cases.filter((c) =>
      c.input.split === "held_out"
    ).slice(0, 60).map((c) => c.input.caseId);
    const selected = corpus.cases.filter((c) =>
      validationIds.includes(c.input.caseId) || ids.includes(c.input.caseId)
    );
    const value = {
      version: "photo_decision_exposure_v1",
      reviewRef: "synthetic",
      reviewedAt: "2026-10-01T00:00:00.000Z",
      corpusDigest: await fingerprintJson(corpus),
      priorJournalDigest: "0".repeat(64),
      inventoryDigest: "1".repeat(64),
      scope: "available_local_records_only",
      independentHumanValidation: false,
      clusters: corpus.cases.map((c) => ({
        caseId: c.input.caseId,
        clusterId: c.input.groupId,
      })),
      cases: selected.map((c) => ({
        caseId: c.input.caseId,
        groupId: c.input.groupId,
        assetDigests: c.input.assets.map((a) => a.sha256),
        priorAttempted: c.input.split === "development",
        sourceAndNearDuplicatesReviewed: true,
      })),
    };
    await validateDecisionExposure(value, corpus, ids, validationIds);
    const firstValidation = value.clusters.find((c) =>
      c.caseId === validationIds[0]
    )!;
    const oldCluster = firstValidation.clusterId;
    firstValidation.clusterId =
      value.clusters.find((c) => c.caseId === ids[0])!.clusterId;
    await assertRejects(() =>
      validateDecisionExposure(value, corpus, ids, validationIds)
    );
    firstValidation.clusterId =
      value.clusters.find((c) => c.caseId === validationIds[1])!.clusterId;
    await assertRejects(() =>
      validateDecisionExposure(value, corpus, ids, validationIds)
    );
    firstValidation.clusterId = oldCluster;
    value.cases[0].assetDigests = ["f".repeat(64)];
    await assertRejects(() =>
      validateDecisionExposure(value, corpus, ids, validationIds)
    );
  });
}
