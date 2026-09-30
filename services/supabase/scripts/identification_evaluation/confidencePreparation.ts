import { join } from "node:path";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import { OPENAI_MODEL } from "../../functions/_shared/ai/openaiRequest.ts";
import { prepareEvidence } from "./assets.ts";
import { confidenceOrder, parseConfidenceCorpus } from "./confidenceCorpus.ts";
import { CONFIDENCE_PROTOCOL as P } from "./confidenceProtocol.ts";
import { fingerprintJson } from "./evidence.ts";
import { claimJson, exists, readJson } from "./files.ts";
import { reserveCost } from "./profiles.ts";
import { nanoUsd } from "./confidenceProjection.ts";
import { parseEvaluationPricing, type SourceIdentity } from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";

export async function prepareConfidenceStudy(
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
    version: "openai_confidence_manifest_v1",
    mode: corpus.kind === "synthetic" ? "offline" : "live",
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    protocolDigest: await fingerprintJson(P),
    pricingDigest: await fingerprintJson(pricing),
    sourceDigest: source.digest,
    assignments,
  };
  const digest = await fingerprintJson(manifest);
  const path = join(root, "confidence-manifest.json");
  if (await exists(path)) {
    check(await fingerprintJson(await readJson(path)) === digest);
  } else await claimJson(path, manifest);
  return { corpus, taxonomy, pricing, manifest, digest, cases };
}
export type PreparedConfidenceStudy = Awaited<
  ReturnType<typeof prepareConfidenceStudy>
>;
