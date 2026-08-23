import { assertEquals } from "@std/assert";

import { encodeWav16 } from "../audio-spec/wav.ts";
import { isWavContainer } from "./audioProcessing.ts";

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
