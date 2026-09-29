import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createAIExecution } from "./execution.ts";
import {
  createOpenAIPhotoModelEvaluationAdapter,
  createOpenAISolPrimaryEvaluationAdapter,
  OPENAI_RESPONSES_URL,
} from "./openai.ts";
import { openAIPhotoModelSnapshot } from "./openaiPhotoModels.ts";
import {
  buildSolPhotoPrimaryRequest,
  solPhotoPrimarySnapshot,
} from "./openaiSolPrimary.ts";
import { solPrimaryDraftFixture } from "./testing/openaiSolPrimaryFixtures.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
} from "./testing/openaiFixtures.ts";

Deno.test("primary transport preserves all five explicit states without admitting them to the legacy decoder", async () => {
  for (
    const resolution of [
      "species",
      "genus",
      "family",
      "unresolved_biological",
      "non_biological",
    ] as const
  ) {
    const request = openAIPhotoRequestFixture();
    const draft = solPrimaryDraftFixture(resolution);
    const response = {
      ...openAIResponseFixture(),
      model: "gpt-6-sol",
      service_tier: "default",
      moderation: openAIPhotoModerationFixture(),
      output: [{
        type: "message",
        role: "assistant",
        status: "completed",
        content: [{ type: "output_text", text: JSON.stringify(draft) }],
      }],
    };
    const snapshot = solPhotoPrimarySnapshot(request);
    const body = buildSolPhotoPrimaryRequest(request, snapshot);
    let calls = 0;
    const adapter = createOpenAISolPrimaryEvaluationAdapter(
      "synthetic-key",
      (url, init) => {
        calls++;
        assertEquals(url, OPENAI_RESPONSES_URL);
        assertEquals(init?.redirect, "error");
        assertEquals(
          JSON.parse(String(init?.body)),
          JSON.parse(JSON.stringify(body)),
        );
        return Promise.resolve(Response.json(response));
      },
    );
    const execution = createAIExecution(adapter, request, snapshot);
    assertEquals(calls, 0);
    // Prepared transport holds serialized evidence rather than the caller's mutable objects.
    Reflect.set(request.evidence, "length", 0);
    const outcome = await execution.invoke();
    assertEquals(outcome.kind, "draft");
    if (outcome.kind === "draft") assertEquals(outcome.draft, draft);
    assertEquals(outcome.usage?.outputTokens, 40);
    assertEquals(outcome.usage?.thinkingTokens, 10);
    await assertRejects(
      () => execution.invoke(),
      Error,
      "ai_attempt_already_invoked",
    );
    assertEquals(calls, 1);
    const legacyRequest = openAIPhotoRequestFixture();
    const legacy = createAIExecution(
      createOpenAIPhotoModelEvaluationAdapter(
        "synthetic-key",
        () => Promise.resolve(Response.json(response)),
      ),
      legacyRequest,
      openAIPhotoModelSnapshot(legacyRequest, "openai_photo_sol_low_v1"),
    );
    assertEquals((await legacy.invoke()).kind, "invalid_output");
  }
});

Deno.test("primary transport strips drafts on malformed rank, model, safety, tool and execution failures", async () => {
  for (
    const failure of [
      "missing_resolution",
      "rank_conflict",
      "wrong_model",
      "version_suffix",
      "missing_input",
      "missing_output",
      "flagged",
      "incomplete",
      "tool_output",
      "http_401",
      "http_500",
    ] as const
  ) {
    const request = openAIPhotoRequestFixture();
    const draft = solPrimaryDraftFixture("genus");
    if (failure === "missing_resolution") delete draft.resolution;
    if (failure === "rank_conflict") draft.candidates = [];
    const response = {
      ...openAIResponseFixture(),
      model: "gpt-6-sol",
      service_tier: "default",
      moderation: openAIPhotoModerationFixture(),
      output: [{
        type: "message",
        role: "assistant",
        status: "completed",
        content: [{ type: "output_text", text: JSON.stringify(draft) }],
      }],
    };
    if (failure === "wrong_model") response.model = "gpt-6-luna";
    if (failure === "version_suffix") response.model += "-unknown-snapshot";
    if (failure === "missing_input") {
      Reflect.deleteProperty(response.moderation, "input");
    }
    if (failure === "missing_output") {
      Reflect.deleteProperty(response.moderation, "output");
    }
    if (failure === "flagged") {
      response.moderation.input.flagged = true;
      response.moderation.input.categories.sexual = true;
      response.output[0].content[0].text = "not-json";
    }
    if (failure === "incomplete") response.status = "incomplete";
    if (failure === "tool_output") response.output[0].type = "function_call";
    let calls = 0;
    const execution = createAIExecution(
      createOpenAISolPrimaryEvaluationAdapter("synthetic-key", () => {
        calls++;
        return Promise.resolve(
          failure.startsWith("http_")
            ? new Response(null, { status: failure === "http_401" ? 401 : 500 })
            : Response.json(response),
        );
      }),
      request,
      solPhotoPrimarySnapshot(request),
    );
    const outcome = await execution.invoke();
    assertEquals(
      outcome.kind,
      failure === "flagged"
        ? "refusal"
        : failure === "http_401"
        ? "operational_failure"
        : failure === "http_500"
        ? "unknown_execution"
        : "invalid_output",
    );
    assertEquals("draft" in outcome, false);
    assertEquals(calls, 1);
  }
});

Deno.test("primary transport rejects snapshot substitution before any dispatch", () => {
  const request = openAIPhotoRequestFixture(),
    snapshot = solPhotoPrimarySnapshot(request);
  let calls = 0;
  const adapter = createOpenAISolPrimaryEvaluationAdapter(
    "synthetic-key",
    () => {
      calls++;
      throw new Error("unexpected_transport");
    },
  );
  for (
    const change of [
      { model: "gpt-6-luna" },
      { profile: "openai_photo_sol_low_v1" },
      { binding: "openai_photo_v1" },
      { contextKind: "user_request" },
      { generation: { ...snapshot.generation, maxOutputTokens: 16384 } },
      { timeoutMs: 180000 },
    ]
  ) {
    assertThrows(() =>
      adapter.prepare(request, { ...snapshot, ...change } as typeof snapshot)
    );
  }
  assertEquals(calls, 0);
});
