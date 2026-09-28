import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { MultimodalAIRequest } from "./contracts.ts";
import { createAIExecution } from "./execution.ts";
import { prepareMultimodalResultPolicy } from "./multimodalResultPolicy.ts";
import { createOpenAIPhotoAdapter, OPENAI_RESPONSES_URL } from "./openai.ts";
import {
  buildOpenAIPhotoRequestParameters,
  OPENAI_PHOTO_MODERATION_MODEL,
  openAIPhotoSafety,
  openAIPhotoSnapshot,
} from "./openaiPhoto.ts";
import {
  buildOpenAIRequestParameters,
  openAIEvaluationSnapshot,
} from "./openaiRequest.ts";
import {
  openAIPhotoModerationFixture as moderationFixture,
  openAIPhotoRequestFixture as photoRequest,
  openAIResponseFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";

Deno.test("photo candidate keeps all evidence and measured generation settings with one inline moderation request", async () => {
  const base = photoRequest(),
    request = { ...base, evidence: [...base.evidence] },
    snapshot = openAIPhotoSnapshot(request, 2);
  const expected = {
    ...buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request)),
    moderation: { model: OPENAI_PHOTO_MODERATION_MODEL },
  };
  assertEquals(buildOpenAIPhotoRequestParameters(request, snapshot), expected);
  assert(
    !("moderation" in
      buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request))),
  );
  let calls = 0;
  const execution = createAIExecution(
    createOpenAIPhotoAdapter("synthetic-photo", (url, init) => {
      calls++;
      assertEquals(url, OPENAI_RESPONSES_URL);
      assertEquals(
        JSON.parse(String(init?.body)),
        JSON.parse(JSON.stringify(expected)),
      );
      return Promise.resolve(
        Response.json({
          ...openAIResponseFixture(),
          moderation: moderationFixture(),
        }),
      );
    }),
    request,
    snapshot,
  );
  assertEquals(calls, 0);
  request.evidence[1] = {
    kind: "text",
    source: "observation_context",
    order: 1,
    text: "LATE_MUTATION",
  };
  const result = await execution.invoke();
  assertEquals(result.kind, "draft");
  assertEquals(result.mediaSafety?.disposition, "allowed");
  assertEquals(result.safetyRatings, undefined);
  assertEquals(result.execution.moderationModel, OPENAI_PHOTO_MODERATION_MODEL);
  await assertRejects(
    () => execution.invoke(),
    Error,
    "ai_attempt_already_invoked",
  );
  assertEquals(calls, 1);
});

Deno.test("photo candidate never admits text-only, audio, sampled video or altered configuration", () => {
  const base = photoRequest();
  const cases: MultimodalAIRequest[] = [openAITextFixture(), {
    ...base,
    capture: { ...base.capture, hasVideo: true },
  }, {
    ...base,
    evidence: [...base.evidence, {
      kind: "audio",
      order: 2,
      inputIndex: 0,
      lineage: null,
      data: "AQID",
      mimeType: "audio/wav",
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
  }];
  for (const request of cases) {
    assertThrows(() => openAIPhotoSnapshot(request, 2));
  }
  const snapshot = openAIPhotoSnapshot(base, 2);
  for (
    const change of [
      { safety: undefined },
      { moderationModel: "omni-moderation-latest" },
      { generation: { ...snapshot.generation, reasoningEffort: "high" } },
      { permission: "google_gemini" },
      { contextKind: "evaluation" },
    ]
  ) {
    assertThrows(() =>
      buildOpenAIPhotoRequestParameters(
        base,
        { ...snapshot, ...change } as typeof snapshot,
      )
    );
  }
  for (const policy of [0, -1, 1.5, Infinity, 1_000_000_000]) {
    assertThrows(() => openAIPhotoSnapshot(base, policy));
  }
  assertEquals(prepareMultimodalResultPolicy(snapshot).confidence, {
    kind: "unqualified",
  });
});

Deno.test("photo safety requires complete native input and output evidence without treating text-only categories as image coverage", () => {
  assertEquals(
    openAIPhotoSafety(moderationFixture(), true).disposition,
    "allowed",
  );
  const noText = moderationFixture();
  for (
    const [category, types] of Object.entries(
      noText.input.category_applied_input_types,
    )
  ) {
    noText.input.category_applied_input_types[category] = types.filter((t) =>
      t !== "text"
    );
  }
  assertEquals(openAIPhotoSafety(noText, false).disposition, "allowed");
  assertEquals(openAIPhotoSafety(noText, true).disposition, "unavailable");
  const invalid: unknown[] = [undefined, null, {}, {
    input: moderationFixture().input,
  }, { output: moderationFixture().output }];
  for (const side of ["input", "output"] as const) {
    for (
      const change of [
        { type: "error", code: "PRIVATE_CODE", message: "PRIVATE_DIAGNOSTIC" },
        { model: "omni-moderation-latest" },
        { model: "unreviewed" },
        { flagged: "false" },
        { flagged: true },
        { categories: {} },
        { category_scores: {} },
        { category_applied_input_types: {} },
      ]
    ) {
      const fixture = moderationFixture();
      invalid.push({ ...fixture, [side]: { ...fixture[side], ...change } });
    }
    for (const score of [-1, 2, NaN, Infinity, "0.1", null]) {
      const fixture = moderationFixture();
      invalid.push({
        ...fixture,
        [side]: {
          ...fixture[side],
          category_scores: { ...fixture[side].category_scores, sexual: score },
        },
      });
    }
  }
  for (
    const types of [[], ["text"], ["image", "image"], [
      "text",
      "image",
      "audio",
    ], "image"]
  ) {
    const fixture = moderationFixture();
    invalid.push({
      ...fixture,
      input: {
        ...fixture.input,
        category_applied_input_types: {
          ...fixture.input.category_applied_input_types,
          sexual: types,
        },
      },
    });
  }
  const extra = moderationFixture();
  extra.input.categories["unknown"] = false;
  invalid.push(extra);
  for (const value of invalid) {
    const result = openAIPhotoSafety(value, true);
    assertEquals(result.disposition, "unavailable");
    assert(!JSON.stringify(result).includes("PRIVATE"));
  }
});

Deno.test("photo adapter removes drafts on denial or unavailable moderation and never retries or fabricates Gemini ratings", async (t) => {
  for (const side of ["input", "output"] as const) {
    await t.step(`${side} denial`, async () => {
      const moderation = moderationFixture();
      moderation[side].flagged = true;
      moderation[side].categories.sexual = true;
      await assertOutcome(moderation, "refusal", "rejected");
      await assertOutcome(moderation, "refusal", "rejected", true);
    });
  }
  await assertOutcome(undefined, "invalid_output", "unavailable");
  await assertOutcome(
    {
      input: { type: "error", message: "PRIVATE_DIAGNOSTIC" },
      output: moderationFixture().output,
    },
    "invalid_output",
    "unavailable",
  );
  async function assertOutcome(
    moderation: unknown,
    kind: string,
    disposition: string,
    malformed = false,
  ) {
    let calls = 0;
    const request = photoRequest();
    const execution = createAIExecution(
      createOpenAIPhotoAdapter("synthetic-photo", () => {
        calls++;
        return Promise.resolve(
          Response.json({
            ...openAIResponseFixture(),
            ...(malformed ? { output: [{ type: "unexpected" }] } : {}),
            moderation,
          }),
        );
      }),
      request,
      openAIPhotoSnapshot(request, 2),
    );
    const result = await execution.invoke();
    assertEquals(calls, 1);
    assertEquals(result.kind, kind);
    assertEquals(result.mediaSafety?.disposition, disposition);
    assertEquals(result.safetyRatings, undefined);
    assert(!("draft" in result));
    assert(!JSON.stringify(result).includes("PRIVATE"));
    if (result.kind === "invalid_output") assertEquals(result.reason, "safety");
  }
});
