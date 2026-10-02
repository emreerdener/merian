/** One prospective development screen. Historical studies remain immutable. */
import { join } from "node:path";
import {
  buildOpenAIConfidenceRequest,
  openAIConfidenceSnapshot,
} from "../../functions/_shared/ai/openaiPhotoConfidence.ts";
import {
  buildOpenAIPhotoPrimaryRequest,
  openAIPhotoPrimarySnapshot,
} from "../../functions/_shared/ai/openaiPhotoPrimary.ts";
import { prepareEvidence } from "./assets.ts";
import { parseConfidenceCorpus } from "./confidenceCorpus.ts";
import { confidenceEvidenceDigest } from "./confidenceEvidence.ts";
import { fingerprintJson } from "./evidence.ts";
import { claimJson, exists, readJson } from "./files.ts";
import { random, reserveCost } from "./profiles.ts";
import {
  hash,
  parseEvaluationPricing,
  type SourceIdentity,
  timestamp,
} from "./runContracts.ts";
import {
  array,
  fields,
  member,
  requireCondition as check,
  token,
} from "./validation.ts";

export const PRIMARY_SCREEN = Object.freeze({
  version: "photo_primary_development_screen_v1",
  maxCalls: 40,
  budgetNanoUsd: 10_000_000_000,
  seed: 20261002,
  billingMultiplier: 1.1,
  minimumNetGain: 2,
  minimumUnresolvedGains: 1,
  regressionIds: ["c0005", "c0006", "c0013"],
  retainedGainIds: ["c0007", "c0021", "c0049", "c0050", "c0195"],
});
export type PrimaryScreenArm = "released" | "primary";
export function screenRequest(
  request: Parameters<typeof openAIConfidenceSnapshot>[0],
  arm: PrimaryScreenArm,
) {
  return arm === "primary"
    ? {
      snapshot: openAIPhotoPrimarySnapshot(request),
      parameters: buildOpenAIPhotoPrimaryRequest(
        request,
        openAIPhotoPrimarySnapshot(request),
      ),
    }
    : {
      snapshot: openAIConfidenceSnapshot(request),
      parameters: buildOpenAIConfidenceRequest(
        request,
        openAIConfidenceSnapshot(request),
      ),
    };
}

export async function preparePrimaryScreen(
  root: string,
  source: SourceIdentity,
) {
  const plan = fields(await readJson(join(root, "screen-plan.json")), [
    "version",
    "mode",
    "authorizationRef",
    "paidServiceApproved",
    "packetRootDigest",
    "retainUntil",
    "inputPermission",
    "caseIds",
    "exposureDigest",
    "reviewRef",
    "budgetNanoUsd",
    "maxCalls",
  ]);
  check(plan.version === PRIMARY_SCREEN.version);
  member(plan.mode, ["live", "offline"]);
  check(
    plan.budgetNanoUsd === PRIMARY_SCREEN.budgetNanoUsd &&
      plan.maxCalls === PRIMARY_SCREEN.maxCalls,
  );
  check(typeof plan.paidServiceApproved === "boolean");
  token(plan.authorizationRef);
  token(plan.reviewRef);
  hash(plan.packetRootDigest);
  hash(plan.exposureDigest);
  timestamp(plan.retainUntil);
  check(plan.inputPermission === "openai");
  check(
    plan.packetRootDigest === await fingerprintJson(await Deno.realPath(root)),
  );
  const { corpus, taxonomy } = parseConfidenceCorpus(
    await readJson(join(root, "confidence-corpus.json")),
    await readJson(join(root, "taxonomy.json")),
  );
  check(
    corpus.referenceStatus === "valid" &&
      corpus.kind === (plan.mode === "live" ? "reference" : "synthetic"),
  );
  const evidenceDigest = await confidenceEvidenceDigest(root, corpus);
  const ids = array(plan.caseIds, 20, 20);
  ids.forEach(token);
  check(new Set(ids).size === 20);
  const cases = ids.map((id) => {
    const c = corpus.cases.find((c) => c.input.caseId === id);
    check(c);
    check(
      c.input.inputGroup === "photos" && c.input.assets.length === 1 &&
        c.input.observationTexts.length === 0 && c.input.clips.length === 0 &&
        c.input.context.currentMonth === null &&
        c.input.context.deviceRegion === null,
    );
    return c;
  });
  check(new Set(cases.map((c) => c.input.groupId)).size === 20);
  const exposure = fields(await readJson(join(root, "screen-exposure.json")), [
    "parentManifest",
    "claims",
    "clusters",
  ]);
  check(await fingerprintJson(exposure) === plan.exposureDigest);
  const parent = fields(exposure.parentManifest, [
    "version",
    "protocol",
    "source",
    "planDigest",
    "corpusDigest",
    "taxonomyDigest",
    "evidenceDigest",
    "openaiPricingDigest",
    "geminiPricingDigest",
    "assignments",
  ]);
  check(
    parent.version === "photo_decision_manifest_v1" &&
      parent.corpusDigest === await fingerprintJson(corpus) &&
      parent.taxonomyDigest === await fingerprintJson(taxonomy) &&
      parent.evidenceDigest === evidenceDigest,
  );
  const parentDigest = await fingerprintJson(parent);
  const claims = array(exposure.claims, 20, 20).map((raw) =>
    fields(raw, ["version", "manifestDigest", "assignment"])
  );
  const clusters = array(exposure.clusters, 20, 20).map((raw) =>
    fields(raw, ["caseId", "clusterRef"])
  );
  clusters.forEach((c) => {
    token(c.caseId);
    token(c.clusterRef);
  });
  check(
    new Set(clusters.map((c) => c.caseId)).size === 20 &&
      new Set(clusters.map((c) => c.clusterRef)).size === 20 &&
      ids.every((id) => clusters.some((c) => c.caseId === id)),
  );
  const priorAssignments = array(parent.assignments, 40, 360);
  const pricing = parseEvaluationPricing(
    await readJson(join(root, "openai-pricing.json")),
  );
  check(pricing.version === "evaluation_openai_pricing_v1");
  const price = pricing.models.find((p) => p.model === "gpt-6-sol");
  check(
    price && price.maxInputTokens >= 1_050_000 &&
      price.maxBillableOutputTokens >= 8192,
  );
  const reservedNanoUsd = Math.ceil(
    reserveCost(pricing, "gpt-6-sol") * 1e9 * PRIMARY_SCREEN.billingMultiplier,
  );
  check(
    Number.isSafeInteger(reservedNanoUsd) && reservedNanoUsd > 0 &&
      reservedNanoUsd <= PRIMARY_SCREEN.budgetNanoUsd,
  );
  if (plan.mode === "live") {
    check(
      [...PRIMARY_SCREEN.regressionIds, ...PRIMARY_SCREEN.retainedGainIds]
        .every((id) => ids.includes(id)),
    );
    check(
      cases.filter((c) =>
        c.reference.subject === "biological" &&
        c.reference.resolution === "unresolved"
      ).length === 6,
    );
    check(cases.some((c) => c.reference.subject === "non_biological"));
  }
  const ordered = [...cases].sort((a, b) =>
    a.input.caseId.localeCompare(b.input.caseId)
  );
  const rng = random(PRIMARY_SCREEN.seed);
  for (let i = ordered.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [ordered[i], ordered[j]] = [ordered[j], ordered[i]];
  }
  const assignments = [];
  for (const [i, c] of ordered.entries()) {
    const request = await prepareEvidence(root, c.input);
    const baseline = screenRequest(request, "released");
    const requestDigest = await fingerprintJson(baseline.parameters);
    const claim = claims.find((claim) =>
      (claim.assignment as { caseId?: unknown })?.caseId === c.input.caseId
    );
    check(
      claim && claim.version === "photo_decision_claim_v1" &&
        claim.manifestDigest === parentDigest,
    );
    const a = fields(claim.assignment, [
      "key",
      "phase",
      "caseId",
      "arm",
      "requestDigest",
      "settingsDigest",
      "reservedNanoUsd",
      "gemini",
    ]);
    check(
      a.arm === "released" && a.requestDigest === requestDigest &&
        a.settingsDigest === await fingerprintJson(baseline.snapshot),
    );
    check(
      (await Promise.all(priorAssignments.map((x) => fingerprintJson(x))))
        .includes(await fingerprintJson(a)),
    );
    const arms: PrimaryScreenArm[] = i % 2
      ? ["primary", "released"]
      : ["released", "primary"];
    for (const arm of arms) {
      const native = screenRequest(request, arm);
      assignments.push({
        ordinal: assignments.length + 1,
        caseId: c.input.caseId,
        arm,
        requestDigest: await fingerprintJson(native.parameters),
        snapshotDigest: await fingerprintJson(native.snapshot),
        reservedNanoUsd,
      });
    }
  }
  const manifest = {
    version: "photo_primary_screen_manifest_v1",
    protocol: PRIMARY_SCREEN,
    source,
    planDigest: await fingerprintJson(plan),
    corpusDigest: await fingerprintJson(corpus),
    taxonomyDigest: await fingerprintJson(taxonomy),
    evidenceDigest,
    pricingDigest: await fingerprintJson(pricing),
    exposureDigest: plan.exposureDigest,
    assignments,
  };
  const path = join(root, "screen-manifest.json");
  if (await exists(path)) {
    check(
      await fingerprintJson(await readJson(path)) ===
        await fingerprintJson(manifest),
    );
  } else await claimJson(path, manifest);
  return {
    plan,
    cases,
    taxonomy,
    pricing,
    manifest,
    digest: await fingerprintJson(manifest),
  };
}
export type PrimaryScreenStudy = Awaited<
  ReturnType<typeof preparePrimaryScreen>
>;
export type PrimaryScreenAssignment =
  PrimaryScreenStudy["manifest"]["assignments"][number];
