/** Offline-only prompt experiment. No live registry entry or provider executor. */
import reviewedDesign from "../../../../docs/rfcs/identification-experiment-plans/2026-09-24-audio-uncertainty/design.json" with {
  type: "json",
};
import type { AIAttemptSnapshot } from "../../functions/_shared/ai/contracts.ts";
import { buildGeminiRequestParameters } from "../../functions/_shared/ai/geminiRequest.ts";
import { resolveAIClaim } from "../../functions/_shared/ai/registry.ts";
import { decodeBase64 } from "../../functions/_shared/encoding.ts";
import { parseWavHeader } from "../../functions/audio-spec/wav.ts";
import { processMultimodalWAV } from "../../functions/identify-multimodal/audio.ts";
import { buildMultimodalAIRequest } from "../../functions/identify-multimodal/provider.ts";
import { validateWavContainer } from "./assets.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import { confidencePolicy, fixtureAuthority } from "./profiles.ts";
import { member, requireCondition as check } from "./validation.ts";

export const AUDIO_UNCERTAINTY_DESIGN_SHA256 =
  "54bb0b5469230b57c507e63ea55d61e3e201cacbd4115dcc0e418ed1aa81df32";
export const AUDIO_UNCERTAINTY_PROMPT =
  "identify_audio_uncertainty_experiment_v1";
export const AUDIO_PROMPT_CONTEXT = Object.freeze({
  safeGpsLat: null,
  safeGpsLon: null,
  deviceLocale: "en",
  deviceTimeZone: "UTC",
  deviceRegion: null,
  currentMonth: 1,
  timeOfDay: "12:00 PM",
});
export type AudioPromptArm = "A" | "B";
type OfflinePromptPolicy = Omit<AIAttemptSnapshot, "prompt"> & {
  prompt: "identify_audio_v2" | typeof AUDIO_UNCERTAINTY_PROMPT;
};

/** Return a fresh trusted copy only after the entire reviewed design matches.
 * This design is not a RunSpec and cannot authorize or select live requests.
 */
export async function audioUncertaintyDesign(value: unknown = reviewedDesign) {
  check(await fingerprintJson(value) === AUDIO_UNCERTAINTY_DESIGN_SHA256);
  check(
    await fingerprintJson(reviewedDesign) === AUDIO_UNCERTAINTY_DESIGN_SHA256,
  );
  return structuredClone(reviewedDesign);
}

/** Evidence only: this API cannot accept case metadata, references or labels. */
export async function buildOfflineAudioPromptPair(bytes: Uint8Array) {
  const design = await audioUncertaintyDesign();
  check(bytes.length <= 44 + 44100 * 15 * 2);
  validateWavContainer(bytes);
  const buffer = new Uint8Array(bytes).buffer;
  const header = parseWavHeader(buffer);
  check(
    header.audioFormat === 1 && header.numChannels === 1 &&
      header.sampleRate === 44100 && header.bitsPerSample === 16 &&
      header.dataOffset === 44 && header.dataLength === bytes.length - 44,
  );
  const audio = processMultimodalWAV(
    buffer,
    { kind: "audio", sourceIndex: 0 },
    {
      present: true,
      error: null,
      timeline: [{ kind: "audio", sourceIndex: 0, audioInputIndex: 0 }],
    },
  );
  const request = buildMultimodalAIRequest({
    observationEvidenceTexts: [],
    visualMediaItems: [],
    imageBase64s: [],
    imageMimeType: "image/webp",
    processedAudios: [audio],
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
  const snapshot = resolveAIClaim(request, fixtureAuthority("gemini_pro"));
  const baseline = buildGeminiRequestParameters(request, snapshot);
  const rules = design.invariants;
  check(
    snapshot.provider === "gemini" && snapshot.model === design.target.model &&
      snapshot.prompt === design.arms.A.prompt &&
      snapshot.schema === rules.schema &&
      snapshot.confidence === rules.confidenceSemantics &&
      snapshot.timeoutMs === rules.timeoutMs &&
      snapshot.diagnosticTrigger === rules.primaryCandidateCutoff,
  );
  check(
    await fingerprintJson(snapshot.generation) === await fingerprintJson({
      temperature: rules.temperature,
      seed: rules.seed,
      maxOutputTokens: rules.maxOutputTokens,
      thinkingBudget: rules.thinkingBudget,
    }),
  );
  check(
    await fingerprintJson(confidencePolicy("gemini_pro")) ===
      await fingerprintJson({
        possible: rules.possibleThresholdPro,
        strong: rules.strongThresholdPro,
        diagnostic: rules.primaryCandidateCutoff,
      }),
  );
  const instruction = baseline.config?.systemInstruction;
  check(typeof instruction === "string");
  const marker = "# Response Detail Rules";
  check(instruction.split(marker).length === 2);
  const delta = design.arms.B.instructionDelta;
  check(
    await fingerprintBytes(new TextEncoder().encode(delta)) ===
      design.arms.B.instructionDeltaSha256,
  );
  // Narrow instruction-only clone. No arbitrary content/schema override.
  const candidate = structuredClone(baseline);
  candidate.config!.systemInstruction = instruction.replace(
    marker,
    delta + "\n\n" + marker,
  );
  const policy: OfflinePromptPolicy = {
    ...snapshot,
    prompt: AUDIO_UNCERTAINTY_PROMPT,
  };
  const withoutInstruction = (native: typeof baseline) => {
    const copy = structuredClone(native);
    delete copy.config!.systemInstruction;
    return copy;
  };
  check(
    await fingerprintJson(withoutInstruction(baseline)) ===
      await fingerprintJson(withoutInstruction(candidate)),
  );
  return {
    processedWav: decodeBase64(audio),
    variants: [
      { arm: "A" as const, native: baseline, policy: snapshot },
      { arm: "B" as const, native: candidate, policy },
    ],
  };
}

/** Verify the actual DSP output before attesting its format in a manifest. */
export function processedAudioFormat(bytes: Uint8Array) {
  check(bytes.length <= 44 + 16000 * 15 * 2);
  validateWavContainer(bytes);
  const header = parseWavHeader(new Uint8Array(bytes).buffer);
  check(
    header.audioFormat === 1 && header.numChannels === 1 &&
      header.sampleRate === 16000 && header.bitsPerSample === 16 &&
      header.dataOffset === 44 && header.dataLength === bytes.length - 44 &&
      header.dataLength >= 8000 * 2,
  );
  return {
    sampleRate: header.sampleRate,
    channels: header.numChannels,
    bitsPerSample: header.bitsPerSample,
    sampleCount: header.dataLength / 2,
  };
}

/** Persist hashes/settings only. Native bodies and processed audio stay in memory. */
export async function prepareAudioPromptPair(bytes: Uint8Array) {
  const pair = await buildOfflineAudioPromptPair(bytes);
  const arms = await Promise.all(
    pair.variants.map(async ({ arm, native, policy }) => {
      const copy = structuredClone(native);
      delete copy.config!.systemInstruction;
      return {
        arm,
        providerRequestSha256: await fingerprintJson(native),
        requestWithoutInstructionSha256: await fingerprintJson(copy),
        policySha256: await fingerprintJson(policy),
        instructionSha256: await fingerprintBytes(
          new TextEncoder().encode(native.config!.systemInstruction as string),
        ),
        schemaSha256: await fingerprintJson(native.config!.responseSchema),
        confidenceSha256: await fingerprintJson(confidencePolicy("gemini_pro")),
        model: policy.model,
        prompt: policy.prompt,
        schema: policy.schema,
        confidence: policy.confidence,
        timeoutMs: policy.timeoutMs,
        generation: policy.generation,
      };
    }),
  );
  check(arms[0].providerRequestSha256 !== arms[1].providerRequestSha256);
  check(arms[0].policySha256 !== arms[1].policySha256);
  return {
    sourceWavSha256: await fingerprintBytes(bytes),
    sourceByteLength: bytes.length,
    processedWavSha256: await fingerprintBytes(pair.processedWav),
    processedByteLength: pair.processedWav.length,
    ...processedAudioFormat(pair.processedWav),
    arms,
  };
}
export type PreparedAudioPromptPair = Awaited<
  ReturnType<typeof prepareAudioPromptPair>
>;

/** One immutable preparation slot per planned first submission, not a scan ID.
 * App identities, runtime authorization and receipt binding belong to Slice 2.
 */
export async function audioPromptAssignments(
  pairs: readonly (PreparedAudioPromptPair & { caseId: string })[],
) {
  const design = await audioUncertaintyDesign();
  check(pairs.length === 6 && new Set(pairs.map((p) => p.caseId)).size === 6);
  const result = [];
  for (const slot of design.schedule) {
    member(slot.arm, ["A", "B"]);
    const pair = pairs.find((p) => p.caseId === slot.caseId);
    check(
      pair && pair.sourceWavSha256 ===
          design.cases.find((c) => c.caseId === slot.caseId)?.sourceWavSha256,
    );
    const arm = pair.arms.find((a) => a.arm === slot.arm);
    check(arm);
    const binding = {
      designSha256: AUDIO_UNCERTAINTY_DESIGN_SHA256,
      ...slot,
      sourceWavSha256: pair.sourceWavSha256,
      processedWavSha256: pair.processedWavSha256,
      providerRequestSha256: arm.providerRequestSha256,
      policySha256: arm.policySha256,
    };
    result.push({
      ...binding,
      preparationSlotId: "audio-uncertainty-v1-slot-" +
        String(slot.slot).padStart(2, "0"),
      assignmentSha256: await fingerprintJson(binding),
      scanId: null,
    });
  }
  check(
    result.length === 36 &&
      new Set(result.map((a) => a.assignmentSha256)).size === 36,
  );
  for (const c of design.cases) {
    for (const arm of ["A", "B"]) {
      check(
        result.filter((a) => a.caseId === c.caseId && a.arm === arm).length ===
          3,
      );
    }
  }
  return result;
}
