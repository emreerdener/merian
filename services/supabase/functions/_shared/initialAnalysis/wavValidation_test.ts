import { assertEquals, assertThrows } from "@std/assert";
import { processWavBuffer } from "../audioProcessing.ts";
import {
  InitialWavStructureError,
  inspectInitialWavStructure,
} from "./wavValidation.ts";

function chunk(id: string, bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  const result = new Uint8Array(8 + bytes.length + bytes.length % 2);
  result.set(new TextEncoder().encode(id));
  new DataView(result.buffer).setUint32(4, bytes.length, true);
  result.set(bytes, 8);
  return result;
}

function riff(chunks: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const result = new Uint8Array(12 + chunks.reduce((n, c) => n + c.length, 0));
  result.set(new TextEncoder().encode("RIFF"));
  result.set(new TextEncoder().encode("WAVE"), 8);
  new DataView(result.buffer).setUint32(4, result.length - 8, true);
  let offset = 12;
  for (const c of chunks) {
    result.set(c, offset);
    offset += c.length;
  }
  return result;
}

function fixture(format = 1, channels = 1, rate = 16_000, frames = 8_000) {
  const bits = format === 1 ? 16 : 32;
  const fmt = new Uint8Array(16);
  const v = new DataView(fmt.buffer);
  v.setUint16(0, format, true);
  v.setUint16(2, channels, true);
  v.setUint32(4, rate, true);
  v.setUint32(8, rate * channels * bits / 8, true);
  v.setUint16(12, channels * bits / 8, true);
  v.setUint16(14, bits, true);
  const data = new Uint8Array(frames * channels * bits / 8);
  const samples = new DataView(data.buffer);
  for (let i = 0; i < frames * channels; i++) {
    if (format === 1) samples.setInt16(i * 2, 8_192, true);
    else samples.setFloat32(i * 4, 0.25, true);
  }
  return { fmt, data, bytes: riff([chunk("fmt ", fmt), chunk("data", data)]) };
}

function rejects(bytes: Uint8Array<ArrayBuffer>) {
  assertThrows(
    () => inspectInitialWavStructure(bytes),
    InitialWavStructureError,
    "Invalid initial WAV structure",
  );
}

Deno.test("initial WAV preserves PCM/float rates and channels and exact transform bytes", () => {
  for (const format of [1, 3]) {
    for (const channels of [1, 2, 3]) {
      for (const rate of [8_000, 16_000, 32_000, 44_100, 48_000, 96_000]) {
        const { bytes } = fixture(format, channels, rate, rate);
        const before = processWavBuffer(bytes.buffer, 16_000);
        const original = bytes.slice();
        const result = inspectInitialWavStructure(bytes);
        assertEquals(result.frameCount, rate);
        assertEquals(result.channels, channels);
        assertEquals(result.rate, rate);
        assertEquals(result.format, format);
        assertEquals(bytes, original);
        assertEquals(processWavBuffer(bytes.buffer, 16_000), before);
      }
    }
  }
});

Deno.test("initial WAV returns closed frozen primitives and isolates exact subarray", () => {
  const { bytes } = fixture();
  const surrounding = new Uint8Array(bytes.length + 29).fill(255);
  surrounding.set(bytes, 13);
  const view = surrounding.subarray(13, 13 + bytes.length);
  const result = inspectInitialWavStructure(view);
  assertEquals(result, {
    format: 1,
    bits: 16,
    channels: 1,
    rate: 16_000,
    blockAlign: 2,
    byteRate: 32_000,
    dataOffset: 44,
    dataLength: 16_000,
    frameCount: 8_000,
  });
  assertEquals(Object.isFrozen(result), true);
  assertEquals(
    Object.values(result).every((value) => typeof value === "number"),
    true,
  );
  rejects(surrounding);
});

Deno.test("initial WAV rejects shared backing even for valid bytes", () => {
  const { bytes } = fixture();
  const shared = new Uint8Array(new SharedArrayBuffer(bytes.length));
  shared.set(bytes);
  rejects(shared as unknown as Uint8Array<ArrayBuffer>);
});

Deno.test("initial WAV accepts bounded opaque fmt extras and odd metadata before/after data", () => {
  const { fmt, data } = fixture();
  const extended = new Uint8Array(19).fill(255);
  extended.set(fmt);
  const metadata = chunk("JUNK", new Uint8Array([1, 2, 3]));
  metadata[metadata.length - 1] = 255; // Padding need not be zero.
  const bytes = riff([
    metadata,
    chunk("fmt ", extended),
    chunk("data", data),
    metadata,
  ]);
  assertEquals(inspectInitialWavStructure(bytes).frameCount, 8_000);
  assertEquals(new DataView(bytes.buffer).getUint32(4, true) + 8, bytes.length);
  const noFinalPadding = bytes.slice(0, -1);
  new DataView(noFinalPadding.buffer).setUint32(
    4,
    noFinalPadding.length - 8,
    true,
  );
  rejects(noFinalPadding);
  const unpadded = metadata.slice(0, -1);
  rejects(riff([unpadded, chunk("fmt ", fmt), chunk("data", data)]));
});

Deno.test("initial WAV rejects every truncated prefix and inconsistent RIFF extent/signature", () => {
  const { bytes } = fixture(1, 1, 16_000, 2);
  for (let i = 0; i < bytes.length; i++) rejects(bytes.slice(0, i));
  for (const extent of [0, bytes.length - 9, bytes.length - 7, 0xffffffff]) {
    const copy = bytes.slice();
    new DataView(copy.buffer).setUint32(4, extent, true);
    rejects(copy);
  }
  for (const index of [0, 8]) {
    const copy = bytes.slice();
    copy[index] = 0;
    rejects(copy);
  }
  const trailing = new Uint8Array(bytes.length + 1);
  trailing.set(bytes);
  rejects(trailing);
  new DataView(trailing.buffer).setUint32(4, trailing.length - 8, true);
  rejects(trailing); // Partial trailing chunk header.
});

Deno.test("initial WAV rejects short fmt, missing/duplicate/misordered chunks and overflows", () => {
  const { fmt, data } = fixture();
  const f = chunk("fmt ", fmt);
  const d = chunk("data", data);
  for (const chunks of [[d], [f], [d, f], [f, f, d], [f, d, f], [f, d, d]]) {
    rejects(riff(chunks));
  }
  for (let size = 0; size < 16; size++) {
    rejects(riff([chunk("fmt ", fmt.slice(0, size)), d]));
  }
  for (const offset of [16, 40]) {
    const bytes = riff([f, d]);
    new DataView(bytes.buffer).setUint32(offset, 0xffffffff, true);
    rejects(bytes);
  }
  const badTail = chunk("JUNK", new Uint8Array(2));
  new DataView(badTail.buffer).setUint32(4, 20, true);
  rejects(riff([f, d, badTail]));
});

Deno.test("initial WAV rejects unsupported encoding and invalid frame arithmetic", () => {
  const { fmt, data } = fixture();
  const changes: [number, number, number][] = [
    [0, 2, 0],
    [0, 2, 3],
    [0, 2, 0xfffe],
    [14, 2, 8],
    [14, 2, 24],
    [2, 2, 0],
    [2, 2, 0xffff],
    [4, 4, 0],
    [4, 4, 0xffffffff],
    [8, 4, 0],
    [8, 4, 32_001],
    [12, 2, 0],
    [12, 2, 3],
  ];
  for (const [offset, width, value] of changes) {
    const copy = fmt.slice();
    const view = new DataView(copy.buffer);
    if (width === 2) view.setUint16(offset, value, true);
    else view.setUint32(offset, value, true);
    rejects(riff([chunk("fmt ", copy), chunk("data", data)]));
  }
  for (const format of [1, 3]) {
    const f = fixture(format, 3);
    for (const length of [0, 1, 2, 3, 4, 5, 7]) {
      rejects(
        riff([chunk("fmt ", f.fmt), chunk("data", f.data.slice(0, length))]),
      );
    }
  }
});

Deno.test("initial WAV rejects every nonfinite float including nonfirst and trimmable channels", () => {
  for (const value of [NaN, Infinity, -Infinity]) {
    for (const index of [0, 1, 2, 23_997, 23_998, 23_999]) {
      const { fmt, data } = fixture(3, 3);
      data.fill(0); // Samples that could otherwise disappear during silence trim.
      new DataView(data.buffer).setFloat32(index * 4, value, true);
      rejects(riff([chunk("fmt ", fmt), chunk("data", data)]));
    }
  }
  const f = fixture(3);
  new DataView(f.data.buffer).setFloat32(0, 3.4e38, true);
  assertEquals(
    inspectInitialWavStructure(
      riff([chunk("fmt ", f.fmt), chunk("data", f.data)]),
    ).format,
    3,
  );
});

Deno.test("initial WAV bounds input and permits dense metadata without a chunk-count limit", () => {
  const { fmt, data } = fixture(1, 1, 1, 1);
  const base = [chunk("fmt ", fmt), chunk("data", data)];
  const exact = riff([
    ...base,
    chunk("JUNK", new Uint8Array(2_700_000 - 46 - 8)),
  ]);
  assertEquals(exact.length, 2_700_000);
  assertEquals(inspectInitialWavStructure(exact).frameCount, 1);
  const oversized = riff([
    ...base,
    chunk("JUNK", new Uint8Array(2_700_000 - 46 - 6)),
  ]);
  rejects(oversized);
  const dense = riff([
    ...Array.from({ length: 5_000 }, () => chunk("JUNK", new Uint8Array())),
    ...base,
  ]);
  assertEquals(inspectInitialWavStructure(dense).rate, 1);
});
