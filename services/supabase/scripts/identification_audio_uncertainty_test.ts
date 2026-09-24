import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import { encodeWav16 } from "../functions/audio-spec/wav.ts";
import { processMultimodalWAV } from "../functions/identify-multimodal/audio.ts";
import { buildMultimodalAIRequest } from "../functions/identify-multimodal/provider.ts";
import { buildGeminiRequestParameters } from "../functions/_shared/ai/geminiRequest.ts";
import { resolveAIClaim } from "../functions/_shared/ai/registry.ts";
import {
  AUDIO_PROMPT_CONTEXT,
  AUDIO_UNCERTAINTY_PROMPT,
  audioPromptAssignments,
  audioUncertaintyDesign,
  buildOfflineAudioPromptPair,
  prepareAudioPromptPair,
  processedAudioFormat,
} from "./identification_evaluation/audioPromptComparison.ts";
import {
  fingerprintBytes,
  fingerprintJson,
} from "./identification_evaluation/evidence.ts";
import { fixtureAuthority } from "./identification_evaluation/profiles.ts";
import { parseRunSpec } from "./identification_evaluation/runContracts.ts";

function source(frames = 44928) {
  return encodeWav16(
    Float32Array.from(
      { length: frames },
      (_, i) => 0.5 * Math.sin(2 * Math.PI * 3000 * i / 44100),
    ),
    44100,
  );
}
Deno.test("offline prompt experiment changes only the system instruction from the actual V2 request", async () => {
  const bytes = source();
  const actualRequest = buildMultimodalAIRequest({
    observationEvidenceTexts: [],
    visualMediaItems: [],
    imageBase64s: [],
    imageMimeType: "image/webp",
    processedAudios: [
      processMultimodalWAV(new Uint8Array(bytes).buffer, {
        kind: "audio",
        sourceIndex: 0,
      }, { present: false, error: null, timeline: null }),
    ],
    audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
    processedAudioInputIndexes: [0],
    hasVideoAudio: false,
    capture: {
      hasVideo: false,
      videoClipCount: 0,
      declaredVideoFrameCount: 0,
      videoInferenceFrameCount: 0,
    },
    telemetry: AUDIO_PROMPT_CONTEXT,
  });
  const actualPolicy = resolveAIClaim(
    actualRequest,
    fixtureAuthority("gemini_pro"),
  );
  const actual = buildGeminiRequestParameters(actualRequest, actualPolicy);
  const { variants, processedWav } = await buildOfflineAudioPromptPair(bytes);
  const [a, b] = variants;
  assertEquals(a.native, actual);
  assertEquals(a.policy, actualPolicy);
  assertEquals(b.policy, { ...actualPolicy, prompt: AUDIO_UNCERTAINTY_PROMPT });
  assertEquals(actualPolicy.prompt, "identify_audio_v2");
  const candidateInstruction = b.native.config!.systemInstruction;
  const stripped = structuredClone(b.native);
  stripped.config!.systemInstruction = a.native.config!.systemInstruction;
  assertEquals(stripped, actual);
  const d = await audioUncertaintyDesign();
  assertEquals(
    candidateInstruction,
    (actual.config!.systemInstruction as string).replace(
      "# Response Detail Rules",
      d.arms.B.instructionDelta + "\n\n# Response Detail Rules",
    ),
  );
  const nativeText = JSON.stringify(b.native.contents);
  assert(
    !nativeText.includes("c0025") && !nativeText.includes("Ochotona") &&
      !nativeText.includes("provisional") && !nativeText.includes("challenge"),
  );
  const prepared = await prepareAudioPromptPair(bytes);
  assertEquals(prepared.sourceWavSha256, await fingerprintBytes(bytes));
  assertEquals(
    prepared.processedWavSha256,
    await fingerprintBytes(processedWav),
  );
  assertEquals(prepared.sampleCount, Math.floor(44928 * 16000 / 44100));
  assertEquals(
    prepared.arms[0].providerRequestSha256,
    await fingerprintJson(actual),
  );
  assertEquals(
    prepared.arms[0].requestWithoutInstructionSha256,
    prepared.arms[1].requestWithoutInstructionSha256,
  );
  assertEquals(prepared.arms[0].schemaSha256, prepared.arms[1].schemaSha256);
  assertEquals(
    prepared.arms[0].confidenceSha256,
    prepared.arms[1].confidenceSha256,
  );
  assertNotEquals(
    prepared.arms[0].instructionSha256,
    prepared.arms[1].instructionSha256,
  );
  assertNotEquals(prepared.arms[0].policySha256, prepared.arms[1].policySha256);
  assert(!JSON.stringify(prepared).includes("inlineData"));
  assert(!JSON.stringify(prepared).includes("systemInstruction"));
});

Deno.test("reviewed design rejects prompt, rules, source, schedule and authorization drift", async () => {
  const d = await audioUncertaintyDesign();
  assertThrows(() => parseRunSpec(d));
  for (
    const change of [
      (v: typeof d) => v.arms.B.instructionDelta += " extra",
      (v: typeof d) => v.schedule[0].arm = "B",
      (v: typeof d) => v.sources.visible.sourceCorpusSha256 = "0".repeat(64),
      (v: typeof d) => v.invariants.strongThresholdPro = 0.9,
      (v: typeof d) => v.executionReady = true,
    ]
  ) {
    const altered = structuredClone(d);
    change(altered);
    await assertRejects(() => audioUncertaintyDesign(altered));
  }
  // Copies returned to callers cannot mutate the pinned imported design.
  d.schedule.reverse();
  assertEquals((await audioUncertaintyDesign()).schedule[0].slot, 1);
});

Deno.test("prompt preparation preserves all 36 prospective slots and keeps repeat request hashes fixed", async () => {
  const d = await audioUncertaintyDesign();
  const invented = await prepareAudioPromptPair(source());
  // Mechanical schedule fixture only; these hashes do not admit invented media.
  const pairs = d.cases.map((c) => ({
    ...structuredClone(invented),
    caseId: c.caseId,
    sourceWavSha256: c.sourceWavSha256,
  }));
  const slots = await audioPromptAssignments(pairs);
  assertEquals(slots.length, 36);
  assertEquals(new Set(slots.map((s) => s.assignmentSha256)).size, 36);
  assertEquals(new Set(slots.map((s) => s.preparationSlotId)).size, 36);
  assertEquals(
    slots.map(({ slot, block, caseId, repeat, arm, maxSubmissions }) => ({
      slot,
      block,
      caseId,
      repeat,
      arm,
      maxSubmissions,
    })),
    d.schedule,
  );
  assertEquals(slots, await audioPromptAssignments(pairs.toReversed()));
  assert(
    slots.every((s) =>
      s.scanId === null &&
      s.preparationSlotId.startsWith("audio-uncertainty-v1-")
    ),
  );
  for (const c of d.cases) {
    for (const arm of ["A", "B"]) {
      const repeated = slots.filter((s) =>
        s.caseId === c.caseId && s.arm === arm
      );
      assertEquals(repeated.length, 3);
      assertEquals(
        new Set(repeated.map((s) => s.providerRequestSha256)).size,
        1,
      );
      assertEquals(repeated.map((s) => s.repeat), [1, 2, 3]);
    }
  }
  await assertRejects(() => audioPromptAssignments(pairs.slice(1)));
  await assertRejects(() =>
    audioPromptAssignments([...pairs.slice(1), pairs[1]])
  );
  pairs[0].sourceWavSha256 = "0".repeat(64);
  await assertRejects(() => audioPromptAssignments(pairs));
});

Deno.test("offline prompt preparation rejects unsupported, malformed and out-of-budget WAVs", async () => {
  const metadata = source();
  metadata.set(new TextEncoder().encode("LIST"), 36);
  const truncated = source().slice(0, -2);
  const stereo = source();
  new DataView(stereo.buffer).setUint16(22, 2, true);
  for (
    const bytes of [
      new Uint8Array(),
      source(44100 * 15 + 1),
      source(100),
      encodeWav16(new Float32Array(16000), 16000),
      metadata,
      truncated,
      stereo,
    ]
  ) await assertRejects(() => prepareAudioPromptPair(bytes));
});

Deno.test("processed audio metadata comes from a validated canonical DSP output", () => {
  assertEquals(
    processedAudioFormat(encodeWav16(new Float32Array(16000), 16000)),
    {
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
      sampleCount: 16000,
    },
  );
  for (
    const bytes of [
      source(),
      new Uint8Array(),
      encodeWav16(new Float32Array(16000 * 15 + 1), 16000),
      encodeWav16(new Float32Array(7999), 16000),
    ]
  ) assertThrows(() => processedAudioFormat(bytes));
});
