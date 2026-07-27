import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { calculateCrc32, combineCrc32, combineCrc32Parts } from "./crc32.ts";

const encoder = new TextEncoder();

Deno.test("CRC32 matches the standard check vector", () => {
  assertEquals(calculateCrc32(encoder.encode("123456789")), 0xcbf4_3926);
});

Deno.test("chunk CRC composition equals a direct concatenated CRC", () => {
  const chunks = [
    encoder.encode("occurrenceID,scientificName\n"),
    encoder.encode("scan-1,Danaus plexippus\n"),
    encoder.encode("scan-2,Quercus rubra\n"),
  ];
  const complete = encoder.encode(
    chunks.map((chunk) => new TextDecoder().decode(chunk)).join(""),
  );
  const digest = combineCrc32Parts(
    chunks.map((chunk) => ({
      crc32: calculateCrc32(chunk),
      byteCount: chunk.byteLength,
    })),
  );

  assertEquals(digest, {
    crc32: calculateCrc32(complete),
    byteCount: complete.byteLength,
  });
});

Deno.test("CRC composition handles empty prefixes and suffixes", () => {
  const content = encoder.encode("content");
  const contentCrc = calculateCrc32(content);
  assertEquals(combineCrc32(0, contentCrc, content.byteLength), contentCrc);
  assertEquals(combineCrc32(contentCrc, 0, 0), contentCrc);
});

Deno.test("cached byte operators cover the safe byte-count range", () => {
  const vectors: Array<[number, number]> = [
    [1, 0xc470_13a8],
    [33, 0x6d88_55a1],
    [512 * 1024, 0x911b_b6a5],
    [16 * 1024 * 1024, 0xaeb7_97ef],
    [2 ** 32, 0xc470_13a8],
    [Number.MAX_SAFE_INTEGER, 0xc376_625a],
  ];
  for (const [secondByteCount, expected] of vectors) {
    assertEquals(
      combineCrc32(0x1234_5678, 0x9abc_def0, secondByteCount),
      expected,
    );
  }
});

Deno.test("CRC composition rejects unsafe durable metadata", () => {
  assertThrows(() => combineCrc32(-1, 0, 0), TypeError);
  assertThrows(() => combineCrc32(0, 0x1_0000_0000, 0), TypeError);
  assertThrows(() => combineCrc32(0, 0, -1), TypeError);
  assertThrows(() => combineCrc32(0, 1, 0), TypeError);
  assertThrows(
    () =>
      combineCrc32Parts([{
        crc32: 0,
        byteCount: Number.MAX_SAFE_INTEGER + 1,
      }]),
    TypeError,
  );
});
