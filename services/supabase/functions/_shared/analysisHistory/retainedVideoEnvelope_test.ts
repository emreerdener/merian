import { assertEquals, assertThrows } from "@std/assert";
import { MEDIA_BUDGETS } from "../mediaBudgets.ts";
import { inspectRetainedVideoEnvelope } from "./retainedVideoEnvelope.ts";

const fixtures = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/retained-video-envelopes.json", import.meta.url),
  ),
);
const decode = (value: string) =>
  Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
function join(...parts: Uint8Array[]) {
  const result = new Uint8Array(
    parts.reduce((sum, part) => sum + part.length, 0),
  );
  let at = 0;
  for (const part of parts) {
    result.set(part, at);
    at += part.length;
  }
  return result;
}
function box(type: string, payload = new Uint8Array([42]), extended = false) {
  const header = extended ? 16 : 8;
  const bytes = new Uint8Array(header + payload.length);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, extended ? 1 : bytes.length);
  bytes.set(new TextEncoder().encode(type), 4);
  if (extended) view.setBigUint64(8, BigInt(bytes.length));
  bytes.set(payload, header);
  return bytes;
}
const shape = (...extra: Uint8Array[]) =>
  join(box("ftyp"), box("moov"), ...extra, box("mdat"));

Deno.test("retained envelope inspects actual silent/audio native output and nonzero byte offsets", () => {
  assertEquals(fixtures.map((v: { audio: boolean }) => v.audio), [false, true]);
  for (const fixture of fixtures) {
    const bytes = decode(fixture.base64);
    const result = inspectRetainedVideoEnvelope(bytes);
    assertEquals(result, fixture.boxes);
    assertEquals(Object.isFrozen(result), true);
    for (const item of result) assertEquals(Object.isFrozen(item), true);
    const padded = join(new Uint8Array(3), bytes, new Uint8Array(5));
    assertEquals(inspectRetainedVideoEnvelope(padded.subarray(3, -5)), result);
    bytes.fill(0);
    assertEquals(result, fixture.boxes); // Returned ranges never alias input bytes.
  }
});
Deno.test("retained envelope supports bounded extended headers and padding boxes", () => {
  const bytes = join(
    box("ftyp", undefined, true),
    box("free", new Uint8Array()),
    box("moov", undefined, true),
    box("wide", new Uint8Array()),
    box("mdat", undefined, true),
  );
  assertEquals(inspectRetainedVideoEnvelope(bytes).map((v) => v.type), [
    "ftyp",
    "free",
    "moov",
    "wide",
    "mdat",
  ]);
});
Deno.test("retained envelope rejects zero, short, oversized and unsafe extended sizes", () => {
  for (const size of [0, 2, 7, 0xffff_ffff]) {
    const bytes = shape();
    new DataView(bytes.buffer).setUint32(0, size);
    assertThrows(() => inspectRetainedVideoEnvelope(bytes));
  }
  for (const size of [0n, 8n, 15n, 9007199254740993n, 0xffff_ffff_ffff_ffffn]) {
    const bytes = join(box("ftyp", undefined, true), box("moov"), box("mdat"));
    new DataView(bytes.buffer).setBigUint64(8, size);
    assertThrows(() => inspectRetainedVideoEnvelope(bytes));
  }
});
Deno.test("retained envelope rejects incomplete sequences, excessive allocation and box count", () => {
  const bytes = decode(fixtures[0].base64);
  for (const length of [0, 1, 7, 8, 12, bytes.length - 1]) {
    assertThrows(() => inspectRetainedVideoEnvelope(bytes.subarray(0, length)));
  }
  for (let count = 1; count < 8; count++) {
    assertThrows(() =>
      inspectRetainedVideoEnvelope(join(bytes, new Uint8Array(count)))
    );
  }
  assertThrows(() =>
    inspectRetainedVideoEnvelope(
      new Uint8Array(MEDIA_BUDGETS.maxVideoRawBytes + 1),
    )
  );
  const pads = Array.from({ length: 29 }, () => box("free", new Uint8Array()));
  assertEquals(inspectRetainedVideoEnvelope(shape(...pads)).length, 32);
  assertThrows(() => inspectRetainedVideoEnvelope(shape(...pads, box("free"))));
  const extended = box("mdat", undefined, true).subarray(0, 12);
  assertThrows(() =>
    inspectRetainedVideoEnvelope(join(box("ftyp"), box("moov"), extended))
  );
});
Deno.test("retained envelope requires unique nonempty core boxes, ftyp first and closed top-level types", () => {
  for (const type of ["ftyp", "moov", "mdat"]) {
    assertThrows(() => inspectRetainedVideoEnvelope(shape(box(type))));
    const types = ["ftyp", "moov", "mdat"];
    assertThrows(() =>
      inspectRetainedVideoEnvelope(
        join(...types.filter((v) => v !== type).map((v) => box(v))),
      )
    );
    assertThrows(() =>
      inspectRetainedVideoEnvelope(
        join(
          ...types.map((v) =>
            box(v, v === type ? new Uint8Array() : undefined)
          ),
        ),
      )
    );
  }
  assertThrows(() => inspectRetainedVideoEnvelope(join(box("free"), shape())));
  for (const type of ["uuid", "moof", "sidx", "junk"]) {
    assertThrows(() => inspectRetainedVideoEnvelope(shape(box(type))));
  }
});
Deno.test("envelope inspection deliberately leaves nested payload semantics opaque", () => {
  // This is NOT valid media. A successful envelope inspection must never be used
  // as a substitute for the pending nested track/sample/reference validator.
  assertEquals(inspectRetainedVideoEnvelope(shape()).length, 3);
});
