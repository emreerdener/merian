import { assert, assertEquals, assertThrows } from "@std/assert";
import type { AIAttemptSnapshot, MultimodalAIRequest } from "./contracts.ts";
import { isIdentificationProviderAssignment } from "./admission.ts";
import { prepareMultimodalResultPolicy } from "./multimodalResultPolicy.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIPhotoModelRequestParameters,
  isOpenAIPhotoModelProfile,
  openAIPhotoModelSnapshot,
} from "./openaiPhotoModels.ts";
import { decodeOpenAIDraft, isOpenAIProfile } from "./openaiRequest.ts";
import {
  buildOpenAIObservedTraitsRequest,
  OBSERVED_TRAITS_PROFILE,
  OBSERVED_TRAITS_SCHEMA,
  openAIObservedTraitsInstructions,
  openAIObservedTraitsSchema,
  openAIObservedTraitsSnapshot,
} from "./openaiObservedTraits.ts";
import { decodeSolPhotoPrimaryDraft } from "./openaiSolPrimaryContract.ts";
import {
  openAIDraftFixture,
  openAIPhotoRequestFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";
import {
  fingerprintBytes,
  fingerprintJson,
} from "../../identify-multimodal/comparison/fingerprint.ts";

const baseline = (request = openAIPhotoRequestFixture()) =>
  buildOpenAIPhotoModelRequestParameters(
    request,
    openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
  );
const candidate = (request = openAIPhotoRequestFixture()) =>
  buildOpenAIObservedTraitsRequest(
    request,
    openAIObservedTraitsSnapshot(request),
  );
const baselineDirection =
  "You MUST extract 3 structural observations in `extracted_visual_traits` BEFORE determining `is_biological_subject` or `scientific_name`.";
const candidateDirection =
  "Extract one to three distinct physical or structural observations in `extracted_visual_traits` BEFORE determining `is_biological_subject` or `scientific_name`. Include only features directly supported by the supplied visual evidence. If only one or two features are supportable, return those; never invent, repeat or infer unseen anatomy to reach three. Keep material visibility limitations in the existing 1–3 sentence `ai_reasoning`, not as substitute traits.";

Deno.test("observed-traits request changes only two directions and schema identity for complete photo observations", () => {
  const base = openAIPhotoRequestFixture();
  const photo = base.evidence[0];
  if (photo.kind !== "image") throw new Error("photo_fixture_required");
  const requests: MultimodalAIRequest[] = [base, {
    ...base,
    evidence: [photo],
  }, {
    ...base,
    evidence: [photo, {
      ...photo,
      data: "BAUG",
      order: 1,
      inputIndex: 1,
      lineage: { kind: "image", sourceIndex: 1 },
    }, { ...base.evidence[1], order: 2 }],
  }];
  for (const request of requests) {
    const originalInput = structuredClone(request);
    const production = buildOpenAIPhotoRequestParameters(
      request,
      openAIPhotoSnapshot(request, 1),
    );
    const base = baseline(request);
    const expected = structuredClone(base);
    expected.instructions = expected.instructions.replace(
      baselineDirection,
      candidateDirection,
    );
    expected.text.format.schema.properties!.extracted_visual_traits
      .description =
        "Extract one to three distinct physical or structural traits directly supported by the supplied visual evidence. Return only supportable observations, without inventing, repeating or inferring unseen anatomy to reach three. Visibility limitations belong in ai_reasoning, not as substitute traits.";
    assertEquals(production, expected);
    assertEquals(candidate(request), {
      ...expected,
      text: {
        ...expected.text,
        format: { ...expected.text.format, name: OBSERVED_TRAITS_SCHEMA },
      },
    });
    assertEquals(baseline(request), base);
    assertEquals(request, originalInput);
  }
});

Deno.test("observed-traits candidate and untouched baseline identities are frozen", async () => {
  for (
    const [parameters, promptHash, schemaHash] of [
      [
        baseline(),
        "338754d17eb1abde90ad7d9ed66dd552043e0b56028b0265522857e979a86c09",
        "e679315d0b431bbecd562f24542257acccac017e0bf4c88ea3664370d3a61871",
      ],
      [
        candidate(),
        "f422b49ef1a0cd459f674f1d11d24da37f130c2b9202a421b90ede497b127f7e",
        "8e3b788d78c7427fb391b78f39a8d2d79f1d40738344f1b34f335c38f7be4486",
      ],
    ] as const
  ) {
    assertEquals(
      await fingerprintBytes(new TextEncoder().encode(parameters.instructions)),
      promptHash,
    );
    assertEquals(await fingerprintJson(parameters.text.format), schemaHash);
  }
  assertEquals(
    await fingerprintJson(
      openAIObservedTraitsSnapshot(openAIPhotoRequestFixture()),
    ),
    "e966db489fb0167ba634d1ba9ba147c258673cb5eacd4d471f77a659ccf05230",
  );
});

Deno.test("observed-traits projection rejects instruction or schema drift without modifying its source", () => {
  const base = baseline();
  for (
    const instructions of [
      base.instructions.replace(baselineDirection, "Changed direction."),
      base.instructions + baselineDirection,
    ]
  ) {
    assertThrows(
      () => openAIObservedTraitsInstructions(instructions),
      Error,
      "openai_observed_traits_baseline_drift",
    );
  }
  for (
    const change of [
      { description: "Changed description." },
      { minItems: 0 },
      { maxItems: 3 },
      { type: ["array", "null"] },
    ]
  ) {
    const schema = structuredClone(base.text.format.schema);
    Object.assign(schema.properties!.extracted_visual_traits, change);
    assertThrows(
      () => openAIObservedTraitsSchema(schema),
      Error,
      "openai_observed_traits_schema_drift",
    );
  }
  const schema = structuredClone(base.text.format.schema);
  delete schema.properties!.extracted_visual_traits;
  assertThrows(() => openAIObservedTraitsSchema(schema));
  const projected = openAIObservedTraitsSchema(base.text.format.schema);
  projected.properties!.extracted_visual_traits.description = "Changed copy.";
  assertEquals(base, baseline());
});

Deno.test("observed-traits identity cannot enter production or a historical evaluator", () => {
  const request = openAIPhotoRequestFixture();
  const snapshot = openAIObservedTraitsSnapshot(request);
  assertEquals(snapshot.confidence, "openai_unqualified_v1");
  assertEquals(isOpenAIProfile(OBSERVED_TRAITS_PROFILE), false);
  assertEquals(isOpenAIPhotoModelProfile(OBSERVED_TRAITS_PROFILE), false);
  assertEquals(
    isIdentificationProviderAssignment({
      provider: "openai",
      binding: snapshot.binding,
      inputProfile: "multimodal_photo_v1",
      permission: "openai",
    }),
    false,
  );
  assertThrows(() =>
    prepareMultimodalResultPolicy(snapshot as unknown as AIAttemptSnapshot)
  );
  assertThrows(() =>
    buildOpenAIPhotoRequestParameters(
      request,
      snapshot as unknown as ReturnType<typeof openAIPhotoSnapshot>,
    )
  );
  assertThrows(() =>
    buildOpenAIPhotoModelRequestParameters(
      request,
      snapshot as unknown as ReturnType<typeof openAIPhotoModelSnapshot>,
    )
  );
  for (
    const change of [
      { profile: "openai_photo_sol_low_v1" },
      { binding: "openai_photo_v1" },
      { prompt: "changed" },
      { schema: "merian_openai_identify_v1" },
      { model: "gpt-6-luna" },
      { safety: null },
      { moderationModel: "changed" },
      { contextKind: "user_request" },
      { timeoutMs: 180000 },
      { confidence: "qualified" },
      { generation: { ...snapshot.generation, reasoningEffort: "high" } },
      { unexpected: true },
    ]
  ) {
    assertThrows(() =>
      buildOpenAIObservedTraitsRequest(
        request,
        {
          ...snapshot,
          ...change,
        } as typeof snapshot,
      )
    );
  }
});

Deno.test("observed-traits retains whole-observation still-photo validation", () => {
  const base = openAIPhotoRequestFixture();
  for (
    const request of [openAITextFixture(), {
      ...base,
      capture: { ...base.capture, hasVideo: true },
    }, {
      ...base,
      evidence: [...base.evidence, {
        kind: "audio",
        order: 2,
        inputIndex: 0,
        lineage: null,
        mimeType: "audio/wav",
        data: "AQID",
      }],
    }, {
      ...base,
      evidence: [{
        kind: "image",
        order: 0,
        inputIndex: 0,
        lineage: { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
        mimeType: "image/png",
        data: "AQID",
      }],
    }] satisfies MultimodalAIRequest[]
  ) {
    assertThrows(() => openAIObservedTraitsSnapshot(request));
    assertThrows(() =>
      buildOpenAIObservedTraitsRequest(
        request,
        openAIObservedTraitsSnapshot(base),
      )
    );
  }
});

Deno.test("existing decoder supports shorter traits without narrowing or widening wire bounds", () => {
  const fixture = openAIDraftFixture();
  // Synthetic descriptions exercise compatibility, not biological correctness.
  for (const count of [1, 2, 3, 4, 10]) {
    const traits = Array.from(
      { length: count },
      (_, i) => `Synthetic trait ${i}`,
    );
    const value = { ...fixture, extracted_visual_traits: traits };
    const decoded = decodeOpenAIDraft(value);
    assertEquals(decoded.extracted_visual_traits, traits);
    assertEquals(decoded.ai_reasoning, decodeOpenAIDraft(fixture).ai_reasoning);
    assertEquals(decoded.candidates, decodeOpenAIDraft(fixture).candidates);
    assertThrows(() => decodeSolPhotoPrimaryDraft(value));
  }
  for (
    const traits of [
      [],
      Array(11).fill("Trait"),
      [""],
      ["x".repeat(501)],
      [null],
      [42],
      null,
    ]
  ) {
    assertThrows(() =>
      decodeOpenAIDraft({ ...fixture, extracted_visual_traits: traits })
    );
  }
  assertThrows(() => decodeOpenAIDraft({ ...fixture, unexpected: true }));
  const missing = { ...fixture };
  delete missing.extracted_visual_traits;
  assertThrows(() => decodeOpenAIDraft(missing));
  assert(candidate().instructions.includes("not as substitute traits"));
});
