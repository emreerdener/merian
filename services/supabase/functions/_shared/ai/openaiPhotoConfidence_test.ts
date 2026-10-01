import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createAIExecution } from "./execution.ts";
import { isIdentificationProviderAssignment } from "./admission.ts";
import { prepareMultimodalResultPolicy } from "./multimodalResultPolicy.ts";
import {
  createOpenAIConfidenceEvaluationAdapter,
  createOpenAIPhotoAdapter,
} from "./openai.ts";
import {
  buildOpenAIPhotoRequestParameters,
  OPENAI_PHOTO_MODERATION_MODEL,
  openAIObservedTraitsInstructions,
  openAIObservedTraitsSchema,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIRequestParameters,
  openAIEvaluationSnapshot,
} from "./openaiRequest.ts";
import {
  buildOpenAIConfidenceRequest,
  OPENAI_PHOTO_CONFIDENCE_RULE,
  openAIConfidenceInstructions,
  openAIConfidenceSchema,
  openAIConfidenceSnapshot,
} from "./openaiPhotoConfidence.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
} from "./testing/openaiFixtures.ts";

Deno.test("activated confidence prompt preserves the assessed request and normalized results in both production and evaluation", async () => {
  const request = openAIPhotoRequestFixture(),
    snapshot = openAIConfidenceSnapshot(request);
  const production = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  const actual = buildOpenAIConfidenceRequest(request, snapshot);
  const historical = buildOpenAIRequestParameters(
    request,
    openAIEvaluationSnapshot(request),
  );
  const expected = {
    ...historical,
    instructions: openAIConfidenceInstructions(
      openAIObservedTraitsInstructions(historical.instructions),
    ),
    text: {
      ...historical.text,
      format: {
        ...historical.text.format,
        schema: openAIConfidenceSchema(
          openAIObservedTraitsSchema(historical.text.format.schema),
        ),
      },
    },
    moderation: { model: OPENAI_PHOTO_MODERATION_MODEL },
  };
  assertEquals(snapshot.prompt, "openai_identify_vision_confidence_v1");
  assertEquals(snapshot.confidence, "openai_unqualified_v1");
  assertEquals(actual, expected);
  assertEquals(production, expected);
  const allInstructions = actual.instructions +
    JSON.stringify(actual.text.format.schema);
  for (
    const obsolete of [
      "0.70–0.88",
      "ANCHORS:",
      "Reserve ≥0.90",
      "Calibrated confidence",
    ]
  ) {
    assert(!allInstructions.includes(obsolete), obsolete);
  }
  assert(allInstructions.includes("one to three distinct"));
  assert(actual.instructions.includes(OPENAI_PHOTO_CONFIDENCE_RULE));
  assertEquals(
    actual.text.format.schema.properties!.confidence_score.description,
    OPENAI_PHOTO_CONFIDENCE_RULE,
  );
  assert(historical.instructions.includes("0.70–0.88"));
  assertThrows(() =>
    openAIConfidenceInstructions(
      historical.instructions + historical.instructions,
    )
  );
  assertThrows(() =>
    openAIConfidenceSchema({ ...production.text.format.schema, properties: {} })
  );
  let calls = 0;
  const execution = createAIExecution(
    createOpenAIConfidenceEvaluationAdapter(
      "synthetic-confidence",
      (_url, init) => {
        calls++;
        assertEquals(
          JSON.parse(String(init?.body)),
          JSON.parse(JSON.stringify(actual)),
        );
        return Promise.resolve(
          Response.json({
            ...openAIResponseFixture(),
            moderation: openAIPhotoModerationFixture(),
          }),
        );
      },
    ),
    request,
    snapshot,
  );
  assertEquals(calls, 0);
  const result = await execution.invoke();
  assertEquals(result.kind, "draft");
  assertEquals(result.mediaSafety?.disposition, "allowed");
  await assertRejects(() => execution.invoke());
  assertEquals(calls, 1);
  // The revised prompt is active, but evaluation authority is still never admitted.
  let productionCalls = 0;
  const productionResult = await createAIExecution(
    createOpenAIPhotoAdapter("synthetic-confidence", (_url, init) => {
      productionCalls++;
      assertEquals(
        JSON.parse(String(init?.body)),
        JSON.parse(JSON.stringify(actual)),
      );
      return Promise.resolve(Response.json({
        ...openAIResponseFixture(),
        moderation: openAIPhotoModerationFixture(),
      }));
    }),
    request,
    openAIPhotoSnapshot(request, 1),
  ).invoke();
  assertEquals(productionCalls, 1);
  assertEquals(productionResult.kind, result.kind);
  if (productionResult.kind !== "draft" || result.kind !== "draft") {
    throw new Error("draft_required");
  }
  assertEquals(productionResult.draft, result.draft);
  assertEquals(productionResult.mediaSafety, result.mediaSafety);
  for (
    const rejected of [snapshot, {
      ...openAIPhotoSnapshot(request, 1),
      prompt: "openai_identify_vision_observed_traits_v1",
    }]
  ) {
    assertThrows(() =>
      createOpenAIPhotoAdapter("synthetic-confidence").prepare(
        request,
        rejected as never,
      )
    );
  }
  assertEquals(
    openAIPhotoSnapshot(request, 1).prompt,
    "openai_identify_vision_confidence_v1",
  );
  assertEquals(
    isIdentificationProviderAssignment({
      provider: "openai",
      binding: snapshot.binding,
      inputProfile: "multimodal_photo_v1",
      permission: "openai",
    }),
    false,
  );
  assertThrows(() => prepareMultimodalResultPolicy(snapshot as never));
});

Deno.test("confidence candidate retains inline moderation failures and rejects modified settings", async () => {
  const request = openAIPhotoRequestFixture(),
    snapshot = openAIConfidenceSnapshot(request);
  assertThrows(() =>
    buildOpenAIConfidenceRequest(
      request,
      { ...snapshot, model: "altered" } as never,
    )
  );
  const result = await createAIExecution(
    createOpenAIConfidenceEvaluationAdapter(
      "synthetic-confidence",
      () => Promise.resolve(Response.json(openAIResponseFixture())),
    ),
    request,
    snapshot,
  ).invoke();
  assertEquals(result.kind, "invalid_output");
});
