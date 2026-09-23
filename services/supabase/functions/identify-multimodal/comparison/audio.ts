import { decodeBase64 } from "../../_shared/encoding.ts";
import {
  encodeWav16,
  extractSamplesAsFloat32,
  parseWavHeader,
} from "../../audio-spec/wav.ts";
import { processMultimodalWAV } from "../audio.ts";
import { resampleLinear, trimSilence } from "./legacyAudio.ts";

export const AUDIO_COMPARISON_ARMS = [
  "audio-linear-full-windows-v1",
  "audio-sinc-partial-tail-v1",
] as const;
export type AudioComparisonArm = typeof AUDIO_COMPARISON_ARMS[number];

/** Canonical standalone mono PCM16, 44.1 kHz, <=15s, before either DSP allocates.
 * Runtime callers must first verify server assignment and the frozen source hash.
 * Video companions and ordinary requests never enter this experimental lane.
 */
export function comparisonAudio(
  bytes: Uint8Array,
  arm: AudioComparisonArm,
): Uint8Array {
  const check = (condition: boolean) => {
    if (!condition) throw new Error("audio_comparison_invalid_wav");
  };
  check(AUDIO_COMPARISON_ARMS.includes(arm));
  check(bytes.length >= 44 && bytes.length <= 44 + 44100 * 15 * 2);
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (offset: number) =>
    String.fromCharCode(...bytes.slice(offset, offset + 4));
  check(
    tag(0) === "RIFF" && tag(8) === "WAVE" && tag(12) === "fmt " &&
      tag(36) === "data",
  );
  check(
    v.getUint32(4, true) + 8 === bytes.length && v.getUint32(16, true) === 16,
  );
  check(v.getUint16(20, true) === 1 && v.getUint16(22, true) === 1);
  check(v.getUint32(24, true) === 44100 && v.getUint32(28, true) === 88200);
  check(v.getUint16(32, true) === 2 && v.getUint16(34, true) === 16);
  check(
    v.getUint32(40, true) === bytes.length - 44 &&
      (bytes.length - 44) % 2 === 0,
  );
  const buffer = new Uint8Array(bytes).buffer;
  if (arm === "audio-sinc-partial-tail-v1") {
    return decodeBase64(
      processMultimodalWAV(buffer, { kind: "audio", sourceIndex: 0 }, {
        present: true,
        error: null,
        timeline: [{ kind: "audio", sourceIndex: 0, audioInputIndex: 0 }],
      }),
    );
  }
  const samples = extractSamplesAsFloat32(buffer, parseWavHeader(buffer));
  const resampled = resampleLinear(trimSilence(samples, 44100), 44100, 16000);
  check(resampled.length >= 8000 && resampled.length <= 16000 * 15);
  return encodeWav16(resampled, 16000);
}
