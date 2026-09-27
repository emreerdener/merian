import type { IdentificationInputProfile } from "./identificationInput.ts";
import { assert, assertEquals, assertThrows } from "@std/assert";
import { identificationProvenance } from "./provenance.ts";
import { openAIPhotoSnapshot } from "./openaiPhoto.ts";
import { openAITextFixture } from "./testing/openaiFixtures.ts";
import { resolveAIClaim } from "./registry.ts";
import type {
  AIAttemptSnapshot,
  AIRequest,
  UserRequestAuthority,
} from "./contracts.ts";

function authority(
  model: string,
  tier: "free" | "pro",
  operation = "scan_identification",
  inputProfile: IdentificationInputProfile = "description_compat_v1",
): UserRequestAuthority {
  return {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "google_gemini",
    operation,
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 7,
      model,
      tier: { effective_tier: tier },
      assignment: {
        inputProfile,
        provider: "gemini",
        binding: "gemini_baseline_v1",
        permission: "google_gemini",
      },
    },
  };
}
const description: AIRequest = {
  task: "identify",
  variant: "description_compat",
  evidence: [
    {
      kind: "text",
      source: "description",
      order: 0,
      text: "Synthetic private observation",
    },
  ],
};

Deno.test("OpenAI provenance v2 records native settings without invented Gemini equivalents", () => {
  const request = openAITextFixture();
  const snapshot = openAIPhotoSnapshot({
    ...request,
    evidence: [{
      kind: "image",
      order: 0,
      inputIndex: 0,
      lineage: null,
      data: "AQID",
      mimeType: "image/png",
    }],
  }, 2);
  const value = identificationProvenance(snapshot);
  assertEquals(value.version, 2);
  assertEquals(value.provider, "openai");
  assertEquals(value.safety, "openai_photo_moderation_v1");
  assertEquals(value.confidence, "openai_unqualified_v1");
  assertEquals(value.diagnostic_trigger, null);
  assertEquals(value.prompt_diagnostic_trigger, null);
  assertEquals(value.generation, {
    max_output_tokens: 8192,
    reasoning_effort: "low",
    image_detail: "high",
  });
  assert(Object.isFrozen(value) && Object.isFrozen(value.generation));
  assert(!JSON.stringify(value).includes("AQID"));
});

Deno.test("provenance preserves the prepared model, prompt, generation and confidence independently of tier", () => {
  for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
    for (const tier of ["free", "pro"] as const) {
      const claim = resolveAIClaim(description, authority(model, tier));
      const value = identificationProvenance(claim);
      assertEquals(value.model, model);
      assertEquals(value.prompt, "identify_describe_v1");
      assertEquals(value.schema, "merian_describe_v1");
      assertEquals(value.confidence, "gemini_describe_v1");
      assertEquals(value.policy_version, 7);
      assertEquals(value.generation, {
        temperature: 0.15,
        seed: 42,
        top_k: 40,
        max_output_tokens: model.endsWith("pro") ? 4096 : 2048,
        thinking_budget: model.endsWith("pro") ? 3000 : 1024,
      });
      assert(Object.isFrozen(value));
      assert(Object.isFrozen(value.generation));
    }
  }
});
Deno.test("provenance explicitly preserves absent generation settings and separate vision thresholds", () => {
  const image = {
    kind: "image" as const,
    order: 0,
    data: "AQ==",
    mimeType: "image/webp",
    inputIndex: 0,
    lineage: null,
  };
  const capture = {
    hasVideo: false,
    videoClipCount: 0,
    declaredVideoFrameCount: 0,
    videoInferenceFrameCount: 0,
  };
  const main = resolveAIClaim(
    {
      task: "identify",
      variant: "multimodal",
      evidence: [image],
      capture,
    },
    authority(
      "gemini-2.5-flash",
      "free",
      "scan_identification",
      "multimodal_photo_v1",
    ),
  );
  const value = identificationProvenance(main);
  assertEquals(value.generation.thinking_budget, null);
  assertEquals(value.generation.top_k, null);
  assertEquals(value.safety, null);
  const legacy = identificationProvenance(
    resolveAIClaim(
      {
        task: "identify",
        variant: "vision_compat",
        evidence: [image],
      },
      authority(
        "gemini-2.5-pro",
        "free",
        "scan_identification",
        "vision_compat_v1",
      ),
    ),
  );
  assertEquals(legacy.diagnostic_trigger, main.diagnosticTrigger!);
  assertEquals(legacy.prompt_diagnostic_trigger, 0.99);
  assertEquals(legacy.safety, "biological_vision_v1");
});
Deno.test("provenance projects a closed shape and never serializes response, authority, evidence or timing", () => {
  const claim = resolveAIClaim(
    description,
    authority("gemini-2.5-flash", "free"),
  );
  const value = identificationProvenance(
    {
      ...claim,
      durationMs: 1,
      response: "synthetic output",
      userId: "synthetic-owner",
      generation: { ...claim.generation, unreviewed: "synthetic secret" },
    } as AIAttemptSnapshot,
  );
  const serialized = JSON.stringify(value);
  for (
    const excluded of [
      "synthetic",
      "durationMs",
      "userId",
      "unreviewed",
      "permission",
      "contextKind",
    ]
  ) {
    assert(!serialized.includes(excluded));
  }
  const retry = identificationProvenance({ ...claim, policyVersion: 8 });
  assertEquals(value.policy_version, 7);
  assertEquals(retry.policy_version, 8);
  assertThrows(
    () => identificationProvenance({ ...claim, contextKind: "service_job" }),
    Error,
    "authority_invalid",
  );
  assertThrows(
    () => identificationProvenance({ ...claim, confidence: null }),
    Error,
    "authority_invalid",
  );
});
