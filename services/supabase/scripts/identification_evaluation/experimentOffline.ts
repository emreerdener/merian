/** Invented mechanics only. No real evidence, pricing, credentials or provider calls. */
import { join } from "node:path";
import { fingerprintJson } from "./evidence.ts";
import {
  EXPERIMENT_METRICS,
  parseExperimentPlan,
} from "./experimentContracts.ts";
import { atomicJson, readJson } from "./files.ts";
import {
  createMeasurementDemo,
  type OfflineFixtures,
  offlineOutcomes,
} from "./offline.ts";
import { REUSABLE_PROFILE_IDS, reusableProfile } from "./reusableProfiles.ts";
import { parseEvaluationPricing, type SourceIdentity } from "./runContracts.ts";
import { type EvaluationInputs, prepareRun } from "./runner.ts";

export async function createExperimentDemo(
  root: string,
  source: SourceIdentity,
  now = Date.now(),
) {
  await createMeasurementDemo(root);
  const inputs = await prepareRun(root, source, "offline");
  const fixtures = await readJson(
    join(root, "fixtures.json"),
  ) as OfflineFixtures;
  // A refusal retains its full case allocation; failures are exercised separately.
  fixtures.cases = fixtures.cases.map((c) =>
    c.kind === "draft" ? c : { ...c, kind: "refusal", draft: null }
  );
  await atomicJson(join(root, "fixtures.json"), fixtures);
  const runs = await Promise.all(
    REUSABLE_PROFILE_IDS.slice(0, 2).map(async (profileId, i) => {
      const openai = i === 1;
      const pricing = parseEvaluationPricing({
        version: openai
          ? "evaluation_openai_pricing_v1"
          : "evaluation_pricing_v1",
        ...(openai ? { provider: "openai" } : {}),
        currency: "USD",
        service: "paid_standard_synchronous",
        retrievedAt: new Date(now).toISOString(),
        sourceUrl: openai
          ? "https://developers.openai.com/api/docs/models/gpt-6-sol"
          : "https://ai.google.dev/gemini-api/docs/pricing",
        reviewRef: "synthetic-price-card",
        includesReasoning: true,
        models:
          (openai ? ["gpt-6-sol"] : ["gemini-2.5-flash", "gemini-2.5-pro"]).map(
            (model) => ({
              model,
              inputPerMillion: {
                text: 1,
                image: 1,
                cached: 1,
                ...(openai ? { cacheWrite: 1 } : { audio: 1 }),
              },
              outputPerMillion: 1,
              maxInputTokens: 1050000,
              maxBillableOutputTokens: 8192,
              limitsEvidenceRef: "synthetic-ceilings",
            }),
          ),
      });
      return {
        runId: `offline-baseline-${i + 1}`,
        profileId,
        profileDigest: (await reusableProfile(profileId)).digest,
        maxCalls: inputs.manifest.spec.caseIds.length,
        budgetUsd: 10,
        pricing,
        pricingDigest: await fingerprintJson(pricing),
        readinessDigest: null,
      };
    }),
  );
  const plan = parseExperimentPlan({
    version: "identification_experiment_plan_v1",
    experimentId: "offline-profiles-v1",
    mode: "offline",
    reviewRef: "synthetic-mechanics-only",
    source,
    corpusDigest: inputs.manifest.spec.corpusDigest,
    taxonomyDigest: inputs.manifest.spec.taxonomyDigest,
    preparationVersion: inputs.manifest.preparationVersion,
    orderSeed: inputs.manifest.spec.orderSeed,
    cases: inputs.manifest.order.filter((a) => a.profile === "gemini_pro").map((
      a,
    ) => ({ caseId: a.caseId, inputDigest: a.inputDigest })),
    window: {
      startsAt: new Date(now).toISOString(),
      expiresAt: new Date(now + 3600000).toISOString(),
    },
    maxCalls: runs.reduce((n, r) => n + r.maxCalls, 0),
    budgetUsd: 20,
    metrics: EXPERIMENT_METRICS,
    cacheControl: "automatic_uncontrolled_no_extra_requests",
    candidateDecision: "deferred_cache_isolation_and_explanation_rubric",
    runs,
  });
  await atomicJson(join(root, "experiment.json"), plan);
  return plan;
}

export async function experimentOfflineOutcome(
  root: string,
  inputs: EvaluationInputs,
) {
  const fixture = offlineOutcomes(
    await readJson(join(root, "fixtures.json")),
    inputs.corpus,
    inputs.manifest.spec,
  );
  return (...args: Parameters<typeof fixture>): ReturnType<typeof fixture> => ({
    ...fixture(...args),
    usage: {
      promptTokens: 100,
      candidateTokens: 10,
      thinkingTokens: 0,
      totalTokens: 110,
      cachedTokens: 0,
      cacheWriteTokens: 0,
      toolTokens: 0,
      modalityBreakdown: {},
    },
  });
}
