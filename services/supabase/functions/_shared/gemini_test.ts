import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { ApiError, MediaModality } from "@google/genai";
import {
  _genAI,
  createFlashModel,
  GEMINI_REQUEST_TIMEOUT_MS,
} from "./gemini.ts";
import {
  buildFieldChatReplyRequest,
  extractFieldChatReplyJson,
} from "./fieldChatReply.ts";
import { getMerianResponseSchema } from "./identify/schema.ts";

// Exercise the installed SDK, rather than mocking models.generateContent. All
// transport is intercepted; no provider credentials or user content are used.
Deno.test("Gemini SDK preserves Merian's provider boundary", async (t) => {
  const environment = [
    "GEMINI_PAID_API_KEY",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "GOOGLE_GENAI_USE_ENTERPRISE",
    "GOOGLE_GEMINI_BASE_URL",
  ];
  const savedEnvironment = new Map(
    environment.map((key) => [key, Deno.env.get(key)]),
  );
  const originalFetch = globalThis.fetch;
  const originalTimeout = globalThis.setTimeout;
  const timers: ReturnType<typeof setTimeout>[] = [];
  const deadlines: number[] = [];
  let requests = 0;
  let inspect: (body: Record<string, unknown>) => void = () => {};
  let respond: (signal: AbortSignal) => Promise<Response> = () =>
    Promise.resolve(Response.json({
      candidates: [{
        content: {
          role: "model",
          parts: [{
            text:
              '{"answer":"Synthetic answer","is_refusal":false,"refusal_reason":null}',
          }],
        },
        finishReason: "STOP",
      }],
    }));
  const request = buildFieldChatReplyRequest(
    "Synthetic system",
    "Synthetic question",
    "gemini-2.5-flash",
  );

  async function step(name: string, run: () => void | Promise<void>) {
    await t.step(name, async () => {
      try {
        await run();
      } finally {
        for (const timer of timers.splice(0)) clearTimeout(timer);
      }
    });
  }

  try {
    for (const key of environment) Deno.env.delete(key);
    globalThis.fetch = (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      assertEquals(url.origin, "https://generativelanguage.googleapis.com");
      assert(
        /^\/v1beta\/models\/gemini-2\.5-(flash|pro):generateContent$/.test(
          url.pathname,
        ),
      );
      assertEquals(url.search, "");
      assertEquals(init?.method, "POST");
      assertEquals(
        new Headers(init?.headers).get("x-goog-api-key"),
        "synthetic-test-key",
      );
      assert(init?.signal instanceof AbortSignal);
      assertEquals(typeof init.body, "string");
      requests++;
      inspect(JSON.parse(init.body as string));
      return respond(init.signal);
    };
    // Record the real configured deadline. Use a short clock only for the hung
    // transport step; cleanup also releases SDK timers retained after responses.
    globalThis.setTimeout = ((
      handler: Parameters<typeof setTimeout>[0],
      timeout?: number,
      ...args: unknown[]
    ) => {
      if (timeout === GEMINI_REQUEST_TIMEOUT_MS) deadlines.push(timeout);
      const timer = originalTimeout(handler, timeout, ...args);
      timers.push(timer);
      return timer;
    }) as typeof setTimeout;

    await step("missing paid key fails closed before transport", () => {
      assertThrows(
        () => _genAI.models,
        Error,
        "GEMINI_PAID_API_KEY is not configured",
      );
      assertEquals(requests, 0);
      Deno.env.set("GEMINI_PAID_API_KEY", "synthetic-test-key");
    });

    await step(
      "Field Chat serializes its schema and decodes JSON text",
      async () => {
        inspect = (body) => {
          assertEquals(body.contents, request.contents);
          assertEquals(body.systemInstruction, {
            role: "user",
            parts: [{ text: "Synthetic system" }],
          });
          const config = body.generationConfig as Record<string, unknown>;
          assertEquals(config.responseMimeType, "application/json");
          assertEquals(config.thinkingConfig, { thinkingBudget: 0 });
          assertEquals(config.maxOutputTokens, 700);
          assertEquals(config.responseSchema, request.config?.responseSchema);
        };
        const result = await _genAI.models.generateContent(request);
        assertEquals(extractFieldChatReplyJson(result.text ?? ""), {
          answer: "Synthetic answer",
          is_refusal: false,
          refusal_reason: null,
        });
        assertEquals(result.candidates?.[0].finishReason, "STOP");
      },
    );

    await step(
      "multimodal Pro retains schema, thinking, safety and token usage",
      async () => {
        const schema = getMerianResponseSchema(0);
        const parts = [{ text: "Synthetic observation" }, {
          inlineData: { mimeType: "image/webp", data: "AA==" },
        }, { inlineData: { mimeType: "audio/wav", data: "AA==" } }];
        inspect = (body) => {
          assertEquals(body.contents, [{ role: "user", parts }]);
          const config = body.generationConfig as Record<string, unknown>;
          assertEquals(config.responseSchema, schema);
          assertEquals(config.thinkingConfig, { thinkingBudget: 5000 });
          assertEquals(config.maxOutputTokens, 8192);
          assertEquals(config.seed, 42);
        };
        respond = () =>
          Promise.resolve(Response.json({
            candidates: [{
              content: {
                role: "model",
                parts: [{ text: "private synthetic thought", thought: true }, {
                  text: '{"is_biological_subject":false}',
                }],
              },
              finishReason: "STOP",
              safetyRatings: [{
                category: "HARM_CATEGORY_DANGEROUS_CONTENT",
                probability: "LOW",
              }],
            }],
            usageMetadata: {
              promptTokenCount: 12,
              candidatesTokenCount: 8,
              thoughtsTokenCount: 5,
              totalTokenCount: 25,
              promptTokensDetails: [{
                modality: MediaModality.IMAGE,
                tokenCount: 10,
              }],
            },
          }));
        const result = await _genAI.models.generateContent({
          model: "gemini-2.5-pro",
          contents: [{ role: "user", parts }],
          config: {
            responseMimeType: "application/json",
            responseSchema: schema,
            maxOutputTokens: 8192,
            seed: 42,
            thinkingConfig: { thinkingBudget: 5000 },
          },
        });
        assertEquals(result.text, '{"is_biological_subject":false}');
        assertEquals(
          result.candidates?.[0].safetyRatings?.[0].probability,
          "LOW",
        );
        assertEquals(result.usageMetadata?.thoughtsTokenCount, 5);
        assertEquals(result.usageMetadata?.totalTokenCount, 25);
        assertEquals(result.usageMetadata?.promptTokensDetails, [{
          modality: MediaModality.IMAGE,
          tokenCount: 10,
        }]);
      },
    );

    await step(
      "Flash wrapper retains zero thinking and caller configuration",
      async () => {
        inspect = (body) => {
          const config = body.generationConfig as Record<string, unknown>;
          assertEquals(config.thinkingConfig, { thinkingBudget: 0 });
          assertEquals(config.maxOutputTokens, 256);
          assertEquals(config.temperature, 0.3);
        };
        await createFlashModel("Synthetic system", 256).generateContent({
          contents: request.contents as {
            role: string;
            parts: { text: string }[];
          }[],
          config: { temperature: 0.3 },
        });
      },
    );

    await step(
      "safety refusal stays distinguishable from empty output",
      async () => {
        inspect = () => {};
        respond = () =>
          Promise.resolve(
            Response.json({
              candidates: [{
                finishReason: "SAFETY",
                safetyRatings: [{
                  category: "HARM_CATEGORY_DANGEROUS_CONTENT",
                  probability: "HIGH",
                }],
              }],
            }),
          );
        const result = await _genAI.models.generateContent(request);
        assertEquals(result.text, undefined);
        assertEquals(result.candidates?.[0].finishReason, "SAFETY");
        assertEquals(
          result.candidates?.[0].safetyRatings?.[0].probability,
          "HIGH",
        );
      },
    );

    await step("provider errors do not trigger hidden retries", async () => {
      for (const status of [400, 429, 503]) {
        respond = () =>
          Promise.resolve(
            Response.json({
              error: {
                code: status,
                message: "Synthetic failure",
                status: "UNAVAILABLE",
              },
            }, { status }),
          );
        const before = requests;
        const error = await assertRejects(
          () => _genAI.models.generateContent(request),
          ApiError,
        );
        assertEquals(error.status, status);
        assertEquals(requests - before, 1);
      }
    });

    await step(
      "configured deadline aborts a hung transport without retry",
      async () => {
        globalThis.setTimeout = ((
          handler: Parameters<typeof setTimeout>[0],
          timeout?: number,
          ...args: unknown[]
        ) => {
          assertEquals(timeout, GEMINI_REQUEST_TIMEOUT_MS);
          deadlines.push(GEMINI_REQUEST_TIMEOUT_MS);
          const timer = originalTimeout(handler, 5, ...args);
          timers.push(timer);
          return timer;
        }) as typeof setTimeout;
        respond = (signal) =>
          new Promise((_resolve, reject) => {
            signal.addEventListener(
              "abort",
              () => reject(new DOMException("Synthetic abort", "AbortError")),
              { once: true },
            );
          });
        const before = requests;
        // The SDK unrefs its timeout. Keep the test event loop alive while
        // waiting for the simulated deadline, as an HTTP server would.
        const keepAlive = originalTimeout(() => {}, 1000);
        try {
          await assertRejects(() => _genAI.models.generateContent(request));
        } finally {
          clearTimeout(keepAlive);
        }
        assertEquals(requests - before, 1);
        assertEquals(deadlines.length, requests);
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
    globalThis.setTimeout = originalTimeout;
    for (const timer of timers) clearTimeout(timer);
    for (const [key, value] of savedEnvironment) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
