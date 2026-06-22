import {
  encodeWav16,
  extractSamplesAsFloat32,
  mixToMono,
  parseWavHeader,
  resampleLinear,
  trimSilence,
} from "../audio-spec/wav.ts";
import { encodeBase64 } from "./encoding.ts";

export const TARGET_AUDIO_SAMPLE_RATE = 16_000;

export interface ProcessedWavResult {
  base64Audio: string;
  sourceSampleRate: number;
  sourceChannels: number;
  originalSampleCount: number;
  trimmedSampleCount: number;
  resampledSampleCount: number;
  encodedByteLength: number;
}

export function processWavBuffer(
  rawWavBuffer: ArrayBuffer,
  targetSampleRate = TARGET_AUDIO_SAMPLE_RATE,
): ProcessedWavResult {
  const header = parseWavHeader(rawWavBuffer);
  const interleaved = extractSamplesAsFloat32(rawWavBuffer, header);
  const mono = mixToMono(interleaved, header.numChannels);
  const trimmed = trimSilence(mono, header.sampleRate);
  const resampled = resampleLinear(
    trimmed,
    header.sampleRate,
    targetSampleRate,
  );

  if (resampled.length < 8_000) {
    throw new Error(
      "Audio too short to identify. Please record a longer clip.",
    );
  }

  const processedWav = encodeWav16(resampled, targetSampleRate);
  return {
    base64Audio: encodeBase64(processedWav),
    sourceSampleRate: header.sampleRate,
    sourceChannels: header.numChannels,
    originalSampleCount: mono.length,
    trimmedSampleCount: trimmed.length,
    resampledSampleCount: resampled.length,
    encodedByteLength: processedWav.byteLength,
  };
}

export function processWAV(rawWavBuffer: ArrayBuffer): string {
  return processWavBuffer(rawWavBuffer).base64Audio;
}
