import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { MultimodalAIRequest } from "../functions/_shared/ai/contracts.ts";
import {
  assertOfflinePermissions,
  liveCredential,
  validateLiveApproval,
  validateSelection,
} from "./identification_evaluation/admission.ts";
import {
  fingerprintBytes,
  fingerprintCorpus,
  fingerprintJson,
} from "./identification_evaluation/evidence.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import {
  assignmentFor,
  estimateCost,
  reserveCost,
} from "./identification_evaluation/profiles.ts";
import {
  projectOutcome,
  projectUsage,
} from "./identification_evaluation/projection.ts";
import {
  pairedInterval,
  wilson95,
} from "./identification_evaluation/reports.ts";
import {
  MODELS,
  parseAttempt,
  parsePricing,
  parseReadiness,
  parseRunSpec,
  parseTaxonomy,
  type Pricing,
  type RunSpec,
} from "./identification_evaluation/runContracts.ts";
import { rate } from "./identification_evaluation/scoring.ts";
import {
  type EvaluationInputs,
  executeRun,
  guardNextAttempt,
} from "./identification_evaluation/runner.ts";
import type { EvaluationCorpus } from "./identification_evaluation/contracts.ts";

// Deliberately invented prices/credential. Never suitable for a paid run.
export function fixturePricing(): Pricing {
  return parsePricing({
    version: "evaluation_pricing_v1",
    currency: "USD",
    service: "paid_standard_synchronous",
    retrievedAt: "2026-09-22T00:00:00.000Z",
    sourceUrl: "https://ai.google.dev/gemini-api/docs/pricing",
    reviewRef: "synthetic-price-review",
    includesReasoning: true,
    models: MODELS.map((model) => ({
      model,
      inputPerMillion: { text: 1, image: 2, audio: 3, cached: 1 },
      outputPerMillion: 4,
      maxInputTokens: 10000,
      maxBillableOutputTokens: 20000,
      limitsEvidenceRef: "synthetic-limits",
    })),
  });
}
const request: MultimodalAIRequest = {
  task: "identify",
  variant: "multimodal",
  evidence: [{
    kind: "text",
    order: 0,
    source: "observation_context",
    text: "Invented synthetic input.",
  }, {
    kind: "text",
    order: 1,
    source: "capture_context",
    text: "Context: no telemetry.",
  }],
  capture: {
    hasVideo: false,
    videoClipCount: 0,
    declaredVideoFrameCount: 0,
    videoInferenceFrameCount: 0,
  },
};
const input = syntheticCorpus().cases[1].input;
const taxonomy = parseTaxonomy({
  version: "evaluation_taxonomy_v1",
  taxonomyVersion: "synthetic-v1",
  taxa: [{
    taxon: { id: "synthetic:monarch", rank: "species" },
    names: ["Danaus plexippus"],
  }],
});
const draft = {
  is_biological_subject: true,
  is_live_capture: true,
  scientific_name: "Danaus plexippus",
  common_name: "Monarch",
  confidence_score: .98,
  ai_reasoning: "PRIVATE_SYNTHETIC_REASONING",
  extracted_visual_traits: ["Invented fixture trait."],
  candidates: [{
    scientific_name: "Unmapped candidate",
    confidence_score: .1,
    distinguishing_feature: "PRIVATE_SYNTHETIC_FEATURE",
  }],
  image_quality: {
    sharpness: 10,
    framing: 10,
    diagnostic_utility: 10,
    overall_score: 100,
  },
};
const facts = {
  providerDurationMs: 7,
  providerCompletedAt: 0,
  returnedModel: "gemini-2.5-flash",
  usage: {
    promptTokens: 10,
    candidateTokens: 5,
    thinkingTokens: 3,
    totalTokens: 18,
    cachedTokens: 4,
    toolTokens: 0,
    modalityBreakdown: {
      prompt: { text: 2, image: 8 },
      cached: { image: 4 },
      candidates: { text: 5 },
      tool: {},
    },
  },
  finishReason: null,
  responseCharacters: 1,
};

Deno.test({
  name:
    "evaluation imports and request preparation are safe with every permission denied",
  permissions: "none",
  async fn() {
    await import("./evaluate_identification.ts");
    await assertOfflinePermissions();
    await assertRejects(liveCredential);
    const a = await assignmentFor(input, request, "gemini_flash_free", 1, null),
      b = await assignmentFor(input, request, "gemini_pro", 1, null);
    assertEquals(a.model, "gemini-2.5-flash");
    assertEquals(b.model, "gemini-2.5-pro");
    assertEquals(a.generation.thinkingBudget, null);
    assertEquals(b.generation.thinkingBudget, 5000);
    assert(a.requestDigest !== b.requestDigest);
    assertEquals(
      await fingerprintJson({ b: undefined, a: 1 }),
      await fingerprintJson({ a: 1 }),
    );
  },
});
Deno.test("evaluation stores bounded decisions/usage and no draft, prompt, reasoning or errors", async () => {
  const a = await assignmentFor(
    input,
    request,
    "gemini_flash_free",
    1,
    fixturePricing(),
  );
  const result = projectOutcome(
    { ...facts, kind: "draft", draft },
    input,
    a,
    "0".repeat(64),
    taxonomy,
    fixturePricing(),
  );
  assertEquals(result.prediction, {
    caseId: input.caseId,
    outcome: "normalized",
    subject: "biological",
    resolution: "named",
    taxon: { id: "synthetic:monarch", rank: "species" },
    confidence: .98,
  });
  assertEquals(result.candidates, [{ taxon: null, confidence: .1 }]);
  assertEquals(result.band, "strong");
  assertEquals(result.diagnostic, false);
  const json = JSON.stringify(result);
  for (
    const forbidden of [
      "PRIVATE_",
      "Monarch",
      "Danaus",
      "Unmapped",
      "finishReason",
      "responseCharacters",
    ]
  ) assert(!json.includes(forbidden));
  assertEquals(result.estimatedUpperUsd, (10 * 3 + 8 * 4) / 1e6);
  assertThrows(() => parseAttempt({ ...result, raw: draft }));
  assertThrows(() => parseAttempt({ ...result, reason: "refusal" }));
  const missing = projectOutcome(
    { ...facts, kind: "draft", draft, usage: null },
    input,
    a,
    "0".repeat(64),
    taxonomy,
    fixturePricing(),
  );
  assertEquals(missing.reason, "usage_missing");
  assertEquals(missing.estimatedUpperUsd, null);
  assertEquals(
    projectOutcome(
      { ...facts, kind: "draft", draft, returnedModel: "gemini-unknown" },
      input,
      a,
      "0".repeat(64),
      taxonomy,
      fixturePricing(),
    ).reason,
    "model_mismatch",
  );
  assertEquals(
    projectOutcome(
      { ...facts, kind: "draft", draft: { private: "secret" } },
      input,
      a,
      "0".repeat(64),
      taxonomy,
      fixturePricing(),
    ).prediction.outcome,
    "invalid_output",
  );
});
Deno.test("cost bounds include thinking and expensive modalities; corrupt/missing usage is unknown", () => {
  const p = fixturePricing(), u = projectUsage(facts.usage)!;
  assertEquals(reserveCost(p, MODELS[0]), .11);
  assertEquals(
    estimateCost(p, MODELS[0], { ...u, thinkingTokens: null }),
    null,
  );
  assertEquals(estimateCost(p, MODELS[0], { ...u, totalTokens: 17 }), null);
  assertEquals(estimateCost(p, MODELS[0], { ...u, cachedTokens: 11 }), null);
  assertEquals(estimateCost(p, MODELS[0], { ...u, toolTokens: 1 }), null);
  assertEquals(estimateCost(p, MODELS[0], { ...u, totalTokens: 40000 }), null);
  assertEquals(
    projectUsage({
      ...facts.usage,
      modalityBreakdown: { prompt: { private: "secret" } },
    })!.modalities,
    null,
  );
  assertEquals(
    projectUsage({ ...facts.usage, promptTokens: Infinity })!.promptTokens,
    null,
  );
});

Deno.test("dispatch spend guards reserve the next attempt and stop for missing usage", async () => {
  const a = await assignmentFor(
    input,
    request,
    "gemini_flash_free",
    1,
    fixturePricing(),
  );
  const record = projectOutcome(
    { ...facts, kind: "draft", draft },
    input,
    a,
    "0".repeat(64),
    taxonomy,
    fixturePricing(),
  );
  assertEquals(guardNextAttempt([], 2, .1, .11, true), "budget_exceeded");
  assertEquals(guardNextAttempt([], 2, .11, .11, true), null);
  assertEquals(
    guardNextAttempt([record], 2, .11, .11, true),
    "budget_exceeded",
  );
  assertEquals(guardNextAttempt([record], 1, 100, .11, true), "call_limit");
  assertEquals(
    guardNextAttempt(
      [{ ...record, estimatedUpperUsd: null }],
      2,
      100,
      .11,
      true,
    ),
    "usage_missing",
  );
  assertEquals(guardNextAttempt([record], 2, 0, 0, false), null);
});

Deno.test({
  name: "live execution rejects dependency injection before any I/O",
  permissions: "none",
  async fn() {
    const inputs = {
      manifest: { spec: { mode: "live" } },
    } as unknown as EvaluationInputs;
    await assertRejects(
      () =>
        executeRun("/must-not-be-accessed", inputs, {
          checkpoint: () => {
            throw new Error("must_not_call");
          },
        }),
      Error,
      "evaluation_live_dependencies_forbidden",
    );
    await assertRejects(
      () =>
        executeRun(
          "/must-not-be-accessed",
          inputs,
          Object.create({
            prepare: () => {
              throw new Error("must_not_call");
            },
          }),
        ),
      Error,
      "evaluation_live_dependencies_forbidden",
    );
  },
});

Deno.test("bounded subject projection preserves the normalized biological disposition", async () => {
  const a = await assignmentFor(input, request, "gemini_flash_free", 1, null);
  const record = projectOutcome(
    {
      ...facts,
      kind: "draft",
      draft: {
        ...draft,
        is_biological_subject: false,
        scientific_name: "Homo sapiens",
        common_name: "Ambiguous subject",
      },
    },
    input,
    a,
    "0".repeat(64),
    taxonomy,
    null,
  );
  assertEquals(record.prediction.outcome, "normalized");
  if (record.prediction.outcome === "normalized") {
    assertEquals(record.prediction.subject, "non_biological");
  }
});
Deno.test("live admission binds pricing, corpus, actual credential, paid processor and validity dates", async () => {
  const now = Date.parse("2026-09-22T12:00:00.000Z"),
    p = fixturePricing(),
    credential = "synthetic-evaluation-credential";
  const corpus = {
    ...syntheticCorpus(),
    kind: "reference",
    approval: {
      recordRef: "synthetic-review",
      ownerRole: "synthetic-owner",
      retainUntil: "2027-01-01",
    },
    cases: syntheticCorpus().cases.map((c) => ({
      ...c,
      curation: {
        kind: "reviewed",
        source: "purpose_collected",
        sourceRecordRef: "synthetic-source",
        referenceRecordRef: "synthetic-reference",
        permission: "gemini_evaluation",
        rightsApproved: true,
        personalDataExcluded: true,
        nearDuplicatesReviewed: true,
        referenceVerified: true,
        reviewerRefs: ["r0001", "r0002"],
        adjudication: "agreed",
      },
    })),
  } as EvaluationCorpus;
  const corpusDigest = await fingerprintCorpus(corpus);
  const readiness = parseReadiness({
    version: "evaluation_processor_v1",
    corpusDigest,
    projectRef: "synthetic-evaluation",
    credentialRef: "synthetic-key",
    credentialSha256: await fingerprintBytes(
      new TextEncoder().encode(credential),
    ),
    reviewedAt: "2026-09-22T00:00:00.000Z",
    expiresAt: "2026-09-23T00:00:00.000Z",
    reviewerRole: "reviewer",
    dedicatedEvaluationProject: true,
    paidServiceApproved: true,
    purpose: "identification_evaluation",
    termsRef: "synthetic-terms",
    dataUseRef: "synthetic-data-use",
    regionSubprocessorRef: "synthetic-region",
    retentionAbuseLogRef: "synthetic-retention",
  });
  const spec: RunSpec = parseRunSpec({
    version: "identification_run_spec_v1",
    runId: "synthetic-run",
    mode: "live",
    corpusDigest,
    taxonomyDigest: "0".repeat(64),
    split: "development",
    stage: "development",
    profiles: ["gemini_flash_free", "gemini_pro"],
    caseIds: corpus.cases.map((c) => c.input.caseId),
    repeats: 1,
    orderSeed: 42,
    maxCalls: 24,
    budgetUsd: 10,
    pricingDigest: await fingerprintJson(p),
    readinessDigest: await fingerprintJson(readiness),
  });
  await validateLiveApproval(corpus, spec, p, readiness, credential, now);
  for (
    const changed of [
      { ...readiness, projectRef: "changed" },
      { ...readiness, credentialRef: "changed" },
      { ...readiness, corpusDigest: "1".repeat(64) },
      { ...readiness, paidServiceApproved: false },
    ]
  ) {
    await assertRejects(() =>
      validateLiveApproval(corpus, spec, p, changed, credential, now)
    );
  }
  await assertRejects(() =>
    validateLiveApproval(corpus, spec, p, readiness, "wrong", now)
  );
  await assertRejects(() =>
    validateLiveApproval(
      corpus,
      spec,
      p,
      readiness,
      credential,
      now + 2 * 86400000,
    )
  );
  const stale = { ...p, retrievedAt: "2026-09-01T00:00:00.000Z" };
  await assertRejects(async () =>
    validateLiveApproval(
      corpus,
      { ...spec, pricingDigest: await fingerprintJson(stale) },
      stale,
      readiness,
      credential,
      now,
    )
  );
  await assertRejects(() => validateSelection(corpus, spec, taxonomy));
});
Deno.test("reviewed intervals handle hand-computed extremes, paired ordering and undefined denominators", () => {
  const none = wilson95(rate(0, 0));
  assertEquals(none.lower, null);
  const one = wilson95(rate(1, 1));
  assert(Math.abs(one.lower! - .20654931437723745) < 1e-10);
  assertEquals(one.upper, 1);
  const interval = pairedInterval([rate(0, 1), rate(0, 1)], [
    rate(1, 1),
    rate(1, 1),
  ]);
  assertEquals([interval.lower, interval.upper], [1, 1]);
  assertEquals(
    pairedInterval([rate(0, 0)], [rate(0, 0)]).status,
    "not_estimable",
  );
  assertEquals(
    pairedInterval([rate(0, 1), rate(1, 1)], [rate(1, 1), rate(0, 1)]),
    pairedInterval([rate(0, 1), rate(1, 1)], [rate(1, 1), rate(0, 1)]),
  );
});
