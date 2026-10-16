import { assertEquals, assertRejects } from "@std/assert";
import { evidenceDigest } from "./evidence.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import { verifyPreparedVideoAudio } from "./videoAudioContainer.ts";

const vectors = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/video-request-v4.json", import.meta.url),
  ),
);
const request = parsePreparedVideoAdmission(vectors[0].input);

function wav(padding = 0, samples = 128): Uint8Array {
  const bytes = new Uint8Array(44 + samples * 2 + (padding ? padding + 8 : 0));
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
  if (padding) {
    tag(36, "FLLR");
    view.setUint32(40, padding, true);
  }
  const offset = bytes.length - samples * 2 - 8;
  tag(offset, "data");
  view.setUint32(offset + 4, samples * 2, true);
  return bytes;
}

async function manifest(bytes: Uint8Array, samples = 128) {
  const saved = request.evidence_manifest;
  const original = saved.provenance.audio!;
  return {
    ...saved,
    provenance: {
      ...saved.provenance,
      audio: {
        ...original,
        start_ticks: 0,
        end_ticks: 2,
        sample_count: samples,
        artifact: {
          ...original.artifact,
          byte_count: bytes.length,
          sha256: await evidenceDigest(bytes),
        },
      },
    },
  };
}
const verify = (value: unknown, bytes: Uint8Array) =>
  verifyPreparedVideoAudio(
    value,
    request.observation_id,
    request.analysis_id,
    bytes,
  );

Deno.test("video companion verifies compact and padded WAV without treating padding as samples", async () => {
  for (const padding of [0, 4044, 4096]) {
    const bytes = wav(padding);
    const verified = await verify(await manifest(bytes), bytes);
    assertEquals(verified, bytes);
    verified[verified.length - 1] = 1;
    assertEquals(bytes[bytes.length - 1], 0);
  }
});

Deno.test("video companion rejects plausible metadata count when actual PCM count differs", async () => {
  const bytes = wav(4044);
  // Both claims pass duration tolerance and lower byte bound. Padding cannot
  // disguise the difference between declared frames and the data chunk.
  for (const count of [127, 129]) {
    const value = await manifest(bytes, count);
    await assertRejects(() => verify(value, bytes));
  }
});

Deno.test("video companion rejects missing audio, malformed bytes and digest or length mismatch", async () => {
  const bytes = wav();
  const value = await manifest(bytes);
  await assertRejects(() =>
    verify(
      { ...value, provenance: { ...value.provenance, audio: null } },
      bytes,
    )
  );
  await assertRejects(() => verify(value, bytes.subarray(0, bytes.length - 1)));
  const changed = bytes.slice();
  changed[changed.length - 1] = 1;
  await assertRejects(() => verify(value, changed));
  const malformed = bytes.slice();
  malformed[22] = 2;
  await assertRejects(async () => verify(await manifest(malformed), malformed));
});

Deno.test("video companion owns bytes and manifest across the digest await", async () => {
  const bytes = wav();
  const value = await manifest(bytes);
  const expected = bytes.slice();
  const pending = verify(value, bytes);
  bytes.fill(255);
  value.provenance.audio.sample_count = 129;
  value.provenance.audio.artifact.sha256 = "b".repeat(64);
  assertEquals(await pending, expected);
});
