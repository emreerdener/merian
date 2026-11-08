import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  decodeProtectedChatProvider,
  prepareProtectedChatProvider,
} from "../insight-chat/protectedProvider.ts";
const envelope = () => ({
  modelVersion: "gemini-2.5-flash",
  candidates: [{
    finishReason: "STOP",
    content: {
      role: "model",
      parts: [{
        text: JSON.stringify({
          answer: "Synthetic answer",
          is_refusal: false,
          refusal_reason: null,
        }),
      }],
    },
  }],
  usageMetadata: {
    promptTokenCount: 10,
    candidatesTokenCount: 5,
    totalTokenCount: 15,
    promptTokensDetails: [{ modality: "TEXT", tokenCount: 10 }],
  },
});
Deno.test("protected provider closes answer and exact granted-model accounting", () => {
  const parsed = decodeProtectedChatProvider(envelope());
  assertEquals(parsed.usage?.thinking_tokens, null);
  assertEquals(parsed.usage?.modality_breakdown.prompt, { text: 10 });
  for (
    const raw of [
      { ...envelope(), modelVersion: "different" },
      { ...envelope(), candidates: [] },
      {
        ...envelope(),
        candidates: [{
          ...envelope().candidates[0],
          safetyRatings: [{ blocked: true }],
        }],
      },
      { ...envelope(), usageMetadata: { promptTokenCount: -1 } },
      {
        ...envelope(),
        usageMetadata: {
          promptTokensDetails: [{ modality: "OTHER", tokenCount: 1 }],
        },
      },
    ]
  ) assertThrows(() => decodeProtectedChatProvider(raw));
  assertEquals(
    decodeProtectedChatProvider({ ...envelope(), usageMetadata: undefined })
      .usage,
    null,
  );
});
Deno.test("protected provider posts one fixed no-redirect request and cannot repeat", async () => {
  let calls = 0;
  const invoke = prepareProtectedChatProvider(
    "system",
    "question",
    "gemini-2.5-flash",
    {
      apiKey: () => "synthetic-key",
      fetcher: (url, init) => {
        calls++;
        assertEquals(
          String(url),
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
        );
        assertEquals(init?.redirect, "error");
        assert(init?.signal);
        const body = JSON.parse(String(init?.body));
        assertEquals(body.systemInstruction, {
          role: "user",
          parts: [{ text: "system" }],
        });
        assertEquals(body.generationConfig.maxOutputTokens, 700);
        return Promise.resolve(Response.json(envelope()));
      },
    },
  );
  assertEquals(
    (await invoke(new AbortController().signal)).answer,
    "Synthetic answer",
  );
  await assertRejects(() => invoke(new AbortController().signal));
  assertEquals(calls, 1);
});
Deno.test("provider failures never retry and never expose upstream details", async () => {
  for (const status of [429, 503, 200]) {
    let calls = 0;
    const invoke = prepareProtectedChatProvider(
      "system",
      "question",
      "gemini-2.5-flash",
      {
        apiKey: () => "synthetic-key",
        fetcher: () => {
          calls++;
          return Promise.resolve(
            new Response("private diagnostic", {
              status,
              headers: { "content-type": "application/json" },
            }),
          );
        },
      },
    );
    const error = await assertRejects(() =>
      invoke(new AbortController().signal)
    );
    assert(error instanceof Error);
    assertEquals(error.message, "field_chat_execution_held");
    assertEquals(calls, 1);
  }
});
Deno.test("provider abort reaches stalled headers and body", async () => {
  for (const phase of ["headers", "body"]) {
    const controller = new AbortController();
    let cancelled = false;
    const invoke = prepareProtectedChatProvider(
      "system",
      "question",
      "gemini-2.5-flash",
      {
        apiKey: () => "synthetic-key",
        fetcher: (_url, init) => {
          assert(init?.signal);
          if (phase === "headers") {
            return new Promise((_resolve, reject) => {
              init.signal!.addEventListener("abort", () => {
                cancelled = true;
                reject(new Error("aborted"));
              }, { once: true });
              queueMicrotask(() => controller.abort());
            });
          }
          return Promise.resolve(
            new Response(
              new ReadableStream({
                start() {
                  setTimeout(() => controller.abort(), 1);
                },
                cancel() {
                  cancelled = true;
                },
              }),
              { headers: { "content-type": "application/json" } },
            ),
          );
        },
      },
    );
    await assertRejects(() => invoke(controller.signal));
    assert(cancelled);
  }
});
Deno.test("provider rejects oversized declared and streaming bodies", async () => {
  for (const declared of [false, true]) {
    const invoke = prepareProtectedChatProvider(
      "system",
      "question",
      "gemini-2.5-flash",
      {
        apiKey: () => "synthetic-key",
        fetcher: () =>
          Promise.resolve(
            new Response("x".repeat(32769), {
              headers: {
                "content-type": "application/json",
                ...(declared ? { "content-length": "32769" } : {}),
              },
            }),
          ),
      },
    );
    await assertRejects(() => invoke(new AbortController().signal));
  }
});
