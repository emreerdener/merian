import { assertEquals, assertThrows } from "@std/assert";

import { encodeWav16, parseWavHeader } from "../audio-spec/wav.ts";
import { isWavContainer, processWavBuffer } from "./audioProcessing.ts";
import { decodeBase64 } from "./encoding.ts";
import { MEDIA_BUDGETS } from "./mediaBudgets.ts";

Deno.test("processed WAV retains partial-window duration and the PCM16 mono contract", () => {
  const input = encodeWav16(new Float32Array(44_237).fill(0.25), 44_100);
  const result = processWavBuffer(input.buffer as ArrayBuffer);
  const output = decodeBase64(result.base64Audio);
  const header = parseWavHeader(output.buffer as ArrayBuffer);
  assertEquals(result.originalSampleCount, 44_237);
  assertEquals(result.trimmedSampleCount, 44_237);
  assertEquals(result.resampledSampleCount, 16_049);
  assertEquals(header.sampleRate, 16_000);
  assertEquals(header.numChannels, 1);
  assertEquals(header.audioFormat, 1);
  assertEquals(header.bitsPerSample, 16);
  assertEquals(header.dataLength, 16_049 * 2);
  assertEquals(result.encodedByteLength, 44 + header.dataLength);
});

Deno.test("audio processing bounds source and expanded WAV sizes", () => {
  assertThrows(
    () => processWavBuffer(new ArrayBuffer(MEDIA_BUDGETS.maxAudioRawBytes + 1)),
    Error,
    "source audio exceeds processing budget",
  );
  const tinyRate = encodeWav16(new Float32Array(1_000), 1);
  assertThrows(
    () => processWavBuffer(tinyRate.buffer as ArrayBuffer),
    Error,
    "resampled audio exceeds processing budget",
  );
});

Deno.test("isWavContainer recognizes the inference WAV transport", () => {
  const encoded = encodeWav16(new Float32Array([0, 0.25, -0.25]), 44_100);
  const buffer = encoded.buffer.slice(
    encoded.byteOffset,
    encoded.byteOffset + encoded.byteLength,
  ) as ArrayBuffer;

  assertEquals(isWavContainer(buffer), true);
});

Deno.test("isWavContainer rejects M4A and truncated payloads", () => {
  const m4aLike = new Uint8Array([
    0x00,
    0x00,
    0x00,
    0x18,
    0x66,
    0x74,
    0x79,
    0x70,
    0x4d,
    0x34,
    0x41,
    0x20,
  ]);
  const m4aBuffer = m4aLike.buffer.slice(
    m4aLike.byteOffset,
    m4aLike.byteOffset + m4aLike.byteLength,
  ) as ArrayBuffer;

  assertEquals(isWavContainer(m4aBuffer), false);
  assertEquals(isWavContainer(new ArrayBuffer(11)), false);
});
