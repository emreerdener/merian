import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createOpenAIPhotoReasoningEvaluationAdapter } from "./openai.ts";
import { createAIExecution } from "./execution.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIPhotoReasoningRequest,
  openAIPhotoReasoningSnapshot,
} from "./openaiPhotoReasoning.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
} from "./testing/openaiFixtures.ts";
import { isIdentificationProviderAssignment } from "./admission.ts";

Deno.test("reasoning comparison transport changes only effort and cannot select production admission", async () => {
  const request = openAIPhotoRequestFixture();
  const production = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  for (const effort of ["low", "medium"] as const) {
    const snapshot = openAIPhotoReasoningSnapshot(request, effort);
    assertEquals(isIdentificationProviderAssignment(snapshot), false);
    const expected = { ...production, reasoning: { effort } };
    assertEquals(buildOpenAIPhotoReasoningRequest(request, snapshot), expected);
    let calls = 0;
    const execution = createAIExecution(
      createOpenAIPhotoReasoningEvaluationAdapter(
        "synthetic-reasoning",
        (_url, init) => {
          calls++;
          assertEquals(
            JSON.parse(String(init?.body)),
            JSON.parse(JSON.stringify(expected)),
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
    const outcome = await execution.invoke();
    assertEquals(outcome.kind, "draft");
    assertEquals(outcome.mediaSafety?.disposition, "allowed");
    await assertRejects(() => execution.invoke());
    assertEquals(calls, 1);
    assertThrows(() =>
      buildOpenAIPhotoReasoningRequest(
        request,
        { ...snapshot, timeoutMs: 1 } as unknown as typeof snapshot,
      )
    );
  }
  assertEquals(
    openAIPhotoSnapshot(request, 1).generation.reasoningEffort,
    "low",
  );
});

Deno.test("medium retains native moderation and contradictory usage rejection", async () => {
  const request = openAIPhotoRequestFixture(),
    snapshot = openAIPhotoReasoningSnapshot(request, "medium");
  const fixtures = [
    { ...openAIResponseFixture() },
    {
      ...openAIResponseFixture(),
      moderation: openAIPhotoModerationFixture(),
      usage: {
        input_tokens: 100,
        output_tokens: 30,
        total_tokens: 130,
        input_tokens_details: { cached_tokens: 50, cache_write_tokens: 51 },
        output_tokens_details: { reasoning_tokens: 10 },
      },
    },
  ];
  const results = [];
  for (const fixture of fixtures) {
    results.push(
      await createAIExecution(
        createOpenAIPhotoReasoningEvaluationAdapter(
          "synthetic-reasoning",
          () => Promise.resolve(Response.json(fixture)),
        ),
        request,
        snapshot,
      ).invoke(),
    );
  }
  assertEquals(results[0].kind, "invalid_output");
  assertEquals(results[1].usage, null);
});
