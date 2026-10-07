import { assertEquals, assertThrows } from "@std/assert";
import { validatePreparedAudioContainer } from "./audioContainer.ts";

function wav(padding = 0, frames = 128): Uint8Array {
  const bytes = new Uint8Array(
    44 + frames * 2 + (padding ? 8 + padding + padding % 2 : 0),
  );
  const view = new DataView(bytes.buffer);
  const tag = (offset: number, value: string) =>
    bytes.set(new TextEncoder().encode(value), offset);
  tag(0, "RIFF");
  view.setUint32(4, bytes.length - 8, true);
  tag(8, "WAVE");
  tag(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, 44100, true);
  view.setUint32(28, 88200, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  let offset = 36;
  if (padding) {
    tag(offset, "FLLR");
    view.setUint32(offset + 4, padding, true);
    offset += 8 + padding + padding % 2;
  }
  tag(offset, "data");
  view.setUint32(offset + 4, frames * 2, true);
  for (let frame = 0; frame < frames; frame++) {
    view.setInt16(offset + 8 + frame * 2, frame % 128 - 64, true);
  }
  return bytes;
}

Deno.test("prepared WAV profile accepts compact and observed Core Audio padding without mutation", () => {
  for (const padding of [0, 1, 4044, 4096]) {
    const bytes = wav(padding), saved = bytes.slice();
    validatePreparedAudioContainer(bytes);
    assertEquals(bytes, saved);
    const buffer = new Uint8Array(bytes.length + 2);
    buffer.set(bytes, 1);
    validatePreparedAudioContainer(buffer.subarray(1, 1 + bytes.length));
  }
});

Deno.test("prepared WAV profile rejects malformed PCM fields and unexamined bytes", () => {
  for (const offset of [0, 4, 8, 12, 16, 20, 22, 24, 28, 32, 34, 36, 40]) {
    const bytes = wav();
    bytes[offset] ^= 1;
    assertThrows(() => validatePreparedAudioContainer(bytes));
  }
  for (
    const bytes of [
      wav().subarray(0, 43),
      wav().subarray(0, 299),
      wav(0, 0),
      wav(4097),
      new Uint8Array(2_700_001),
    ]
  ) assertThrows(() => validatePreparedAudioContainer(bytes));
  const trailing = new Uint8Array(wav().length + 8);
  trailing.set(wav());
  new DataView(trailing.buffer).setUint32(4, trailing.length - 8, true);
  assertThrows(() => validatePreparedAudioContainer(trailing));
  for (const replacement of ["fmt ", "data", "JUNK", "LIST"]) {
    const bytes = wav(4044);
    bytes.set(new TextEncoder().encode(replacement), 36);
    assertThrows(() => validatePreparedAudioContainer(bytes));
  }
  const privatePadding = wav(4044);
  privatePadding[44] = 1;
  assertThrows(() => validatePreparedAudioContainer(privatePadding));
  const oddPadding = wav(1);
  oddPadding[45] = 1;
  assertThrows(() => validatePreparedAudioContainer(oddPadding));
});

Deno.test("prepared WAV profile enforces the exact raw-byte limit and nonempty frames", () => {
  validatePreparedAudioContainer(wav(0, 1));
  validatePreparedAudioContainer(wav(0, (2_700_000 - 44) / 2));
  assertThrows(() =>
    validatePreparedAudioContainer(wav(0, (2_700_002 - 44) / 2))
  );
});
