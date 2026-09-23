import { buildGeminiRequestParameters } from "../../functions/_shared/ai/geminiRequest.ts";
import { resolveAIClaim } from "../../functions/_shared/ai/registry.ts";
import {
  decodeBase64,
  encodeBase64,
} from "../../functions/_shared/encoding.ts";
import {
  encodeWav16,
  extractSamplesAsFloat32,
  parseWavHeader,
} from "../../functions/audio-spec/wav.ts";
import { processMultimodalWAV } from "../../functions/identify-multimodal/audio.ts";
import { buildMultimodalAIRequest } from "../../functions/identify-multimodal/provider.ts";
import { validateWavContainer } from "./assets.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import { resampleLinear, trimSilence } from "./legacyAudio.ts";
import { confidencePolicy, fixtureAuthority } from "./profiles.ts";
import { requireCondition as check } from "./validation.ts";

export const AUDIO_COMPARISON_ARMS = [
  "audio-linear-full-windows-v1",
  "audio-sinc-partial-tail-v1",
] as const;
export type AudioComparisonArm = typeof AUDIO_COMPARISON_ARMS[number];
export const AUDIO_COMPARISON_CONTEXT = Object.freeze({
  safeGpsLat: null,
  safeGpsLon: null,
  deviceLocale: "en",
  deviceTimeZone: "UTC",
  deviceRegion: null,
  currentMonth: 1,
  timeOfDay: "12:00 PM",
});

/** Only the six-clip standalone lane: canonical mono PCM16, 44.1 kHz, <=15s.
 * Bounds apply equally to both arms before historical code can allocate.
 * No route, credential, provider dispatch, or production model override exists.
 */
export function comparisonAudio(
  bytes: Uint8Array,
  arm: AudioComparisonArm,
): Uint8Array {
  check(AUDIO_COMPARISON_ARMS.includes(arm));
  check(bytes.length >= 44 && bytes.length <= 44 + 44100 * 15 * 2);
  validateWavContainer(bytes);
  const buffer = new Uint8Array(bytes).buffer;
  const header = parseWavHeader(buffer);
  check(
    header.sampleRate === 44100 && header.numChannels === 1 &&
      header.bitsPerSample === 16,
  );
  if (arm === "audio-sinc-partial-tail-v1") {
    return decodeBase64(
      processMultimodalWAV(buffer, { kind: "audio", sourceIndex: 0 }, {
        present: true,
        error: null,
        timeline: [{ kind: "audio", sourceIndex: 0, audioInputIndex: 0 }],
      }),
    );
  }
  const samples = extractSamplesAsFloat32(buffer, header);
  const resampled = resampleLinear(trimSilence(samples, 44100), 44100, 16000);
  check(resampled.length >= 8000 && resampled.length <= 16000 * 15);
  return encodeWav16(resampled, 16000);
}

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
