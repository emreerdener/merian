import { assertEquals, assertThrows } from "@std/assert";
import { inspectRetainedVideoStructure } from "./retainedVideoStructure.ts";

const fixtures = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/retained-video-envelopes.json", import.meta.url),
  ),
);
const source = (audio = true): Uint8Array =>
  Uint8Array.from(atob(fixtures[audio ? 1 : 0].base64), (c) => c.charCodeAt(0));
Deno.test("nested retained profile inspects actual silent/audio native fixtures with AAC priming", () => {
  for (const audio of [false, true]) {
    const bytes = source(audio), result = inspectRetainedVideoStructure(bytes);
    assertEquals(result, {
      width: 64,
      height: 64,
      durationTicks: 600,
      hasAudio: audio,
    });
    assertEquals(Object.isFrozen(result), true);
    const padded = new Uint8Array(bytes.length + 4);
    padded.set(bytes, 2);
    assertEquals(inspectRetainedVideoStructure(padded.subarray(2, -2)), result);
    bytes.fill(0);
    assertEquals(result.width, 64);
  }
  const bytes = source(), v = new DataView(bytes.buffer);
  // Fixture-backed compatibility facts; template channels are not ASC channels.
  assertEquals(v.getUint16(1210 + 16), 2);
  assertEquals(v.getUint32(1009 + 12), 2112);
  assertEquals(v.getUint32(909 + 20), 599);
});
// Absolute offsets belong to the immutable imported audio fixture; mutations
// deliberately do not use the production parser to locate their own targets.
const changes: [string, number, number, number][] = [
  ["brand", 8, 1, 0],
  ["movie flags", 44, 4, 1],
  ["movie timescale", 56, 4, 0],
  ["movie duration", 60, 4, 3001],
  ["movie matrix", 80, 4, 0],
  ["next track ID", 140, 4, 1],
  ["duplicate track ID", 921, 4, 1],
  ["track duration", 929, 4, 601],
  ["video transform scale", 200, 4, 131072],
  ["audio transform", 949, 4, 0],
  ["video media scale", 308, 4, 0],
  ["audio media scale", 1057, 4, 48000],
  ["media duration", 1061, 4, 0],
  ["language reserved", 1065, 4, 0],
  ["edit count", 1013, 4, 2],
  ["edit duration", 1017, 4, 600],
  ["edit negative time", 1021, 4, 0xffffffff],
  ["edit exceeds media", 1021, 4, 4096],
  ["edit rate", 1025, 4, 0],
  ["handler type", 1085, 4, 0x74657874],
  ["handler text", 1101, 1, 0],
  ["video media flags", 385, 4, 0],
  ["reference count", 1162, 4, 2],
  ["external URL flag", 1174, 4, 0],
  ["video data reference", 471, 2, 2],
  ["audio data reference", 1216, 2, 2],
  ["odd dimensions", 489, 2, 65],
  ["track dimensions mismatch", 236, 4, 128 * 65536],
  ["compressor metadata", 507, 1, 1],
  ["audio ASC stereo", 1282, 1, 0x10],
  ["audio template rate", 1234, 4, 48000 * 65536],
  ["SPS profile", 552, 1, 100],
  ["SPS overflow", 557, 2, 65535],
  ["NAL length", 555, 1, 0xfe],
  ["color extension", 602, 1, 1],
  ["color full range", 602, 1, 128],
  ["color primaries", 596, 2, 1],
  ["color transfer", 598, 2, 6],
  ["color matrix", 600, 2, 1],
  ["audio sample duration", 1363, 4, 512],
  ["pixel aspect", 611, 4, 2],
  ["time count", 635, 4, 31],
  ["time delta", 639, 4, 0],
  ["sample count", 749, 4, 601],
  ["sample length", 753, 4, 0],
  ["chunk description", 729, 4, 2],
  ["first chunk", 721, 4, 0],
  ["chunk outside mdat", 889, 4, 0],
  ["overlapping track bytes", 889, 4, 1651],
  ["sync index", 663, 4, 31],
  ["dependency reserved", 675, 1, 255],
  ["roll grouping", 1301, 4, 0],
  ["roll distance", 1313, 2, 0],
  ["roll mapping count", 1335, 4, 45],
  ["roll description", 1339, 4, 2],
];
Deno.test("nested retained profile rejects forged declarations and sample accounting", async (t) => {
  for (const [name, offset, size, value] of changes) {
    await t.step(name, () => {
      const bytes = source(), v = new DataView(bytes.buffer);
      if (size === 1) v.setUint8(offset, value);
      else if (size === 2) v.setUint16(offset, value);
      else v.setUint32(offset, value);
      assertThrows(() => inspectRetainedVideoStructure(bytes));
    });
  }
});
Deno.test("nested retained profile rejects wrong placement, metadata, fragmented and unsupported tables", () => {
  for (
    const [offset, tag] of [
      [584, "meta"],
      [397, "tref"],
      [873, "co64"],
      [619, "ctts"],
      [1289, "uuid"],
      [152, "moof"],
    ] as const
  ) {
    const bytes = source();
    bytes.set(new TextEncoder().encode(tag), offset + 4);
    assertThrows(() => inspectRetainedVideoStructure(bytes));
  }
});
Deno.test("nested retained profile rejects malformed nested box extents and versions", () => {
  for (
    const [offset, size] of [
      [36, 1],
      [36, 0],
      [36, 7],
      [36, 0xffffffff],
      [36, 107],
      [1238, 50],
      [901, 743],
    ] as const
  ) {
    const bytes = source();
    new DataView(bytes.buffer).setUint32(offset, size);
    assertThrows(() => inspectRetainedVideoStructure(bytes));
  }
  for (const offset of [44, 160, 260, 296, 627, 741, 1246, 1323]) {
    const bytes = source();
    bytes[offset] = 2;
    assertThrows(() => inspectRetainedVideoStructure(bytes));
  }
});
Deno.test("nested retained profile rejects opaque-envelope-only fixtures and excessive nested boxes", () => {
  const bytes = source();
  bytes.fill(0, 36, 1635);
  assertThrows(() => inspectRetainedVideoStructure(bytes));
  const count = 129,
    extra = new Uint8Array(count * 8),
    view = new DataView(extra.buffer);
  for (let i = 0; i < count; i++) {
    view.setUint32(i * 8, 8);
    extra.set(new TextEncoder().encode("trak"), i * 8 + 4);
  }
  const original = source(),
    enlarged = new Uint8Array(original.length + extra.length);
  enlarged.set(original.subarray(0, 1635));
  enlarged.set(extra, 1635);
  enlarged.set(original.subarray(1635), 1635 + extra.length);
  new DataView(enlarged.buffer).setUint32(28, 1607 + extra.length);
  assertThrows(() => inspectRetainedVideoStructure(enlarged));
});
