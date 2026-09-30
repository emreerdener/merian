import { join } from "node:path";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import { OPENAI_MODEL } from "../../functions/_shared/ai/openaiRequest.ts";
import { prepareEvidence } from "./assets.ts";
import { confidenceOrder, parseConfidenceCorpus } from "./confidenceCorpus.ts";
import { confidenceEvidenceDigest } from "./confidenceEvidence.ts";
import { CONFIDENCE_PROTOCOL as P } from "./confidenceProtocol.ts";
import { fingerprintJson } from "./evidence.ts";
import { claimJson, exists, readJson } from "./files.ts";
import { reserveCost } from "./profiles.ts";
import { nanoUsd } from "./confidenceProjection.ts";
import {
  type OpenAIPricing,
  parseEvaluationPricing,
  type SourceIdentity,
} from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";
import { token } from "./validation.ts";
import { hash } from "./runContracts.ts";
import { readConfidenceLedger } from "./confidenceLedger.ts";
import {
  type ConfidenceContinuation,
  confidenceJournalPrefixDigest,
  CONTINUATION_BUDGET_NANO_USD,
  readConfidenceContinuation,
} from "./confidenceContinuation.ts";

async function deriveConfidenceStudy(
  root: string,
  source: SourceIdentity,
) {
  const { corpus, taxonomy } = parseConfidenceCorpus(
    await readJson(join(root, "confidence-corpus.json")),
    await readJson(join(root, "taxonomy.json")),
  );
  const pricing = parseEvaluationPricing(
    await readJson(join(root, "pricing.json")),
  );
  check(pricing.version === "evaluation_openai_pricing_v1");
  const evidenceDigest = await confidenceEvidenceDigest(root, corpus);
  const reservationNanoUsd = nanoUsd(reserveCost(pricing, OPENAI_MODEL));
  check(Number.isSafeInteger(reservationNanoUsd) && reservationNanoUsd > 0);
  const cases = await confidenceOrder(corpus);
  const assignments = [];
  for (const c of cases) {
    const request = await prepareEvidence(root, c.input),
      snapshot = openAIConfidenceSnapshot(request);
    const native = buildOpenAIConfidenceRequest(request, snapshot);
    const { input: _input, ...settings } = native;
    assignments.push({
      caseId: c.input.caseId,
      split: c.input.split,
      requestDigest: await fingerprintJson(native),
      settingsDigest: await fingerprintJson({ snapshot, settings }),
      reservationNanoUsd,
    });
  }
  const manifest = {
    version: "openai_confidence_manifest_v2",
    mode: corpus.kind === "synthetic" ? "offline" : "live",
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    protocolDigest: await fingerprintJson(P),
    pricingDigest: await fingerprintJson(pricing),
    sourceDigest: source.digest,
    evidenceDigest,
    assignments,
  };
  const path = join(root, "confidence-manifest.json");
  let originalManifest = manifest;
  if (await exists(path)) {
    const stored = await readJson(path) as typeof manifest;
    hash(stored.sourceDigest);
    // Reconstruct every frozen input and request. Only a separately validated
    // continuation can authorize a changed executable, never changed study data.
    check(
      await fingerprintJson(stored) === await fingerprintJson({
        ...manifest,
        sourceDigest: stored.sourceDigest,
      }),
    );
    originalManifest = stored;
  } else await claimJson(path, manifest);
  return {
    corpus,
    taxonomy,
    pricing,
    manifest: originalManifest,
    digest: await fingerprintJson(originalManifest),
    cases,
    budgetNanoUsd: P.budgetNanoUsd as number,
    continuation: null as ConfidenceContinuation | null,
  };
}

export async function prepareConfidenceStudy(
  root: string,
  source: SourceIdentity,
) {
  const study = await deriveConfidenceStudy(root, source);
  const continuation = await readConfidenceContinuation(
    root,
    study.digest,
    study.manifest.sourceDigest,
    source,
  );
  if (continuation === null) {
    check(study.manifest.sourceDigest === source.digest);
  } else {
    study.continuation = continuation;
    study.budgetNanoUsd = continuation.budgetNanoUsd;
    await readConfidenceLedger(root, study);
  }
  return study;
}

/** Offline, explicit reviewed repair. Caller holds the same run lock as dispatch. */
export async function prepareConfidenceContinuation(
  root: string,
  source: SourceIdentity,
  expectedManifestDigest: string,
  authorizationRef: string,
  reviewRef: string,
) {
  hash(expectedManifestDigest);
  token(authorizationRef);
  token(reviewRef);
  check(
    await exists(join(root, "confidence-manifest.json")) &&
      !await exists(join(root, "confidence-continuation.json")),
  );
  const study = await deriveConfidenceStudy(root, source);
  check(
    study.digest === expectedManifestDigest &&
      study.manifest.sourceDigest !== source.digest,
  );
  const ledger = await readConfidenceLedger(root, study);
  check(
    ledger.attempted > 0 && ledger.attempted < P.maxAttempts &&
      ledger.costComplete,
  );
  const continuation: ConfidenceContinuation = {
    version: "openai_confidence_continuation_v1",
    originalManifestDigest: study.digest,
    originalSourceDigest: study.manifest.sourceDigest,
    replacementSource: source,
    authorizationRef,
    reviewRef,
    budgetKind: "cumulative_total",
    budgetNanoUsd: CONTINUATION_BUDGET_NANO_USD,
    maxAttempts: P.maxAttempts,
    nextOrdinal: ledger.attempted + 1,
    journalPrefix: {
      attempted: ledger.attempted,
      settledNanoUsd: ledger.settledNanoUsd,
      outstandingNanoUsd: 0,
      digest: await confidenceJournalPrefixDigest(
        root,
        study.manifest.assignments
          .slice(0, ledger.attempted).map((a) => a.caseId),
      ),
    },
  };
  await claimJson(join(root, "confidence-continuation.json"), continuation);
  return await prepareConfidenceStudy(root, source);
}
export type PreparedConfidenceStudy = Awaited<
  ReturnType<typeof deriveConfidenceStudy>
>;

/** Reporting stays available after expiry; only new paid dispatch needs fresh prices. */
export function confidencePricingCurrent(pricing: OpenAIPricing, now: number) {
  const age = now - Date.parse(pricing.retrievedAt);
  return Number.isFinite(age) && age >= 0 && age <= P.pricingMaxAgeMs;
}
