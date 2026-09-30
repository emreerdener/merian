import { join } from "node:path";
import type { AIAdapter } from "../../functions/_shared/ai/contracts.ts";
import { createAIExecution } from "../../functions/_shared/ai/execution.ts";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import { prepareEvidence } from "./assets.ts";
import { CONFIDENCE_PROTOCOL as P } from "./confidenceProtocol.ts";
import { fingerprintJson } from "./evidence.ts";
import {
  atomicJson,
  claimJson,
  exists,
  readJson,
  withRunLock,
} from "./files.ts";
import {
  confidenceClaim,
  type ConfidenceLedger,
  readConfidenceLedger,
} from "./confidenceLedger.ts";
import {
  prepareConfidenceStudy,
  type PreparedConfidenceStudy,
} from "./confidencePreparation.ts";
import { projectConfidenceOutcome } from "./confidenceProjection.ts";
import {
  confidenceAssessment,
  confidenceRows,
  selectConfidenceCutoff,
} from "./confidenceScoring.ts";
import type { SourceIdentity } from "./runContracts.ts";
import { fields, requireCondition as check, token } from "./validation.ts";

async function invalidated(root: string, study: PreparedConfidenceStudy) {
  const path = join(root, "confidence-invalidation.json");
  if (!await exists(path)) return study.corpus.referenceStatus !== "valid";
  const v = fields(await readJson(path), [
    "version",
    "manifestDigest",
    "reviewRef",
  ]);
  check(
    v.version === "openai_confidence_invalidation_v1" &&
      v.manifestDigest === study.digest,
  );
  token(v.reviewRef);
  return true;
}

async function selectionRecord(
  study: PreparedConfidenceStudy,
  ledger: ConfidenceLedger,
) {
  const development = study.cases.filter((c) =>
    c.input.split === "development"
  );
  const ids = new Set(development.map((c) => c.input.caseId));
  const values = ledger.observations.filter((v) =>
    ids.has(v.prediction.caseId)
  );
  const cutoff = selectConfidenceCutoff(confidenceRows(development, values));
  return {
    version: "openai_confidence_selection_v1",
    manifestDigest: study.digest,
    developmentDigest: await fingerprintJson(values),
    cutoff,
    cutoffDigest: await fingerprintJson({
      strong: cutoff,
      possible: P.possible,
    }),
  };
}
async function readSelection(
  root: string,
  study: PreparedConfidenceStudy,
  ledger: ConfidenceLedger,
) {
  const path = join(root, "confidence-selection.json");
  if (!await exists(path)) {
    check(ledger.attempted <= 100);
    return null;
  }
  check(ledger.attempted >= 100);
  const expected = await selectionRecord(study, ledger);
  check(
    await fingerprintJson(await readJson(path)) ===
      await fingerprintJson(expected),
  );
  // No held-out requests are allowed when development selects no candidate.
  check(expected.cutoff !== null || ledger.attempted === 100);
  return expected;
}

export async function saveConfidenceReport(
  root: string,
  study: PreparedConfidenceStudy,
  stop: string | null = null,
) {
  const ledger = await readConfidenceLedger(root, study),
    selection = await readSelection(root, study, ledger);
  const referenceInvalidated = await invalidated(root, study);
  const assessment = confidenceAssessment(
    {
      ...study.corpus,
      referenceStatus: referenceInvalidated
        ? "invalidated"
        : study.corpus.referenceStatus,
    },
    ledger.observations,
    selection?.cutoff ?? null,
  );
  const accounting = {
    attempted: ledger.attempted,
    maxAttempts: P.maxAttempts,
    budgetNanoUsd: P.budgetNanoUsd,
    settledNanoUsd: ledger.settledNanoUsd,
    outstandingNanoUsd: ledger.outstandingNanoUsd,
    costComplete: ledger.costComplete,
  };
  const report = {
    ...assessment,
    // Unresolved billing/dispatch cannot authorize a threshold, even if known predictions passed.
    recommendedStrong: ledger.costComplete
      ? assessment.recommendedStrong
      : P.fallbackStrong,
    thresholdDecisionEligible: ledger.costComplete && !referenceInvalidated &&
      assessment.decision === "validation_passed" &&
      study.corpus.kind === "reference",
    stop,
    manifestDigest: study.digest,
    hashes: {
      corpus: study.manifest.corpusDigest,
      taxonomy: study.manifest.taxonomyDigest,
      protocol: study.manifest.protocolDigest,
      pricing: study.manifest.pricingDigest,
      source: study.manifest.sourceDigest,
      cutoff: selection?.cutoffDigest ?? null,
      requests: study.manifest.assignments.map((a) => ({
        caseId: a.caseId,
        request: a.requestDigest,
        settings: a.settingsDigest,
      })),
    },
    accounting,
  };
  await atomicJson(join(root, "confidence-report.json"), report);
  return report;
}

/** One ledger for both splits. Every paid call follows an immutable fsynced claim. */
export async function executeConfidenceStudy(
  root: string,
  source: SourceIdentity,
  mode: "offline" | "live",
  adapter: AIAdapter<ReturnType<typeof openAIConfidenceSnapshot>>,
) {
  return await withRunLock(root, async () => {
    const study = await prepareConfidenceStudy(root, source);
    check(study.manifest.mode === mode);
    let stop: string | null = null;
    while (true) {
      const ledger = await readConfidenceLedger(root, study);
      await readSelection(root, study, ledger);
      if (await invalidated(root, study)) {
        stop = "reference_invalidated";
        break;
      }
      if (!ledger.costComplete) {
        stop = "accounting_reconciliation_required";
        break;
      }
      if (ledger.attempted === 100) {
        const path = join(root, "confidence-selection.json");
        if (!await exists(path)) {
          await claimJson(path, await selectionRecord(study, ledger));
        }
        if ((await readSelection(root, study, ledger))!.cutoff === null) {
          stop = "no_development_cutoff";
          break;
        }
      }
      if (ledger.attempted === P.maxAttempts) break;
      const a = study.manifest.assignments[ledger.attempted];
      if (
        ledger.settledNanoUsd + ledger.outstandingNanoUsd +
            a.reservationNanoUsd > P.budgetNanoUsd
      ) {
        stop = "budget_exhausted";
        break;
      }
      const request = await prepareEvidence(
        root,
        study.cases[ledger.attempted].input,
      );
      const snapshot = openAIConfidenceSnapshot(request);
      check(
        await fingerprintJson(
          buildOpenAIConfidenceRequest(request, snapshot),
        ) === a.requestDigest,
      );
      const execution = createAIExecution(adapter, request, snapshot);
      const claim = confidenceClaim(study, ledger.attempted),
        base = join(ledger.journal, a.caseId);
      await claimJson(base + ".claim.json", claim);
      try {
        const outcome = await execution.invoke();
        const result = projectConfidenceOutcome(
          a.caseId,
          outcome,
          study.taxonomy,
          study.pricing,
        );
        if (result.settledNanoUsd !== null) {
          check(result.settledNanoUsd <= a.reservationNanoUsd);
        }
        await claimJson(base + ".result.json", {
          version: "openai_confidence_result_v1",
          claimDigest: await fingerprintJson(claim),
          ...result,
        });
      } catch {
        // A missing result is an uncertain attempt on resume, never permission to retry.
        stop = "uncertain_execution";
        break;
      }
    }
    return await saveConfidenceReport(root, study, stop);
  });
}
