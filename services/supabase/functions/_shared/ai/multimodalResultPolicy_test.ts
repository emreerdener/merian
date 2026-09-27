import { assert, assertEquals, assertThrows } from "@std/assert";
import type {
  AIAttemptSnapshot,
  AIExecutionOutcome,
  GeminiAttemptSnapshot,
  MultimodalAIRequest,
} from "./contracts.ts";
import { identificationInputProfile } from "./identificationInput.ts";
import { resolveAIClaim } from "./registry.ts";
import { openAIEvaluationSnapshot } from "./openaiRequest.ts";
import { openAITextFixture } from "./testing/openaiFixtures.ts";
import { prepareMultimodalResultPolicy } from "./multimodalResultPolicy.ts";
import { diagnosticTriggerForTier } from "../identify/thresholds.ts";

function snapshot(
  request = openAITextFixture(),
  model = "gemini-2.5-flash",
  tier: "free" | "pro" = "free",
): GeminiAttemptSnapshot {
  return resolveAIClaim(request, {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 7,
      model,
      tier: { effective_tier: tier },
      assignment: {
        inputProfile: identificationInputProfile(request),
        provider: "gemini",
        binding: "gemini_baseline_v1",
        permission: "google_gemini",
      },
    },
  });
}
function outcome(
  execution: AIAttemptSnapshot = snapshot(),
): AIExecutionOutcome {
  return {
    kind: "draft",
    draft: {},
    execution: { ...execution, durationMs: 1 },
    providerDurationMs: 1,
    providerCompletedAt: 1,
    returnedModel: null,
    usage: null,
    finishReason: "STOP",
    responseCharacters: 0,
  };
}

Deno.test("result policy preserves all Gemini primary profiles independently of model/tier", () => {
  const image = {
    kind: "image" as const,
    order: 0,
    data: "AQ==",
    mimeType: "image/webp",
    inputIndex: 0,
    lineage: null,
  };
  const audio = {
    kind: "audio" as const,
    order: 0,
    data: "AQ==",
    mimeType: "audio/wav" as const,
    inputIndex: 0,
    lineage: null,
  };
  const text = openAITextFixture();
  const requests: MultimodalAIRequest[] = [
    text,
    { ...text, evidence: [image] },
    { ...text, evidence: [audio] },
    { ...text, evidence: [image, { ...audio, order: 1 }] },
    {
      ...text,
      capture: { ...text.capture, hasVideo: true, videoInferenceFrameCount: 1 },
      evidence: [{
        ...image,
        lineage: { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
      }],
    },
  ];
  for (const request of requests) {
    for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
      for (const tier of ["free", "pro"] as const) {
        const claim = snapshot(request, model, tier);
        const policy = prepareMultimodalResultPolicy(claim);
        assertEquals(policy.confidence, {
          kind: "diagnostic_threshold",
          threshold: diagnosticTriggerForTier(tier === "pro" ? "pro" : "flash"),
        });
        assert(Object.isFrozen(policy));
        assert(Object.isFrozen(policy.confidence));
        for (
          const probability of [
            undefined,
            "NEGLIGIBLE",
            "LOW",
            "MEDIUM",
            "HIGH",
          ]
        ) {
          const safetyRatings = probability ? [{ probability }] : undefined;
          const result = { ...outcome(claim), safetyRatings };
          assertEquals(policy.safetySignals(result), {
            finishReason: "STOP",
            safetyRatings,
          });
        }
      }
    }
  }
});

Deno.test("OpenAI evaluation and unknown result policies cannot authorize production media handling", () => {
  const base = snapshot();
  const invalid: unknown[] = [
    openAIEvaluationSnapshot(openAITextFixture()),
    ...Object.entries({
      provider: "unknown",
      binding: "unknown",
      model: "unknown",
      task: "species_overview",
      variant: "vision_compat",
      contextKind: "evaluation",
      operation: "scan_audio_identification",
      permission: "openai",
      confidence: "openai_unqualified_v1",
      schema: "merian_audio_v2",
      prompt: "identify_audio_v2",
      safety: "biological_vision_v1",
      diagnosticTrigger: undefined,
    }).map(([field, value]) => ({ ...base, [field]: value })),
    ...[null, NaN, 0, .95, 1].map((diagnosticTrigger) => ({
      ...base,
      diagnosticTrigger,
    })),
  ];
  for (const value of invalid) {
    assertThrows(
      () => prepareMultimodalResultPolicy(value as AIAttemptSnapshot),
      Error,
      "ai_identification_result_policy_unavailable",
    );
  }
});

Deno.test("prepared result policy rejects mismatched or unqualified execution before exposing safety signals", () => {
  const base = snapshot();
  const policy = prepareMultimodalResultPolicy(base);
  assertThrows(
    () => policy.safetySignals(outcome({ ...base, model: "gemini-2.5-pro" })),
    Error,
    "ai_identification_result_policy_mismatch",
  );
  assertThrows(
    () =>
      policy.safetySignals(
        outcome(
          openAIEvaluationSnapshot(
            openAITextFixture(),
          ) as unknown as AIAttemptSnapshot,
        ),
      ),
    Error,
    "ai_identification_result_policy_unavailable",
  );
  assertEquals(
    policy.safetySignals({
      ...outcome(base),
      kind: "refusal",
      finishReason: "SAFETY",
    }),
    {
      finishReason: "SAFETY",
      safetyRatings: undefined,
    },
  );
});
