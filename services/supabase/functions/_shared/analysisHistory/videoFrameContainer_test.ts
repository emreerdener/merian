import { assertEquals, assertRejects } from "@std/assert";
import { evidenceDigest } from "./evidence.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import { verifyPreparedVideoFrame } from "./videoFrameContainer.ts";

const vectors = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/video-request-v4.json", import.meta.url),
  ),
);
const request = parsePreparedVideoAdmission(vectors[0].input);
const native = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/video-frame-containers.json", import.meta.url),
  ),
);
function decode(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}
async function manifest(bytes: Uint8Array, type = "image/jpeg", edge = 768) {
  const saved = request.evidence_manifest;
  const value = {
    ...saved,
    provenance: {
      ...saved.provenance,
      parameters: { ...saved.provenance.parameters, inference_long_edge: edge },
      frames: saved.provenance.frames.map((frame) => ({
        ...frame,
        artifact: { ...frame.artifact },
      })),
    },
  };
  value.provenance.frames[0].artifact = {
    ...value.provenance.frames[0].artifact,
    content_type: type,
    byte_count: bytes.length,
    sha256: await evidenceDigest(bytes),
  };
  return value;
}
const verify = (value: unknown, bytes: Uint8Array, index = 0) =>
  verifyPreparedVideoFrame(
    value,
    request.observation_id,
    request.analysis_id,
    index,
    bytes,
  );
const joined = (...parts: Uint8Array[]) => {
  const bytes = new Uint8Array(
    parts.reduce((sum, part) => sum + part.length, 0),
  );
  let at = 0;
  for (const part of parts) {
    bytes.set(part, at);
    at += part.length;
  }
  return bytes;
};
function chunk(type: string, payload: Uint8Array) {
  const bytes = new Uint8Array(8 + payload.length + payload.length % 2);
  bytes.set(new TextEncoder().encode(type));
  new DataView(bytes.buffer).setUint32(4, payload.length, true);
  bytes.set(payload, 8);
  return bytes;
}
function riff(...chunks: Uint8Array[]) {
  const header = new Uint8Array(12);
  header.set(new TextEncoder().encode("RIFF"));
  header.set(new TextEncoder().encode("WEBP"), 8);
  const bytes = joined(header, ...chunks);
  new DataView(bytes.buffer).setUint32(4, bytes.length - 8, true);
  return bytes;
}
// Structural synthetic containers, deliberately not claims of pixel-decodable bitstreams.
function webp(lossless: boolean, extended = false) {
  const payload = new Uint8Array(lossless ? 8 : 14);
  const v = new DataView(payload.buffer);
  if (lossless) {
    payload[0] = 0x2f;
    v.setUint32(1, 767 | (767 << 14), true);
  } else {
    payload.set([0x30, 0, 0, 0x9d, 1, 0x2a]);
    v.setUint16(6, 768, true);
    v.setUint16(8, 768, true);
  }
  const image = chunk(lossless ? "VP8L" : "VP8 ", payload);
  const extra = new Uint8Array(10);
  extra.set([255, 2, 0, 255, 2, 0], 4);
  return extended ? riff(chunk("VP8X", extra), image) : riff(image);
}

Deno.test("video frame accepts captured native JPEG and reference WebP containers unchanged and owns copied bytes", async () => {
  for (const vector of native) {
    const bytes = decode(vector.base64), before = bytes.slice();
    const value = await manifest(bytes, vector.content_type, vector.edge);
    const output = await verify(value, bytes);
    assertEquals(output, before);
    output[0] ^= 1;
    assertEquals(bytes, before);
  }
});
Deno.test("video frame binds exact index, scope separation, digest, MIME and square dimensions", async () => {
  const bytes = decode(native[0].base64), value = await manifest(bytes);
  for (const index of [-1, 5, 0.5, NaN]) {
    await assertRejects(() => verify(value, bytes, index));
  }
  await assertRejects(() => verify(value, bytes, 1));
  await assertRejects(() =>
    verifyPreparedVideoFrame(
      value,
      value.provenance.source.media_id,
      request.analysis_id,
      0,
      bytes,
    )
  );
  const changed = bytes.slice();
  changed[changed.length - 3] ^= 1;
  await assertRejects(() => verify(value, changed));
  await assertRejects(() => verify(value, bytes.subarray(0, bytes.length - 1)));
  await assertRejects(() =>
    verify(withContentType(value, "image/webp"), bytes)
  );
  await assertRejects(() =>
    verify({
      ...value,
      provenance: {
        ...value.provenance,
        parameters: {
          ...value.provenance.parameters,
          inference_long_edge: 1024,
        },
      },
    }, bytes)
  );
});
function withContentType(
  value: Awaited<ReturnType<typeof manifest>>,
  type: string,
) {
  const copy = structuredClone(value);
  copy.provenance.frames[0].artifact.content_type = type;
  return copy;
}
Deno.test("private JPEG rejects metadata changes, truncation, segment overflow and trailing data", async () => {
  const bytes = decode(native[0].base64);
  const overflow = bytes.slice();
  overflow[4] = 255;
  overflow[5] = 255;
  const metadata = bytes.slice();
  metadata[12] ^= 1;
  for (
    const damaged of [
      bytes.subarray(0, bytes.length - 1),
      joined(bytes, new Uint8Array([0])),
      overflow,
      metadata,
    ]
  ) {
    const value = await manifest(damaged);
    await assertRejects(() => verify(value, damaged));
  }
});
Deno.test("private JPEG rejects changed and duplicated EXIF and IPTC segments", async () => {
  const bytes = decode(native[0].base64);
  const view = new DataView(bytes.buffer);
  for (const marker of [0xe1, 0xed]) {
    let start = 2;
    while (bytes[start + 1] !== marker) {
      start += 2 + view.getUint16(start + 2);
      if (start >= bytes.length) {
        throw new Error("Missing native metadata fixture");
      }
    }
    const end = start + 2 + view.getUint16(start + 2);
    const changed = bytes.slice();
    changed[end - 1] ^= 1;
    const duplicate = joined(
      bytes.subarray(0, end),
      bytes.subarray(start, end),
      bytes.subarray(end),
    );
    for (const damaged of [changed, duplicate]) {
      const value = await manifest(damaged);
      await assertRejects(() => verify(value, damaged));
    }
  }
});
Deno.test("private WebP bounds simple and extended opaque still-image containers", async () => {
  for (const lossless of [false, true]) {
    for (const extended of [false, true]) {
      const bytes = webp(lossless, extended);
      assertEquals(
        await verify(await manifest(bytes, "image/webp"), bytes),
        bytes,
      );
    }
  }
});
Deno.test("private WebP rejects animation, metadata, duplicate images, bad size and dimensions", async () => {
  const valid = webp(false),
    wrongSize = valid.slice(),
    wrongEdge = valid.slice(),
    badPartition = valid.slice();
  new DataView(wrongSize.buffer).setUint32(4, 0xffff_ffff, true);
  wrongEdge[26] = 1;
  badPartition[20] = 0;
  const extended = webp(false, true);
  extended[20] = 2;
  const image = valid.subarray(12);
  for (
    const bytes of [
      wrongSize,
      wrongEdge,
      badPartition,
      extended,
      valid.subarray(0, valid.length - 1),
      joined(valid, new Uint8Array([0])),
      riff(image, image),
      riff(chunk("ANIM", new Uint8Array(6)), image),
      riff(image, chunk("EXIF", new Uint8Array(4))),
    ]
  ) {
    const value = await manifest(bytes, "image/webp");
    await assertRejects(() => verify(value, bytes));
  }
});
Deno.test("video frame snapshots manifest and bytes before digest awaits", async () => {
  const bytes = decode(native[0].base64),
    expected = bytes.slice(),
    value = await manifest(bytes);
  const pending = verify(value, bytes);
  bytes.fill(0);
  value.provenance.frames[0].artifact.sha256 = "0".repeat(64);
  assertEquals(await pending, expected);
});
