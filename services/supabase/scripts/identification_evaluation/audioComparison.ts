import { buildGeminiRequestParameters } from "../../functions/_shared/ai/geminiRequest.ts";
import { resolveAIClaim } from "../../functions/_shared/ai/registry.ts";
import { encodeBase64 } from "../../functions/_shared/encoding.ts";
import { buildMultimodalAIRequest } from "../../functions/identify-multimodal/provider.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import { confidencePolicy, fixtureAuthority } from "./profiles.ts";
import { requireCondition as check } from "./validation.ts";

import {
  AUDIO_COMPARISON_ARMS,
  comparisonAudio,
} from "../../functions/identify-multimodal/comparison/audio.ts";
export {
  AUDIO_COMPARISON_ARMS,
  comparisonAudio,
} from "../../functions/identify-multimodal/comparison/audio.ts";
export type { AudioComparisonArm } from "../../functions/identify-multimodal/comparison/audio.ts";
export const AUDIO_COMPARISON_CONTEXT = Object.freeze({
  safeGpsLat: null,
  safeGpsLon: null,
  deviceLocale: "en",
  deviceTimeZone: "UTC",
  deviceRegion: null,
  currentMonth: 1,
  timeOfDay: "12:00 PM",
});

/** Freeze only hashes/settings. Neither source media nor a provider body is retained. */
export async function prepareAudioComparisonPair(bytes: Uint8Array) {
  const arms = [];
  for (const arm of AUDIO_COMPARISON_ARMS) {
    const wav = comparisonAudio(bytes, arm);
    const request = buildMultimodalAIRequest({
      observationEvidenceTexts: [],
      visualMediaItems: [],
      imageBase64s: [],
      imageMimeType: "image/webp",
      processedAudios: [encodeBase64(wav)],
      audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
      processedAudioInputIndexes: [0],
      hasVideoAudio: false,
      capture: {
        hasVideo: false,
        videoClipCount: 0,
        declaredVideoFrameCount: 0,
        videoInferenceFrameCount: 0,
      },
      telemetry: AUDIO_COMPARISON_CONTEXT,
    });
    const snapshot = resolveAIClaim(request, fixtureAuthority("gemini_pro"));
    const native = buildGeminiRequestParameters(request, snapshot);
    const withoutAudio = buildGeminiRequestParameters({
      ...request,
      evidence: request.evidence.map((item) =>
        item.kind === "audio" ? { ...item, data: "" } : item
      ),
    }, snapshot);
    arms.push({
      arm,
      processedWavSha256: await fingerprintBytes(wav),
      processedByteLength: wav.length,
      sampleRate: 16000,
      channels: 1,
      bitsPerSample: 16,
      sampleCount: (wav.length - 44) / 2,
      providerRequestSha256: await fingerprintJson(native),
      requestWithoutAudioSha256: await fingerprintJson(withoutAudio),
      policySha256: await fingerprintJson(snapshot),
      confidenceSha256: await fingerprintJson(confidencePolicy("gemini_pro")),
      model: snapshot.model,
      prompt: snapshot.prompt,
      schema: snapshot.schema,
      generation: snapshot.generation,
    });
  }
  check(
    arms[0].requestWithoutAudioSha256 === arms[1].requestWithoutAudioSha256,
  );
  check(arms[0].policySha256 === arms[1].policySha256);
  return {
    sourceWavSha256: await fingerprintBytes(bytes),
    sourceByteLength: bytes.length,
    arms,
  };
}
