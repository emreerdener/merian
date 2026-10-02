import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createOpenAIPhotoEvidenceEvaluationAdapter } from "./openai.ts";
import { isIdentificationProviderAssignment } from "./admission.ts";
import { createAIExecution } from "./execution.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIPhotoEvidenceRequest,
  openAIPhotoEvidenceSnapshot,
} from "./openaiPhotoEvidence.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
} from "./testing/openaiFixtures.ts";

Deno.test("evidence candidate preserves pixels, settings, output shape, explanation and confidence rule", () => {
  const request = openAIPhotoRequestFixture();
  const baseline = buildOpenAIPhotoRequestParameters(
    request,
    openAIPhotoSnapshot(request, 1),
  );
  const snapshot = openAIPhotoEvidenceSnapshot(request);
  const candidate = buildOpenAIPhotoEvidenceRequest(request, snapshot);
  assertEquals(isIdentificationProviderAssignment(snapshot), false);
  const stripDescriptions = (v: unknown): unknown =>
    Array.isArray(v)
      ? v.map(stripDescriptions)
      : v && typeof v === "object"
      ? Object.fromEntries(
        Object.entries(v).filter(([k]) => k !== "description").map((
          [k, v],
        ) => [k, stripDescriptions(v)]),
      )
      : v;
  assertEquals({
    ...candidate,
    instructions: baseline.instructions,
    text: baseline.text,
  }, baseline);
  assertEquals(
    stripDescriptions(candidate.text),
    stripDescriptions(baseline.text),
  );
  for (
    const key of ["ai_reasoning", "confidence_score", "extracted_visual_traits"]
  ) {
    assertEquals(
      candidate.text.format.schema.properties?.[key],
      baseline.text.format.schema.properties?.[key],
    );
  }
  assertEquals(
    candidate.instructions.includes(
      "A lower `confidence_score` or a disclaimer cannot justify an unsupported species name.",
    ),
    true,
  );
  assertEquals(
    candidate.instructions.includes(
      "Missing, obscured, or unphotographed features are unknown, not absent.",
    ),
    true,
  );
  assertThrows(() =>
    buildOpenAIPhotoEvidenceRequest(
      request,
      { ...snapshot, timeoutMs: 1 } as unknown as typeof snapshot,
    )
  );
});

Deno.test("evidence candidate dispatches once and retains moderation and accounting rejection", async () => {
  const request = openAIPhotoRequestFixture(),
    snapshot = openAIPhotoEvidenceSnapshot(request);
  for (const moderation of [true, false]) {
    let calls = 0;
    const execution = createAIExecution(
      createOpenAIPhotoEvidenceEvaluationAdapter("synthetic", (_url, init) => {
        calls++;
        assertEquals(
          JSON.parse(String(init?.body)),
          JSON.parse(
            JSON.stringify(buildOpenAIPhotoEvidenceRequest(request, snapshot)),
          ),
        );
        return Promise.resolve(
          Response.json({
            ...openAIResponseFixture(),
            ...(moderation
              ? { moderation: openAIPhotoModerationFixture() }
              : {}),
          }),
        );
      }),
      request,
      snapshot,
    );
    assertEquals(
      (await execution.invoke()).kind,
      moderation ? "draft" : "invalid_output",
    );
    await assertRejects(() => execution.invoke());
    assertEquals(calls, 1);
  }
});
