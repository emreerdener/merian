import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import { encodeWav16 } from "../../audio-spec/wav.ts";
import { decodeBase64 } from "../encoding.ts";
import { evidenceDigest } from "./evidence.ts";
import { initialEvidenceArtifacts } from "./initialEvidenceManifest.ts";
import {
  initialCapturePlanValue,
  parseInitialEvidenceCapturePlan,
  prepareInitialCaptureAudio,
  recoverInitialCaptureAudio,
} from "./initialEvidenceCapturePlan.ts";

const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const owner = id(1), scan = id(2), generation = id(3);
const artifact = (n: number, type = "image/jpeg", bytes = 100) => ({
  media_id: id(n),
  content_type: type,
  byte_count: bytes,
  sha256: "a".repeat(64),
});

Deno.test("capture plan round trip preserves geometry and reserved identities without hypothetical audio facts", async () => {
  const a = await audio();
  const original = request([photo(), a.item]);
  const plan = parseInitialEvidenceCapturePlan(owner, original);
  const durable = initialCapturePlanValue(plan);
  assertEquals<unknown>(durable, original);
  assertEquals(JSON.stringify(durable).includes('"prepared_media_id"'), true);
  const restored = parseInitialEvidenceCapturePlan(
    owner,
    JSON.parse(JSON.stringify(durable)),
  );
  assertEquals(restored, plan);
  assertThrows(() => initialCapturePlanValue({ ...plan }));
});

Deno.test("recovery uses exact bound server WAV output without requiring or reprocessing original audio", async () => {
  const a = await audio(), b = await audio(30);
  const plan = parseInitialEvidenceCapturePlan(
    owner,
    request([a.item, b.item]),
  );
  const initial = await prepareInitialCaptureAudio(
    plan,
    [a.read, b.read],
    signal(),
  );
  const outputs = initialEvidenceArtifacts(initial.request.evidence_manifest)
    .filter((file) => file.role === "prepared_audio").map((file) => ({
      artifact: {
        media_id: file.media_id,
        content_type: file.content_type,
        byte_count: file.byte_count,
        sha256: file.sha256,
      },
      bytes: initial.readPreparedAudio(file.media_id),
    }));
  a.read.bytes.fill(0);
  b.read.bytes.fill(0);
  const pending = recoverInitialCaptureAudio(plan, outputs, signal());
  for (const output of outputs) {
    output.bytes.fill(0);
    output.artifact.sha256 = "0".repeat(64);
  }
  const recovered = await pending;
  assertEquals(recovered.request, initial.request);
  assertEquals(recovered.audioBase64s, initial.audioBase64s);
});

Deno.test("recovery rejects missing, reordered, changed or noncanonical bound outputs without substitution", async () => {
  const a = await audio(), b = await audio(30);
  const plan = parseInitialEvidenceCapturePlan(
    owner,
    request([a.item, b.item]),
  );
  const initial = await prepareInitialCaptureAudio(
    plan,
    [a.read, b.read],
    signal(),
  );
  const outputs = initialEvidenceArtifacts(initial.request.evidence_manifest)
    .filter((file) => file.role === "prepared_audio").map((file) => ({
      artifact: {
        media_id: file.media_id,
        content_type: file.content_type,
        byte_count: file.byte_count,
        sha256: file.sha256,
      },
      bytes: initial.readPreparedAudio(file.media_id),
    }));
  const wrongHash = structuredClone(outputs);
  wrongHash[0].bytes[60] ^= 1;
  const wrongFormat = structuredClone(outputs);
  new DataView(wrongFormat[0].bytes.buffer).setUint32(24, 44_100, true);
  wrongFormat[0].artifact.sha256 = await evidenceDigest(wrongFormat[0].bytes);
  for (
    const input of [
      [],
      [outputs[0]],
      outputs.toReversed(),
      wrongHash,
      wrongFormat,
    ]
  ) {
    await assertRejects(() =>
      recoverInitialCaptureAudio(plan, input, signal())
    );
  }
  const controller = new AbortController();
  const pending = recoverInitialCaptureAudio(plan, outputs, controller.signal);
  controller.abort();
  await assertRejects(() => pending);
});
const photo = () => ({
  kind: "image",
  source: artifact(10, "image/heic", 32 * 1024 * 1024),
  prepared: artifact(11),
  coordinate_basis: "prepared_image_top_left_v1",
  focus_region: null,
  preparation: {
    schema_version: 1,
    coordinate_basis: "upright_source_top_left_v1",
    format: "nativeStillImageV1",
    crop_display_size: null,
    quarter_turns: 0,
    scale: 1,
    offset_x: 0,
    offset_y: 0,
    camera_vertical_center: null,
    source_selection: null,
  },
});
const request = (items: unknown[]) => ({
  schema_version: 1,
  scan_id: scan,
  generation,
  items,
});
function wav(activeSeconds = 1) {
  const samples = new Float32Array(44_100 * 3);
  for (let i = 0; i < activeSeconds * 44_100; i++) {
    samples[i] = 0.2 * Math.sin(2 * Math.PI * 880 * i / 44_100);
  }
  return encodeWav16(samples, 44_100);
}
async function audio(n = 20, bytes = wav()) {
  return {
    item: {
      kind: "audio",
      source: {
        ...artifact(n, "audio/wav", bytes.length),
        sha256: await evidenceDigest(bytes),
      },
      prepared_media_id: id(n + 1),
    },
    read: { mediaID: id(n), bytes },
  };
}
const signal = () => new AbortController().signal;

Deno.test("capture plan reserves server audio identity and preserves ordered mixed-media geometry", async () => {
  const a = await audio();
  for (const items of [[photo(), a.item], [a.item, photo()], [photo()]]) {
    const plan = parseInitialEvidenceCapturePlan(owner, request(items));
    assertEquals(plan.uploads.some((file) => file.media_id === id(21)), false);
    assertEquals(
      plan.uploads.find((file) => file.role === "source_image")?.byte_count,
      32 * 1024 * 1024,
    );
    const result = await prepareInitialCaptureAudio(
      plan,
      plan.audio.length ? [a.read] : [],
      signal(),
    );
    assertEquals(
      result.request.evidence_manifest.items.map((item) => item.kind),
      items.map((item) => item.kind),
    );
    const image = result.request.evidence_manifest.items.find((item) =>
      item.kind === "image"
    );
    assertEquals<unknown>(
      image?.kind === "image" ? image.preparation : null,
      photo().preparation,
    );
    if (plan.audio.length) {
      const prepared = initialEvidenceArtifacts(
        result.request.evidence_manifest,
      ).find((file) => file.role === "prepared_audio")!;
      const bytes = result.readPreparedAudio(prepared.media_id);
      assertEquals(bytes, decodeBase64(result.audioBase64s[0]));
      assertEquals(prepared.sha256, await evidenceDigest(bytes));
      assertEquals(prepared.byte_count, bytes.length);
      assertNotEquals(prepared.sha256, a.item.source.sha256);
      assertNotEquals(prepared.sha256, "0".repeat(64));
      bytes.fill(0);
      assertEquals(
        await evidenceDigest(result.readPreparedAudio(prepared.media_id)),
        prepared.sha256,
      );
    }
  }
});

Deno.test("capture audio validates complete source identity before processing and owns input across await", async () => {
  const a = await audio(), b = await audio(30);
  const plan = parseInitialEvidenceCapturePlan(
    owner,
    request([a.item, b.item]),
  );
  for (
    const reads of [[a.read], [b.read, a.read], [a.read, {
      ...b.read,
      bytes: new Uint8Array(b.read.bytes.length),
    }]]
  ) {
    await assertRejects(() =>
      prepareInitialCaptureAudio(plan, reads, signal())
    );
  }
  const pending = prepareInitialCaptureAudio(plan, [a.read, b.read], signal());
  a.read.bytes.fill(0);
  b.read.bytes.fill(0);
  const result = await pending;
  assertEquals(result.audioBase64s.length, 2);
  assertEquals(
    initialEvidenceArtifacts(result.request.evidence_manifest).filter((file) =>
      file.role === "prepared_audio"
    ).map((file) => file.media_id),
    [id(21), id(31)],
  );
  assertThrows(() => result.readPreparedAudio(id(20)));
  await assertRejects(() =>
    prepareInitialCaptureAudio({ ...plan }, [], signal())
  );
});

Deno.test("capture companion fallback derives only from a validated video node", async () => {
  const a = await audio(40, wav(0.08));
  const video = {
    kind: "video",
    source: artifact(30, "video/mp4"),
    playback: artifact(31, "video/mp4"),
    frames: [artifact(32)],
    audio: {
      source: a.item.source,
      prepared_media_id: a.item.prepared_media_id,
    },
  };
  const plan = parseInitialEvidenceCapturePlan(
    owner,
    request([photo(), video]),
  );
  const result = await prepareInitialCaptureAudio(plan, [a.read], signal());
  assertEquals(result.audioBase64s.length, 1);
  const prepared = initialEvidenceArtifacts(result.request.evidence_manifest)
    .find((file) => file.role === "prepared_companion_audio")!;
  assertEquals(prepared.byte_count, 44 + 3 * 16_000 * 2);
  await assertRejects(() =>
    prepareInitialCaptureAudio(
      parseInitialEvidenceCapturePlan(owner, request([a.item])),
      [a.read],
      signal(),
    )
  );
});

Deno.test("capture plan rejects forged prepared audio facts, aliases, historical codecs and cancellation", async () => {
  const a = await audio();
  for (
    const changed of [
      { ...a.item, prepared: artifact(21, "audio/wav") },
      { ...a.item, prepared_media_id: a.item.source.media_id },
      { ...a.item, prepared_media_id: owner },
      { ...a.item, source: { ...a.item.source, content_type: "audio/mp4" } },
    ]
  ) {
    assertThrows(() =>
      parseInitialEvidenceCapturePlan(owner, request([changed]))
    );
  }
  assertThrows(() =>
    parseInitialEvidenceCapturePlan(owner, {
      ...request([a.item]),
      evidence_digest: "0".repeat(64),
    })
  );
  const body = request([a.item]),
    plan = parseInitialEvidenceCapturePlan(owner, body);
  body.items.length = 0;
  const controller = new AbortController();
  const pending = prepareInitialCaptureAudio(plan, [a.read], controller.signal);
  controller.abort();
  await assertRejects(() => pending);
});
