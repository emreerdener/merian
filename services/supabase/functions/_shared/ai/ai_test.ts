import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { AIRequest, UserRequestAuthority } from "./contracts.ts";
import { prepareAIExecution } from "./production.ts";
import { resolveAIClaim } from "./registry.ts";
import { buildGeminiRequest } from "./gemini.ts";
import { buildVisionAIRequest } from "../../identify/provider.ts";
import { buildAudioAIRequest } from "../../audio-spec/provider.ts";
import { BIOACOUSTIC_SYSTEM_INSTRUCTION as AUDIO_COMPAT_INSTRUCTION } from "../../audio-spec/instructions.ts";
import { buildDescribeAIRequest } from "../../identify-describe/provider.ts";
import { buildMultimodalAIRequest } from "../../identify-multimodal/provider.ts";
import { buildVisualMediaPrompt } from "../../identify-multimodal/capturedMedia.ts";
import {
  BIOACOUSTIC_SYSTEM_INSTRUCTION,
  DESCRIBE_SYSTEM_INSTRUCTION,
  MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION,
} from "../../identify-multimodal/instructions.ts";
import { buildContextText } from "../identify/context.ts";
import {
  getMerianAudioResponseSchema,
  getMerianResponseSchema,
  getSystemInstruction,
} from "../identify/schema.ts";
import { diagnosticTriggerForTier } from "../identify/thresholds.ts";
import { isProviderSafetyRejected } from "../identify/moderation.ts";
import {
  getDescribeResponseSchema,
  getDescribeSystemInstruction,
} from "../../identify-describe/schema.ts";

const request = buildDescribeAIRequest("Synthetic striped organism.", {
  safeGpsLat: null,
  safeGpsLon: null,
  deviceLocale: "en-US",
  currentMonth: 9,
});

function authority(model = "gemini-2.5-flash"): UserRequestAuthority {
  return {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model,
      tier: { effective_tier: model === "gemini-2.5-pro" ? "pro" : "free" },
    },
  };
}

Deno.test("AI registry rejects unsupported authority/model/evidence before SDK access", () => {
  assertThrows(
    () => prepareAIExecution(request, authority("other-model")),
    Error,
    "ai_model_not_enabled",
  );
  assertThrows(
    () =>
      prepareAIExecution(request, {
        ...authority(),
        operation: "scan_audio_identification",
      }),
    Error,
    "ai_authority_mismatch",
  );
  assertThrows(
    () =>
      prepareAIExecution(request, {
        kind: "service_job",
        task: "species_overview",
        purpose: "public_species_facts",
        jobId: "synthetic-job",
        attemptCount: 1,
        maxAttempts: 5,
        model: "gemini-2.5-flash",
      }),
    Error,
    "ai_authority_mismatch",
  );
  assertThrows(
    () =>
      prepareAIExecution({
        ...request,
        evidence: [{ kind: "image" }],
      } as unknown as AIRequest, authority()),
    Error,
    "ai_unsupported_input",
  );
  assertThrows(
    () =>
      resolveAIClaim(request, {
        ...authority(),
        permission: "other-processor",
      } as unknown as UserRequestAuthority),
    Error,
    "ai_authority_mismatch",
  );
});

function multimodalCases(): Array<
  Parameters<typeof buildMultimodalAIRequest>[0] & { label: string }
> {
  const base: Parameters<typeof buildMultimodalAIRequest>[0] = {
    observationEvidenceTexts: [
      "Synthetic context one",
      "Synthetic context two",
    ],
    visualMediaItems: [],
    imageBase64s: [],
    imageMimeType: "image/webp",
    processedAudios: [],
    audioMediaItems: [],
    processedAudioInputIndexes: [],
    hasVideoAudio: false,
    capture: {
      hasVideo: false,
      videoClipCount: 0,
      declaredVideoFrameCount: 0,
      videoInferenceFrameCount: 0,
    },
    telemetry: { safeGpsLat: null, safeGpsLon: null, deviceLocale: "en-US" },
  };
  const images = {
    ...base,
    imageBase64s: ["AQ==", "Ag=="],
    visualMediaItems: [
      { kind: "image" as const, sourceIndex: 1 },
      { kind: "image" as const, sourceIndex: 0 },
    ],
  };
  const audio = {
    ...base,
    processedAudios: ["Aw=="],
    audioMediaItems: [{ kind: "audio" as const, sourceIndex: 0 }],
    processedAudioInputIndexes: [0],
  };
  const frames = {
    ...base,
    imageBase64s: ["AQ==", "Ag==", "Aw==", "BA==", "BQ=="],
    visualMediaItems: Array.from(
      { length: 5 },
      (_, frameIndex) => ({
        kind: "video_frame" as const,
        clipIndex: 0,
        frameIndex,
      }),
    ),
    capture: {
      hasVideo: true,
      videoClipCount: 1,
      declaredVideoFrameCount: 5,
      videoInferenceFrameCount: 5,
    },
  };
  const withAudio = {
    ...frames,
    processedAudios: ["Bg=="],
    audioMediaItems: [{ kind: "video_audio" as const, clipIndex: 0 }],
    processedAudioInputIndexes: [2],
    hasVideoAudio: true,
  };
  return [
    { ...base, label: "primary description" },
    {
      ...images,
      imageBase64s: ["AQ=="],
      visualMediaItems: [{ kind: "image", sourceIndex: 0 }],
      label: "one still",
    },
    { ...images, label: "ordered stills" },
    { ...audio, label: "standalone audio" },
    {
      ...images,
      processedAudios: audio.processedAudios,
      audioMediaItems: audio.audioMediaItems,
      processedAudioInputIndexes: audio.processedAudioInputIndexes,
      label: "images and audio",
    },
    { ...frames, label: "five snapshots" },
    {
      ...frames,
      imageBase64s: frames.imageBase64s.slice(0, 2),
      visualMediaItems: frames.visualMediaItems.slice(0, 2),
      capture: { ...frames.capture, videoInferenceFrameCount: 2 },
      label: "accepted partial snapshots",
    },
    { ...withAudio, label: "snapshots with companion audio" },
    {
      ...withAudio,
      imageBase64s: ["BA==", "Ag==", "AQ=="],
      visualMediaItems: [
        { kind: "video_frame", clipIndex: 1, frameIndex: 2 },
        { kind: "image", sourceIndex: 0 },
        { kind: "video_frame", clipIndex: 0, frameIndex: 1 },
      ],
      capture: {
        hasVideo: true,
        videoClipCount: 2,
        declaredVideoFrameCount: 10,
        videoInferenceFrameCount: 2,
      },
      label: "multiple sources retain positional lineage",
    },
    { ...frames, visualMediaItems: [], label: "legacy unknown frame lineage" },
  ];
}

Deno.test("multimodal binding requires admitted tier and rejects native video evidence", () => {
  const input = buildMultimodalAIRequest(multimodalCases()[0]);
  const admitted = authority();
  assertThrows(
    () =>
      resolveAIClaim(input, {
        ...admitted,
        reservation: { ...admitted.reservation, tier: undefined },
      }),
    Error,
    "ai_authority_mismatch",
  );
  assertThrows(
    () =>
      resolveAIClaim(
        {
          ...input,
          evidence: [{
            kind: "video",
            order: 0,
            data: "AQ==",
            mimeType: "video/mp4",
          }],
        } as unknown as AIRequest,
        admitted,
      ),
    Error,
    "ai_unsupported_input",
  );
  // Entitlement is not inferred from a model string. Preserve the original
  // caller's independent authority for generation settings and confidence.
  assertEquals(
    resolveAIClaim(input, {
      ...admitted,
      reservation: { ...admitted.reservation, tier: { effective_tier: "pro" } },
    }).generation.thinkingBudget,
    5000,
  );
});

Deno.test("compatibility bindings keep operation and evidence authority distinct", () => {
  const telemetry = { safeGpsLat: null, safeGpsLon: null };
  const visual = buildVisionAIRequest({ imageBase64s: ["AQ=="], telemetry });
  const audio = buildAudioAIRequest("Ag==", telemetry);
  const audioAuthority = {
    ...authority(),
    operation: "scan_audio_identification",
  };
  assertEquals(
    resolveAIClaim(audio, audioAuthority).operation,
    "scan_audio_identification",
  );
  assertThrows(
    () => resolveAIClaim(audio, authority()),
    Error,
    "ai_authority_mismatch",
  );
  assertThrows(
    () => resolveAIClaim(visual, audioAuthority),
    Error,
    "ai_authority_mismatch",
  );
  assertThrows(
    () => resolveAIClaim({ ...visual, evidence: audio.evidence }, authority()),
    Error,
    "ai_unsupported_input",
  );
  assertThrows(
    () =>
      resolveAIClaim({ ...audio, evidence: visual.evidence }, audioAuthority),
    Error,
    "ai_unsupported_input",
  );
});

Deno.test("AI snapshots preserve admitted policy and complete describe request profiles", () => {
  for (
    const [model, maxOutputTokens, thinkingBudget] of [
      ["gemini-2.5-flash", 2048, 1024],
      ["gemini-2.5-pro", 4096, 3000],
    ] as const
  ) {
    const admitted = authority(model);
    const snapshot = resolveAIClaim(request, admitted);
    assert(Object.isFrozen(snapshot));
    assert(Object.isFrozen(snapshot.generation));
    assertEquals(buildGeminiRequest(request, snapshot), {
      model,
      contents: [{
        role: "user",
        parts: [{
          text:
            "Context: Locale:en-US, Month:9.\n\nObservation Description:\nSynthetic striped organism.",
        }],
      }],
      config: {
        systemInstruction: getDescribeSystemInstruction(),
        temperature: 0.15,
        seed: 42,
        topK: 40,
        maxOutputTokens,
        thinkingConfig: { thinkingBudget },
        responseMimeType: "application/json",
        responseSchema: getDescribeResponseSchema(),
      },
    });
    const nextAdmission = {
      ...admitted,
      reservation: {
        ...admitted.reservation,
        model: "gemini-2.5-pro",
        policyVersion: 2,
        attemptCount: 2,
      },
    };
    assertEquals(resolveAIClaim(request, nextAdmission).policyVersion, 2);
    assertEquals(snapshot.policyVersion, 1);
    assertEquals(snapshot.model, model);
  }
});

// Exercise the installed SDK and production composition with intercepted HTTP.
// This test runs without network permission; no alternate provider is enabled.
Deno.test("AI Gemini adapter preserves dispatch, usage, finish and timeout behavior", async (t) => {
  const names = [
    "GEMINI_PAID_API_KEY",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "GOOGLE_GENAI_USE_ENTERPRISE",
    "GOOGLE_GEMINI_BASE_URL",
  ];
  const environment = new Map(names.map((name) => [name, Deno.env.get(name)]));
  const originalFetch = globalThis.fetch;
  const originalTimeout = globalThis.setTimeout;
  const timers: ReturnType<typeof setTimeout>[] = [];
  let calls = 0;
  let timeouts = 0;
  let status = 200;
  let response: Record<string, unknown> = {};
  let inspect: (url: URL, body: Record<string, unknown>) => void = () => {};
  let hang = false;
  let inspectionError: unknown;
  try {
    names.forEach((name) => Deno.env.delete(name));
    assertThrows(
      () => prepareAIExecution(request, authority()),
      Error,
      "GEMINI_PAID_API_KEY",
    );
    Deno.env.set("GEMINI_PAID_API_KEY", "synthetic-test-key");
    globalThis.setTimeout = ((
      handler: Parameters<typeof setTimeout>[0],
      timeout?: number,
      ...args: unknown[]
    ) => {
      if (timeout === 90000) timeouts++;
      const timer = originalTimeout(
        handler,
        hang && timeout === 90000 ? 1 : timeout,
        ...args,
      );
      timers.push(timer);
      return timer;
    }) as typeof setTimeout;
    globalThis.fetch = (input, init) => {
      calls++;
      const url = new URL(input instanceof Request ? input.url : String(input));
      assertEquals(url.origin, "https://generativelanguage.googleapis.com");
      assertEquals(init?.method, "POST");
      assert(init?.signal instanceof AbortSignal);
      try {
        inspect(url, JSON.parse(init.body as string));
      } catch (error) {
        inspectionError = error;
      }
      if (hang) {
        return new Promise((_resolve, reject) => {
          init.signal!.addEventListener(
            "abort",
            () => reject(new DOMException("Synthetic timeout", "AbortError")),
            {
              once: true,
            },
          );
        });
      }
      return Promise.resolve(Response.json(response, { status }));
    };
    const step = async (name: string, run: () => Promise<void>) => {
      await t.step(name, async () => {
        const before = calls;
        inspectionError = undefined;
        try {
          await run();
          if (inspectionError) throw inspectionError;
          assertEquals(calls - before, 1);
        } finally {
          timers.splice(0).forEach(clearTimeout);
        }
      });
    };
    for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
      await step(
        `${model} sends one exact text request and normalizes usage`,
        async () => {
          inspect = (url, body) => {
            assertEquals(
              url.pathname,
              `/v1beta/models/${model}:generateContent`,
            );
            const expected = buildGeminiRequest(
              request,
              resolveAIClaim(request, authority(model)),
            );
            const { systemInstruction, ...generationConfig } = expected.config!;
            assertEquals(body.contents, expected.contents);
            assertEquals(body.systemInstruction, {
              role: "user",
              parts: [{ text: systemInstruction }],
            });
            assertEquals(body.generationConfig, generationConfig);
          };
          response = {
            candidates: [{
              content: {
                parts: [{ text: '```json\n{"synthetic":true}\n```' }],
              },
              finishReason: "STOP",
            }],
            modelVersion: model,
            usageMetadata: {
              promptTokenCount: 100,
              candidatesTokenCount: 20,
              thoughtsTokenCount: 7,
              cachedContentTokenCount: 5,
              totalTokenCount: 127,
              promptTokensDetails: [{ modality: "TEXT", tokenCount: 100 }],
            },
          };
          const mutableRequest = structuredClone(request);
          const attempt = prepareAIExecution(mutableRequest, authority(model));
          Object.assign(mutableRequest.evidence[0], {
            text: "Must not reach the provider",
          });
          const result = await attempt.invoke();
          assertEquals(result.kind, "draft");
          if (result.kind === "draft") {
            assertEquals(result.draft, { synthetic: true });
          }
          assertEquals(result.returnedModel, model);
          assertEquals(result.usage, {
            promptTokens: 100,
            candidateTokens: 20,
            totalTokens: 127,
            thinkingTokens: 7,
            cachedTokens: 5,
            modalityBreakdown: {
              prompt: { text: 100 },
              cached: {},
              candidates: {},
              tool: {},
            },
          });
          assertEquals(result.execution.timeoutMs, 90000);
          assert(result.execution.durationMs >= 0);
          await assertRejects(
            () => attempt.invoke(),
            Error,
            "ai_attempt_already_invoked",
          );
        },
      );
    }
    for (const input of multimodalCases()) {
      for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
        await step(
          `${input.label} preserves ${model} request and evidence`,
          async () => {
            const canonical = buildMultimodalAIRequest(input);
            const snapshot = resolveAIClaim(canonical, authority(model));
            const hasImages = input.imageBase64s.length > 0;
            const hasAudio = input.processedAudios.length > 0;
            const trigger = diagnosticTriggerForTier(
              model === "gemini-2.5-pro" ? "pro" : "flash",
            );
            const instruction = hasImages
              ? hasAudio
                ? MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION
                : getSystemInstruction(trigger)
              : hasAudio
              ? BIOACOUSTIC_SYSTEM_INSTRUCTION
              : DESCRIBE_SYSTEM_INSTRUCTION;
            const visualText = buildVisualMediaPrompt(
              input.visualMediaItems,
              input.capture.hasVideo,
              input.imageBase64s.length,
              input.hasVideoAudio,
            );
            const expectedParts = [
              {
                text:
                  "Additional observation context from user:\nSynthetic context one\nSynthetic context two",
              },
              ...(visualText ? [{ text: visualText }] : []),
              ...input.imageBase64s.map((data) => ({
                inlineData: { mimeType: "image/webp", data },
              })),
              ...input.processedAudios.map((data) => ({
                inlineData: { mimeType: "audio/wav", data },
              })),
              { text: buildContextText(input.telemetry) },
            ];
            const expectedConfig = {
              temperature: 0.1,
              seed: 42,
              maxOutputTokens: 8192,
              ...(model === "gemini-2.5-pro"
                ? { thinkingConfig: { thinkingBudget: 5000 } }
                : {}),
              responseMimeType: "application/json",
              responseSchema: !hasImages && hasAudio
                ? getMerianAudioResponseSchema()
                : getMerianResponseSchema(trigger),
            };
            assertEquals(buildGeminiRequest(canonical, snapshot), {
              model,
              contents: [{ role: "user", parts: expectedParts }],
              config: { systemInstruction: instruction, ...expectedConfig },
            });
            assertEquals(
              canonical.evidence.filter((part) => part.kind === "image").map((
                part,
              ) => part.lineage),
              input.imageBase64s.map((_, index) =>
                input.visualMediaItems[index] ?? null
              ),
            );
            assertEquals(
              canonical.evidence.filter((part) => part.kind === "audio").map((
                part,
              ) => [part.inputIndex, part.lineage]),
              input.processedAudios.map((
                _,
                index,
              ) => [
                input.processedAudioInputIndexes[index],
                input.audioMediaItems[index] ?? null,
              ]),
            );
            assertEquals(canonical.capture, input.capture);
            inspect = (url, body) => {
              assertEquals(
                url.pathname,
                `/v1beta/models/${model}:generateContent`,
              );
              assertEquals(body.contents, [{
                role: "user",
                parts: expectedParts,
              }]);
              assertEquals(body.systemInstruction, {
                role: "user",
                parts: [{ text: instruction }],
              });
              assertEquals(body.generationConfig, expectedConfig);
            };
            response = {
              candidates: [{
                content: { parts: [{ text: '{"synthetic":true}' }] },
                finishReason: "STOP",
                safetyRatings: [{
                  category: "HARM_CATEGORY_DANGEROUS_CONTENT",
                  probability: "MEDIUM",
                }],
              }],
            };
            const result = await prepareAIExecution(canonical, authority(model))
              .invoke();
            assertEquals(result.kind, "draft");
            assertEquals(result.usage, null);
            assert(
              result.providerDurationMs >= 0 &&
                result.providerDurationMs <= result.execution.durationMs,
            );
            assert(result.providerCompletedAt <= Date.now());
            assertEquals(
              isProviderSafetyRejected(
                result.finishReason ?? undefined,
                result.safetyRatings,
              ),
              true,
            );
            assertEquals(
              isProviderSafetyRejected("STOP", [{ probability: "LOW" }]),
              false,
            );
            assertEquals(
              isProviderSafetyRejected("STOP", [{ probability: "HIGH" }]),
              true,
            );
          },
        );
      }
    }
    inspect = () => {};
    for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
      for (const tier of ["free", "pro"] as const) {
        for (
          const profile of [
            "single",
            "multiple_with_note",
            "blank_note",
            "audio",
          ] as const
        ) {
          await step(
            `${profile} compatibility preserves ${model} / ${tier}`,
            async () => {
              const telemetry = {
                safeGpsLat: null,
                safeGpsLon: null,
                deviceLocale: "en-US",
                currentMonth: 9,
              };
              const audio = profile === "audio";
              const images = profile === "multiple_with_note"
                ? ["AQ==", "Ag=="]
                : ["AQ=="];
              const mimeType = profile === "multiple_with_note"
                ? "image/png"
                : undefined;
              const description = profile === "multiple_with_note"
                ? "  Synthetic note.  "
                : profile === "blank_note"
                ? "   "
                : undefined;
              const canonical = audio
                ? buildAudioAIRequest("Aw==", telemetry)
                : buildVisionAIRequest({
                  imageBase64s: images,
                  mimeType,
                  description,
                  telemetry,
                });
              const admitted = {
                ...authority(model),
                operation: audio
                  ? "scan_audio_identification"
                  : "scan_identification",
                reservation: {
                  ...authority(model).reservation,
                  tier: { effective_tier: tier },
                },
              };
              const snapshot = resolveAIClaim(canonical, admitted);
              const modelPro = model === "gemini-2.5-pro";
              const schemaTrigger = diagnosticTriggerForTier(
                tier === "pro" ? "pro" : "flash",
              );
              const promptTrigger = diagnosticTriggerForTier(
                modelPro ? "pro" : "flash",
              );
              const parts = [
                {
                  text: buildContextText(
                    telemetry,
                    audio
                      ? "Perform bioacoustic identification."
                      : "Perform biological identification.",
                  ),
                },
                ...(audio
                  ? [{ inlineData: { mimeType: "audio/wav", data: "Aw==" } }]
                  : images.map((data) => ({
                    inlineData: { mimeType: mimeType || "image/webp", data },
                  }))),
                ...(profile === "multiple_with_note"
                  ? [{
                    text:
                      "\n\nAdditional observation context from user:\nSynthetic note.",
                  }]
                  : []),
              ];
              const instruction = audio
                ? AUDIO_COMPAT_INSTRUCTION
                : getSystemInstruction(promptTrigger);
              const config = {
                temperature: 0.1,
                seed: 42,
                ...(!audio ? { topK: 40 } : {}),
                maxOutputTokens: audio ? 2048 : modelPro ? 8192 : 4096,
                thinkingConfig: {
                  thinkingBudget: audio ? 2048 : modelPro ? 5000 : 2048,
                },
                responseMimeType: "application/json",
                responseSchema: audio
                  ? getMerianAudioResponseSchema()
                  : getMerianResponseSchema(schemaTrigger),
              };
              const safetySettings = [
                {
                  category: "HARM_CATEGORY_DANGEROUS_CONTENT",
                  threshold: "BLOCK_ONLY_HIGH",
                },
                {
                  category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                  threshold: "BLOCK_ONLY_HIGH",
                },
              ];
              assertEquals<unknown>(buildGeminiRequest(canonical, snapshot), {
                model,
                contents: [{ role: "user", parts }],
                config: {
                  systemInstruction: instruction,
                  ...config,
                  ...(!audio ? { safetySettings } : {}),
                },
              });
              inspect = (url, body) => {
                assertEquals(
                  url.pathname,
                  `/v1beta/models/${model}:generateContent`,
                );
                assertEquals(body.contents, [{ role: "user", parts }]);
                assertEquals(body.systemInstruction, {
                  role: "user",
                  parts: [{ text: instruction }],
                });
                assertEquals(body.generationConfig, config);
                assertEquals(
                  body.safetySettings,
                  audio ? undefined : safetySettings,
                );
              };
              response = {
                candidates: [{
                  finishReason: "STOP",
                  content: { parts: [{ text: '{"synthetic":true}' }] },
                }],
              };
              const attempt = prepareAIExecution(canonical, admitted);
              Object.assign(canonical.evidence[1], {
                data: "Must not reach the provider",
              });
              const result = await attempt.invoke();
              assertEquals(result.kind, "draft");
              assertEquals(result.execution.operation, admitted.operation);
              assertEquals(result.usage, null);
              await assertRejects(
                () => attempt.invoke(),
                Error,
                "ai_attempt_already_invoked",
              );
            },
          );
        }
      }
    }
    for (
      const canonical of [
        request,
        buildVisionAIRequest({
          imageBase64s: ["AQ=="],
          telemetry: { safeGpsLat: null, safeGpsLon: null },
        }),
        buildAudioAIRequest("Ag==", { safeGpsLat: null, safeGpsLon: null }),
        buildMultimodalAIRequest(multimodalCases()[0]),
      ]
    ) {
      await step(
        `${canonical.variant} preserves first-part fallback policy`,
        async () => {
          inspect = () => {};
          // The SDK omits thought parts from its text getter. Legacy endpoints
          // explicitly used parts[0].text when that getter was empty; main did not.
          response = {
            candidates: [{
              finishReason: "FINISH_REASON_UNSPECIFIED",
              content: {
                parts: [{ text: '{"synthetic":true}', thought: true }],
              },
            }],
          };
          const admitted = {
            ...authority(),
            operation: canonical.variant === "audio_compat"
              ? "scan_audio_identification"
              : "scan_identification",
          };
          const result = await prepareAIExecution(canonical, admitted).invoke();
          assertEquals(
            result.kind,
            canonical.variant === "multimodal" ? "invalid_output" : "draft",
          );
          if (result.kind === "draft") {
            assertEquals(result.draft, { synthetic: true });
          }
        },
      );
    }
    for (const finishReason of ["SAFETY", "PROHIBITED_CONTENT", "MAX_TOKENS"]) {
      await step(`finish ${finishReason} stays distinct`, async () => {
        response = { candidates: [{ finishReason }] };
        const result = await prepareAIExecution(request, authority()).invoke();
        assertEquals(
          result.kind,
          finishReason === "MAX_TOKENS" ? "invalid_output" : "refusal",
        );
        assertEquals(result.finishReason, finishReason);
        assertEquals(result.usage, null);
      });
    }
    await step("malformed JSON and absent usage stay explicit", async () => {
      response = {
        candidates: [{
          content: { parts: [{ text: "Malformed synthetic output" }] },
          finishReason: "STOP",
        }],
      };
      const result = await prepareAIExecution(request, authority()).invoke();
      assertEquals(result.kind, "invalid_output");
      assertEquals(result.usage, null);
      assertEquals(result.returnedModel, null);
    });
    for (const code of [400, 429, 503]) {
      await step(`HTTP ${code} has no retry`, async () => {
        status = code;
        response = { error: { code, message: "Synthetic provider failure" } };
        const result = await prepareAIExecution(request, authority()).invoke();
        assertEquals(
          result.kind,
          code === 503 ? "unknown_execution" : "operational_failure",
        );
      });
    }
    await step(
      "timeout is unknown execution and cannot redispatch",
      async () => {
        hang = true;
        const attempt = prepareAIExecution(request, authority());
        const keepAlive = originalTimeout(() => {}, 1000);
        try {
          assertEquals((await attempt.invoke()).kind, "unknown_execution");
        } finally {
          clearTimeout(keepAlive);
        }
        await assertRejects(
          () => attempt.invoke(),
          Error,
          "ai_attempt_already_invoked",
        );
      },
    );
    assertEquals(timeouts, calls);
  } finally {
    globalThis.fetch = originalFetch;
    globalThis.setTimeout = originalTimeout;
    timers.forEach(clearTimeout);
    for (const [name, value] of environment) {
      if (value == null) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
});
