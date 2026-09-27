import {
  fingerprintRunCorpus,
  parseExploratoryCorpus,
} from "./identification_evaluation/exploratory.ts";
import { fingerprintBytes } from "./identification_evaluation/evidence.ts";
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createAIExecution } from "../functions/_shared/ai/execution.ts";
import { createOpenAIEvaluationAdapter } from "../functions/_shared/ai/openai.ts";
import {
  OPENAI_MODEL,
  OPENAI_PROFILE,
  openAIEvaluationSnapshot,
} from "../functions/_shared/ai/openaiRequest.ts";
import {
  openAIResponseFixture,
  openAITextFixture,
} from "../functions/_shared/ai/testing/openaiFixtures.ts";
import {
  syntheticCorpus,
  syntheticPredictions,
} from "./identification_evaluation/fixtures.ts";
import { fingerprintJson } from "./identification_evaluation/evidence.ts";
import {
  assignmentFor,
  confidencePolicy,
  estimateCost,
} from "./identification_evaluation/profiles.ts";
import { projectOutcome } from "./identification_evaluation/projection.ts";
import {
  liveCredential,
  validateLiveApproval,
} from "./identification_evaluation/admission.ts";
import {
  type GeminiReadiness,
  type OpenAIPricing,
  type OpenAIReadiness,
  parseEvaluationPricing,
  parseEvaluationReadiness,
  parsePricing,
  parseReadiness,
  parseRunSpec,
  parseTaxonomy,
  PROVIDER_SPEC_VERSION,
} from "./identification_evaluation/runContracts.ts";
import { scoreEvaluation } from "./identification_evaluation/scoring.ts";
import { guardNextAttempt } from "./identification_evaluation/runner.ts";

// Intentionally invented rates/reviews; no credential or approval for a paid call.
const pricing: OpenAIPricing = {
  version: "evaluation_openai_pricing_v1",
  provider: "openai",
  currency: "USD",
  service: "paid_standard_synchronous",
  retrievedAt: "2026-09-25T00:00:00.000Z",
  sourceUrl: "https://developers.openai.com/api/docs/models/gpt-6-sol",
  reviewRef: "synthetic-review",
  includesReasoning: true,
  models: [{
    model: OPENAI_MODEL,
    inputPerMillion: { text: 2, image: 2, cached: 1, cacheWrite: 3 },
    outputPerMillion: 10,
    maxInputTokens: 1050000,
    maxBillableOutputTokens: 8192,
    limitsEvidenceRef: "synthetic-limits",
  }],
};
const readiness: OpenAIReadiness = {
  version: "evaluation_openai_processor_v1",
  provider: "openai",
  inputPermission: {
    provider: "openai",
    corpusDigest: "0".repeat(64),
    caseIds: ["c0002"],
    reviewRef: "synthetic-openai-permission",
    approved: true,
  },
  corpusDigest: "0".repeat(64),
  projectRef: "synthetic-project",
  credentialRef: "synthetic-key-reference",
  credentialSha256: "1".repeat(64),
  reviewedAt: "2026-09-25T00:00:00.000Z",
  expiresAt: "2026-09-26T00:00:00.000Z",
  reviewerRole: "synthetic-owner",
  dedicatedEvaluationProject: true,
  paidServiceApproved: true,
  purpose: "identification_evaluation",
  termsRef: "synthetic-terms",
  dataUseRef: "synthetic-data",
  regionSubprocessorRef: "synthetic-region",
  retentionAbuseLogRef: "synthetic-retention",
};
Deno.test("OpenAI evaluation records require explicit provider versions and cannot consume legacy approvals", async () => {
  assertEquals(parseEvaluationPricing(pricing), pricing);
  assertEquals(parseEvaluationReadiness(readiness), readiness);
  assertThrows(() => parsePricing(pricing));
  assertThrows(() => parseReadiness(readiness));
  const { inputPermission: _permission, ...withoutPermission } = readiness;
  assertThrows(() => parseEvaluationReadiness(withoutPermission));
  assertThrows(() =>
    parseEvaluationReadiness({
      ...readiness,
      inputPermission: { ...readiness.inputPermission, provider: "gemini" },
    })
  );
  assertThrows(() =>
    parseEvaluationReadiness({
      ...readiness,
      inputPermission: { ...readiness.inputPermission, approved: false },
    })
  );
  assertThrows(() =>
    parseEvaluationPricing({ ...pricing, sourceUrl: "https://example.test" })
  );
  assertThrows(() =>
    parseEvaluationPricing({
      ...pricing,
      models: [{ ...pricing.models[0], model: "gemini-2.5-pro" }],
    })
  );
  assertThrows(() =>
    parseEvaluationPricing({
      ...pricing,
      models: [{ ...pricing.models[0], maxInputTokens: 100 }],
    })
  );
  assertThrows(() =>
    parseEvaluationPricing({
      ...pricing,
      models: [{
        ...pricing.models[0],
        inputPerMillion: { text: 1, image: 1, cached: 1 },
      }],
    })
  );
  const spec = parseRunSpec({
    version: PROVIDER_SPEC_VERSION,
    runId: "synthetic-openai",
    mode: "live",
    corpusDigest: "0".repeat(64),
    taxonomyDigest: "1".repeat(64),
    split: "development",
    stage: "exploratory",
    profiles: [OPENAI_PROFILE],
    caseIds: ["c0002"],
    repeats: 1,
    orderSeed: 42,
    maxCalls: 1,
    budgetUsd: 10,
    pricingDigest: await fingerprintJson(pricing),
    readinessDigest: await fingerprintJson(readiness),
  });
  assertThrows(() =>
    parseRunSpec({ ...spec, version: "identification_exploratory_spec_v1" })
  );
  assertThrows(() =>
    parseRunSpec({ ...spec, profiles: [OPENAI_PROFILE, "gemini_pro"] })
  );
  assertThrows(() => parseRunSpec({ ...spec, budgetUsd: 0 }));
  await assertRejects(() =>
    validateLiveApproval(
      syntheticCorpus(),
      spec,
      pricing,
      readiness,
      "synthetic",
      Date.parse("2026-09-25T01:00:00.000Z"),
    )
  );
  await assertRejects(() => liveCredential("openai")); // Suite has no net or env grant.
});
Deno.test("OpenAI permits an explicitly shared project without relaxing legacy Gemini readiness", () => {
  const shared = { ...readiness, dedicatedEvaluationProject: false };
  assertEquals(parseEvaluationReadiness(shared), shared);
  for (const invalid of [undefined, null, "false", 0]) {
    assertThrows(() =>
      parseEvaluationReadiness({
        ...shared,
        dedicatedEvaluationProject: invalid,
      })
    );
  }
  assertThrows(() =>
    parseEvaluationReadiness({ ...shared, paidServiceApproved: false })
  );
  const { provider: _provider, inputPermission: _permission, ...legacyFields } =
    shared;
  const legacy = { ...legacyFields, version: "evaluation_processor_v1" };
  assertThrows(() => parseReadiness(legacy));
  assertThrows(() => parseEvaluationReadiness(legacy));
  assertEquals(
    parseReadiness({ ...legacy, dedicatedEvaluationProject: true }),
    {
      ...legacy,
      dedicatedEvaluationProject: true,
    },
  );
});
Deno.test("OpenAI results retain unqualified confidence, account for reasoning once and stop on drift/missing usage", async () => {
  const corpus = syntheticCorpus(),
    input = corpus.cases[1].input,
    request = openAITextFixture();
  const assignment = await assignmentFor(
    input,
    request,
    OPENAI_PROFILE,
    1,
    pricing,
  );
  assertEquals(assignment.model, OPENAI_MODEL);
  assertEquals(assignment.confidence, "openai_unqualified_v1");
  assertEquals(confidencePolicy(OPENAI_PROFILE), null);
  const taxonomy = parseTaxonomy({
    version: "evaluation_taxonomy_v1",
    taxonomyVersion: corpus.taxonomyVersion,
    taxa: [{
      taxon: { id: "synthetic:1", rank: "species" },
      names: ["Syntheticus example"],
    }],
  });
  const outcome = await createAIExecution(
    createOpenAIEvaluationAdapter(
      "synthetic",
      () => Promise.resolve(Response.json(openAIResponseFixture())),
    ),
    request,
    openAIEvaluationSnapshot(request),
  ).invoke();
  const result = projectOutcome(
    outcome,
    input,
    assignment,
    "0".repeat(64),
    taxonomy,
    pricing,
  );
  assertEquals(result.reason, "completed");
  assertEquals(result.band, "unqualified");
  assertEquals(result.diagnostic, false);
  assertEquals(result.estimatedUpperUsd, (100 * 3 + 40 * 10) / 1e6);
  assertEquals(result.usage?.modalities, null);
  assertEquals(
    estimateCost(pricing, OPENAI_MODEL, {
      ...result.usage!,
      candidateTokens: 40,
    }),
    null,
  );
  for (
    const changed of [{ ...outcome, usage: null }, {
      ...outcome,
      returnedModel: "gpt-6-sol-other",
    }]
  ) {
    const record = projectOutcome(
      changed,
      input,
      assignment,
      "0".repeat(64),
      taxonomy,
      pricing,
    );
    assert(["usage_missing", "model_mismatch"].includes(record.reason));
    if (record.usage === null) {
      assertEquals(
        guardNextAttempt([record], 5, 10, 1, true),
        "usage_missing",
      );
    }
  }
  await assertRejects(() =>
    assignmentFor(corpus.cases[2].input, request, OPENAI_PROFILE, 1, null)
  );
  assert(
    !JSON.stringify(result).includes("Syntheticus") &&
      !JSON.stringify(result).includes("ai_reasoning"),
  );
  const scored = await scoreEvaluation(corpus, syntheticPredictions(), {
    profile: OPENAI_PROFILE,
    split: "development",
    caseIds: corpus.cases.map((c) => c.input.caseId),
  });
  assertEquals(scored.metrics.strongErrorRate.status, "not_estimable");
  assertEquals(scored.metrics.diagnosticErrorRate.status, "not_estimable");
  assertEquals(scored.reliability.strong.correctness.status, "not_estimable");
  assertEquals(scored.metrics.offeredPrecision.status, "measured");
});

Deno.test("OpenAI live approval binds the supplemental input permission independently of old Gemini curation", async () => {
  const corpus = parseExploratoryCorpus({
    version: "identification_exploratory_corpus_v1",
    id: "synthetic-permission-test",
    kind: "exploratory",
    evidenceOrigin: "real",
    taxonomyVersion: "synthetic-taxonomy-v1",
    preparationVersion: "synthetic-descriptors-v1",
    splitSeed: 42,
    eligibility: {
      recordRef: "synthetic-review",
      reviewerRef: "r0001",
      reviewerKind: "owner",
      retainUntil: "2026-10-01",
    },
    cases: [{
      input: syntheticCorpus().cases[1].input,
      provisionalReference: null,
      curation: {
        kind: "eligibility_reviewed",
        source: "purpose_collected",
        sourceRecordRef: "synthetic-source",
        referenceRecordRef: null,
        permission: "gemini_evaluation",
        rightsApproved: true,
        personalDataExcluded: true,
        nearDuplicatesReviewed: true,
      },
    }],
  });
  const corpusDigest = await fingerprintRunCorpus(corpus),
    credential = "synthetic-review-key";
  const approved = {
    ...readiness,
    dedicatedEvaluationProject: false,
    corpusDigest,
    credentialSha256: await fingerprintBytes(
      new TextEncoder().encode(credential),
    ),
    inputPermission: { ...readiness.inputPermission, corpusDigest },
  };
  const spec = parseRunSpec({
    version: PROVIDER_SPEC_VERSION,
    runId: "synthetic-openai-permission",
    mode: "live",
    corpusDigest,
    taxonomyDigest: "1".repeat(64),
    split: "development",
    stage: "exploratory",
    profiles: [OPENAI_PROFILE],
    caseIds: ["c0002"],
    repeats: 1,
    orderSeed: 42,
    maxCalls: 1,
    budgetUsd: 10,
    pricingDigest: await fingerprintJson(pricing),
    readinessDigest: await fingerprintJson(approved),
  });
  const now = Date.parse("2026-09-25T01:00:00.000Z");
  await validateLiveApproval(corpus, spec, pricing, approved, credential, now);
  for (
    const change of [
      {
        ...approved,
        inputPermission: { ...approved.inputPermission, caseIds: ["c0001"] },
      },
      {
        ...approved,
        inputPermission: {
          ...approved.inputPermission,
          corpusDigest: "f".repeat(64),
        },
      },
      {
        ...approved,
        inputPermission: { ...approved.inputPermission, approved: false },
      },
      { ...approved, expiresAt: "2026-09-25T00:30:00.000Z" },
    ]
  ) {
    // Refreshing a file digest cannot make the wrong recipient/cases/date valid.
    await assertRejects(() =>
      validateLiveApproval(
        corpus,
        { ...spec, readinessDigest: "unused" },
        pricing,
        change,
        credential,
        now,
      )
    );
    const changedSpec = {
      ...spec,
      readinessDigest: await fingerprintJson(change),
    };
    await assertRejects(() =>
      validateLiveApproval(
        corpus,
        changedSpec,
        pricing,
        change,
        credential,
        now,
      )
    );
  }
  await assertRejects(() =>
    validateLiveApproval(corpus, spec, pricing, approved, "different", now)
  );
  const { inputPermission: _permission, provider: _provider, ...oldShape } =
    approved;
  const old = { ...oldShape, version: "evaluation_processor_v1" };
  const oldSpec = { ...spec, readinessDigest: await fingerprintJson(old) };
  await assertRejects(() =>
    validateLiveApproval(corpus, oldSpec, pricing, old, credential, now)
  );
  const gemini: GeminiReadiness = {
    ...approved,
    version: "evaluation_gemini_processor_v1",
    provider: "gemini",
    inputPermission: { ...approved.inputPermission, provider: "gemini" },
  };
  assertEquals(parseEvaluationReadiness(gemini), gemini);
  const geminiSpec = {
    ...spec,
    readinessDigest: await fingerprintJson(gemini),
  };
  await assertRejects(() =>
    validateLiveApproval(
      corpus,
      geminiSpec,
      pricing,
      gemini,
      credential,
      now,
    )
  );
});
