import { assertEquals, assertRejects } from "@std/assert";
import { evidenceDigest } from "./evidence.ts";
import { verifyPreparedVideoSource } from "./retainedVideoContainer.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const corpus = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/retained-video-variants.json", import.meta.url),
  ),
);
const decode = (base64: string) =>
  Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
function manifest(
  bytes: Uint8Array,
  sha256: string,
  duration: number,
  audio: boolean,
) {
  const artifact = (n: number, content_type: string, byte_count = 100) => ({
    media_id: id(n),
    content_type,
    byte_count,
    sha256: "a".repeat(64),
  });
  return {
    schema_version: 4,
    descriptions: ["Synthetic fixture"],
    provenance: {
      schema_version: 1,
      preprocessing_version: "retained_clip_v1",
      source: { ...artifact(3, "video/mp4", bytes.length), sha256 },
      parameters: {
        timescale: 600,
        frame_pipeline: "direct_inference_v1",
        decode_long_edge: 2048,
        duration_ticks: duration,
        sampling: "five_interior_v1",
        preferred_track_transform: true,
        crop: "square_v1",
        crop_center_basis_points: 5000,
        inference_long_edge: 768,
        encoding_quality_percent: 85,
      },
      frames: Array.from({ length: 5 }, (_, index) => {
        const time = Math.min(
          Math.max(Math.round(duration * (1 + 2 * index) / 10), 30),
          duration - 30,
        );
        return {
          index,
          source_media_id: id(3),
          requested_time_ticks: time,
          actual_time_ticks: time,
          artifact: artifact(index + 4, "image/jpeg"),
        };
      }),
      audio: audio
        ? {
          source_media_id: id(3),
          track: "first_audio_track",
          start_ticks: 0,
          end_ticks: duration,
          sample_rate: 44100,
          sample_count: duration * 44100 / 600,
          channels: 1,
          bits_per_sample: 16,
          encoding: "pcm_s16le",
          artifact: artifact(9, "audio/wav", 44 + duration * 44100 / 600 * 2),
        }
        : null,
    },
  };
}
const verify = (value: unknown, bytes: Uint8Array) =>
  verifyPreparedVideoSource(value, id(1), id(2), bytes);
Deno.test("retained source binds unchanged native corpus and returns independent exact bytes", async () => {
  for (const row of corpus) {
    const bytes = decode(row.base64), before = bytes.slice();
    const value = manifest(bytes, row.sha256, row.durationTicks, row.hasAudio);
    const padded = new Uint8Array(bytes.length + 8);
    padded.set(bytes, 4);
    const output = await verify(value, padded.subarray(4, -4));
    assertEquals(output, before);
    output.fill(0);
    assertEquals(padded.subarray(4, -4), before);
  }
});
Deno.test("retained source rejects wrong length, digest, MIME, duration and audio association", async () => {
  for (const row of corpus) {
    const bytes = decode(row.base64);
    const value = manifest(bytes, row.sha256, row.durationTicks, row.hasAudio);
    await assertRejects(() => verify(value, bytes.subarray(1)));
    const digest = structuredClone(value);
    digest.provenance.source.sha256 = "b".repeat(64);
    await assertRejects(() => verify(digest, bytes));
    const mime = structuredClone(value);
    mime.provenance.source.content_type = "audio/mp4";
    await assertRejects(() => verify(mime, bytes));
    const otherDuration = row.durationTicks === 60 ? 3000 : 60;
    await assertRejects(() =>
      verify(manifest(bytes, row.sha256, otherDuration, row.hasAudio), bytes)
    );
    await assertRejects(() =>
      verify(
        manifest(bytes, row.sha256, row.durationTicks, !row.hasAudio),
        bytes,
      )
    );
    const changed = bytes.slice();
    changed[changed.length - 1] ^= 1;
    await assertRejects(() => verify(value, changed));
  }
});
Deno.test("retained source snapshots manifest and bytes synchronously before hashing", async () => {
  const row = corpus[0], bytes = decode(row.base64), before = bytes.slice();
  const value = manifest(bytes, row.sha256, row.durationTicks, row.hasAudio);
  const pending = verify(value, bytes);
  bytes.fill(0);
  value.provenance.source.sha256 = "b".repeat(64);
  value.provenance.parameters.duration_ticks = 60;
  value.provenance.audio = null;
  value.provenance.frames.reverse();
  value.descriptions.push("Changed");
  assertEquals(await pending, before);
});
Deno.test("retained source rejects malformed structure even with matching digest and length", async () => {
  const row = corpus[0], bytes = decode(row.base64);
  bytes[4] = 0; // Corrupt ftyp box name; no envelope-only fallback.
  const sha256 = await evidenceDigest(bytes);
  await assertRejects(() =>
    verify(manifest(bytes, sha256, row.durationTicks, row.hasAudio), bytes)
  );
});
Deno.test("retained source rejects malformed metadata and colliding scope identities", async () => {
  const row = corpus[0], bytes = decode(row.base64);
  const value = manifest(bytes, row.sha256, row.durationTicks, row.hasAudio);
  await assertRejects(() => verify({ ...value, schema_version: 3 }, bytes));
  await assertRejects(() =>
    verifyPreparedVideoSource(value, id(3), id(2), bytes)
  );
  await assertRejects(() =>
    verifyPreparedVideoSource(value, id(1), id(1), bytes)
  );
  const tooLarge = structuredClone(value);
  tooLarge.provenance.source.byte_count = 12 * 1024 * 1024 + 1;
  await assertRejects(() => verify(tooLarge, bytes));
});
