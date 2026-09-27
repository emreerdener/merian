import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createAIExecution } from "./execution.ts";
import {
  createOpenAIEvaluationAdapter,
  OPENAI_RESPONSE_LIMIT,
  OPENAI_RESPONSES_URL,
} from "./openai.ts";
import {
  buildOpenAIRequestParameters,
  decodeOpenAIDraft,
  openAIEvaluationSnapshot,
  openAISchemaFromContract,
} from "./openaiRequest.ts";
import {
  type ContractNode,
  merianModelContract,
} from "../identify/contract.ts";
import {
  openAIDraftFixture,
  openAIResponseFixture,
  openAITextFixture,
} from "./testing/openaiFixtures.ts";
import type { AIRequest, AIUsage } from "./contracts.ts";

const credential = "synthetic-evaluation";
Deno.test("OpenAI executes the frozen complete photo/text projection once, with no preparation disclosure", async () => {
  const request = { ...openAITextFixture() };
  request.evidence = [...request.evidence, {
    kind: "image",
    order: 1,
    inputIndex: 0,
    lineage: { kind: "image", sourceIndex: 0 },
    mimeType: "image/png",
    data: "AQID",
  }, {
    kind: "image",
    order: 2,
    inputIndex: 1,
    lineage: { kind: "image", sourceIndex: 1 },
    mimeType: "image/jpeg",
    data: "BAUG",
  }];
  const snapshot = openAIEvaluationSnapshot(request),
    native = buildOpenAIRequestParameters(request, snapshot);
  assert(Object.isFrozen(snapshot) && Object.isFrozen(snapshot.generation));
  assertEquals(native.input[0].content.map((p) => p.type), [
    "input_text",
    "input_image",
    "input_image",
  ]);
  assertEquals(native.store, false);
  assertEquals(native.tools, []);
  assertEquals(native.reasoning, { effort: "low" });
  assert(!("temperature" in native) && !("seed" in native));
  let calls = 0;
  const execution = createAIExecution(
    createOpenAIEvaluationAdapter(credential, (url, init) => {
      calls++;
      assertEquals(url, OPENAI_RESPONSES_URL);
      assertEquals(init?.redirect, "error");
      assert(init?.signal instanceof AbortSignal);
      assertEquals(
        new Headers(init?.headers).get("Authorization"),
        `Bearer ${credential}`,
      );
      assertEquals(
        JSON.parse(String(init?.body)),
        JSON.parse(JSON.stringify(native)),
      );
      return Promise.resolve(Response.json(openAIResponseFixture()));
    }),
    request,
    snapshot,
  );
  assertEquals(calls, 0);
  request.evidence = [];
  const result = await execution.invoke();
  assertEquals(result.kind, "draft");
  assertEquals(result.execution.provider, "openai");
  assertEquals(
    result.usage,
    {
      promptTokens: 100,
      candidateTokens: 30,
      thinkingTokens: 10,
      totalTokens: 140,
      cachedTokens: 20,
      cacheWriteTokens: null,
      toolTokens: 0,
      modalityBreakdown: {},
    } satisfies AIUsage,
  );
  await assertRejects(
    () => execution.invoke(),
    Error,
    "ai_attempt_already_invoked",
  );
  assertEquals(calls, 1);
});
Deno.test("OpenAI rejects whole unsupported observations, compatibility tasks and configuration overrides before dispatch", () => {
  const base = openAITextFixture();
  const unsupported: AIRequest[] = [
    { ...base, capture: { ...base.capture, hasVideo: true } },
    { ...base, capture: { ...base.capture, videoInferenceFrameCount: 1 } },
    {
      ...base,
      evidence: [...base.evidence, {
        kind: "audio",
        order: 1,
        data: "AQID",
        mimeType: "audio/wav",
        inputIndex: 0,
        lineage: null,
      }],
    },
    {
      ...base,
      evidence: [...base.evidence, {
        kind: "image",
        order: 1,
        data: "AQID",
        mimeType: "image/png",
        inputIndex: 0,
        lineage: { kind: "video_frame", clipIndex: 0, frameIndex: 0 },
      }],
    },
    {
      ...base,
      evidence: [{
        kind: "image",
        order: 0,
        data: "AQID",
        mimeType: "image/heic",
        inputIndex: 0,
        lineage: null,
      }],
    },
    { ...base, evidence: [] },
    {
      ...base,
      evidence: [{
        kind: "text",
        order: 0,
        source: "capture_context",
        text: "Only telemetry.",
      }],
    },
    { ...base, variant: "vision_compat" },
  ];
  for (const request of unsupported) {
    assertThrows(
      () => openAIEvaluationSnapshot(request),
      Error,
      "openai_input_unsupported",
    );
  }
  const snapshot = openAIEvaluationSnapshot(base);
  assertThrows(
    () =>
      buildOpenAIRequestParameters(
        base,
        { ...snapshot, model: "other" } as unknown as typeof snapshot,
      ),
    Error,
    "openai_binding_mismatch",
  );
  assertThrows(
    () => createOpenAIEvaluationAdapter(""),
    Error,
    "openai_credential_invalid",
  );
});
Deno.test("OpenAI strict schema is generated from the shared contract and null optionals decode without weakening it", () => {
  function visit(node: ContractNode) {
    const schema = openAISchemaFromContract(node);
    if (node.kind === "object") {
      assertEquals(schema.additionalProperties, false);
      assertEquals(schema.required, Object.keys(node.fields));
      for (const [key, field] of Object.entries(node.fields)) {
        if (!field.required) {
          assertEquals(schema.properties![key].type, [
            field.contract.kind,
            "null",
          ]);
        }
        visit(field.contract);
      }
    } else if (node.kind === "array") visit(node.items);
  }
  visit(merianModelContract);
  const draft = openAIDraftFixture();
  const decoded = decodeOpenAIDraft(draft);
  assertEquals(decoded.pet_identification, null);
  assertEquals(decoded.confidence_score, .99);
  delete draft.common_name; // Optional domain field is still REQUIRED by strict provider schema.
  assertThrows(() => decodeOpenAIDraft(draft));
  assertThrows(() =>
    decodeOpenAIDraft({ ...openAIDraftFixture(), extra: "untrusted" })
  );
  assertThrows(() =>
    decodeOpenAIDraft({ ...openAIDraftFixture(), confidence_score: 2 })
  );
});
Deno.test("OpenAI distinguishes refusal, incomplete output and uncertain execution without retry or diagnostics", async () => {
  const response = openAIResponseFixture();
  const cases: [Response | Error, string][] = [
    [
      Response.json({
        ...response,
        output: [{
          type: "message",
          role: "assistant",
          status: "completed",
          content: [{ type: "refusal", refusal: "PRIVATE_REFUSAL" }],
        }],
      }),
      "refusal",
    ],
    [
      Response.json({
        ...response,
        status: "incomplete",
        incomplete_details: { reason: "content_filter" },
      }),
      "refusal",
    ],
    [
      Response.json({
        ...response,
        status: "incomplete",
        incomplete_details: { reason: "max_output_tokens" },
      }),
      "invalid_output",
    ],
    [
      Response.json({ ...response, output: [{ type: "web_search_call" }] }),
      "invalid_output",
    ],
    [
      Response.json({
        ...response,
        output: [response.output[0], response.output[0]],
      }),
      "invalid_output",
    ],
    [
      Response.json({
        ...response,
        output: [{
          ...response.output[0],
          content: [{ type: "output_text", text: "PRIVATE_INVALID_JSON" }],
        }],
      }),
      "invalid_output",
    ],
    [
      Response.json({ ...response, status: "in_progress" }),
      "unknown_execution",
    ],
    [new Response("PRIVATE_ERROR", { status: 429 }), "operational_failure"],
    [new Response("PRIVATE_ERROR", { status: 503 }), "unknown_execution"],
    [new Error("PRIVATE_TRANSPORT"), "unknown_execution"],
    [new Response("{"), "unknown_execution"],
    [new Response("x".repeat(OPENAI_RESPONSE_LIMIT + 1)), "unknown_execution"],
    [
      new Response("x", {
        headers: { "Content-Length": String(OPENAI_RESPONSE_LIMIT + 1) },
      }),
      "unknown_execution",
    ],
  ];
  for (const [reply, kind] of cases) {
    let calls = 0;
    const request = openAITextFixture();
    const result = await createAIExecution(
      createOpenAIEvaluationAdapter(credential, () => {
        calls++;
        if (reply instanceof Error) return Promise.reject(reply);
        return Promise.resolve(reply);
      }),
      request,
      openAIEvaluationSnapshot(request),
    ).invoke();
    assertEquals(result.kind, kind);
    assertEquals(calls, 1);
    assert(!JSON.stringify(result).includes("PRIVATE_"));
  }
});
Deno.test("OpenAI missing/contradictory reasoning usage stays unknown and model metadata is bounded", async () => {
  for (const reasoning of [undefined, -1, 41]) {
    const request = openAITextFixture();
    const raw = openAIResponseFixture();
    const result = await createAIExecution(
      createOpenAIEvaluationAdapter(credential, () =>
        Promise.resolve(
          Response.json({
            ...raw,
            model: "PRIVATE_MODEL",
            usage: {
              ...raw.usage,
              output_tokens_details: { reasoning_tokens: reasoning },
            },
          }),
        )),
      request,
      openAIEvaluationSnapshot(request),
    ).invoke();
    assertEquals(result.usage?.candidateTokens, null);
    assertEquals(result.returnedModel, null);
  }
});

Deno.test("OpenAI cache-write usage is bounded and missing or contradictory counters stay unknown", async () => {
  for (const writes of [undefined, null, -1, 1.5, "30", 81, 30, 0]) {
    const request = openAITextFixture(), raw = openAIResponseFixture();
    const result = await createAIExecution(
      createOpenAIEvaluationAdapter(
        credential,
        () =>
          Promise.resolve(Response.json({
            ...raw,
            usage: {
              ...raw.usage,
              input_tokens_details: {
                cached_tokens: 20,
                cache_write_tokens: writes,
              },
            },
          })),
      ),
      request,
      openAIEvaluationSnapshot(request),
    ).invoke();
    assertEquals(
      result.usage?.cacheWriteTokens,
      writes === 30 || writes === 0 ? writes : null,
    );
    assertEquals(result.usage?.candidateTokens, 30);
    assertEquals(result.usage?.thinkingTokens, 10);
  }
});
