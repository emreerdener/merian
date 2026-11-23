import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  captureSourceObservationsForIntent,
  type CaptureSourceRead,
  type CaptureSourceSnapshots,
  captureSourceSnapshots,
} from "./captureSourceEvidence.ts";
import { captureObjectBackendDigest } from "./captureObjectRetirement.ts";
import { buildScanIngestionIntent } from "./scanIngestionIntents.ts";
import {
  MEDIA_BUDGETS,
  STAGING_ALLOWED_CONTENT_TYPES,
} from "./mediaBudgets.ts";
import type { MultimodalPayload } from "./identify/types.ts";

const owner = "00000000-0000-4000-8000-000000000001";
const backend = {
  endpoint: "https://synthetic.r2.cloudflarestorage.com",
  bucketName: "synthetic-capture",
};
const key = (name: string) => `staging/${owner}/${name}`;
const read = (
  kind: "image" | "audio" | "video",
  name: string = kind,
): CaptureSourceRead => ({
  sourceKey: key(name),
  kind,
  contentType: kind === "image"
    ? "image/jpeg"
    : kind === "audio"
    ? "audio/wav"
    : "video/mp4",
  bytes: new Uint8Array([1, 2, 3]),
});
const counts = {
  image_count: 1,
  audio_count: 1,
  video_count: 1,
  required_video_count: 1,
  video_frame_count: 0,
};
const mediaKeys = {
  image: [key("image")],
  audio: [key("audio")],
  video: [key("video")],
};
const scanId = "00000000-0000-4000-8000-000000000002";

Deno.test("source evidence and provider preparation use frozen identical bytes for all media", async () => {
  const image = read("image"), audio = read("audio"), video = read("video");
  const reads = [image, audio, video];
  const config = { ...backend };
  const pending = captureSourceSnapshots(owner, config, reads);
  image.bytes.fill(9);
  audio.bytes.fill(8);
  video.bytes.fill(7);
  config.bucketName = "replacement";
  reads.splice(0, reads.length, read("image", "replacement"));
  const snapshot = await pending;
  assertEquals(snapshot.observations.version, 1);
  for (const item of snapshot.observations.items) {
    assertEquals(
      item.sha256,
      "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
    );
    assertEquals(item.byteCount, 3);
    assertEquals(item.backendSHA256, await captureObjectBackendDigest(backend));
  }
  assertEquals(snapshot.imageBase64s(), ["AQID"]);
  const returned = snapshot.audioBuffers();
  new Uint8Array(returned[0]).fill(0);
  assertEquals([...new Uint8Array(snapshot.audioBuffers()[0])], [1, 2, 3]);
  for (const item of snapshot.observations.items) {
    const isolated = snapshot.sourceBytes(item.sourceKey);
    assertEquals([...isolated], [1, 2, 3]);
    isolated.fill(0);
    assertEquals([...snapshot.sourceBytes(item.sourceKey)], [1, 2, 3]);
  }
  assertThrows(() => snapshot.sourceBytes(key("missing")));
  assertThrows(() => snapshot.sourceBytes("staging/other/image"));
  assertThrows(() =>
    Object.assign(snapshot.observations.items[0], { sha256: "f".repeat(64) })
  );
  assertThrows(() => Object.assign(snapshot, { ownerId: "replacement" }));
  assertEquals(
    captureSourceObservationsForIntent(snapshot, mediaKeys),
    snapshot.observations,
  );
});

Deno.test("source evidence rejects malformed, duplicate, foreign and excessive reads", async (t) => {
  const invalidReads: unknown[] = [
    [],
    [read("image"), read("image")],
    [{ ...read("image"), sourceKey: "staging/other/image" }],
    [{ ...read("image"), sourceKey: key("../image") }],
    [{ ...read("image"), kind: "__proto__" }],
    [{ ...read("image"), kind: { toString: () => "image" } }],
    [{ ...read("image"), contentType: "audio/wav" }],
    [{ ...read("image"), bytes: new Uint8Array() }],
    [{ ...read("image"), bytes: new Uint8Array(new SharedArrayBuffer(3)) }],
    [{ ...read("image"), sha256: "f".repeat(64) }],
    [{
      ...read("audio"),
      bytes: new Uint8Array(MEDIA_BUDGETS.maxAudioRawBytes + 1),
    }],
    [{
      ...read("video"),
      bytes: new Uint8Array(MEDIA_BUDGETS.maxVideoRawBytes + 1),
    }],
    [{
      ...read("image"),
      bytes: new Uint8Array(MEDIA_BUDGETS.maxImageRawBytes),
    }, read("image", "extra")],
    Array.from({ length: 6 }, (_, i) => read("image", `image${i}`)),
    Array.from({ length: 3 }, (_, i) => read("audio", `audio${i}`)),
    Array.from({ length: 2 }, (_, i) => read("video", `video${i}`)),
  ];
  for (const [index, value] of invalidReads.entries()) {
    await t.step(`invalid reads ${index}`, async () => {
      await assertRejects(() =>
        captureSourceSnapshots(owner, backend, value as CaptureSourceRead[])
      );
    });
  }
  for (
    const endpoint of [
      "http://example.test",
      "https://example.test/path",
      "https://user:pass@example.test",
      "https://example.test?q=x",
    ]
  ) {
    await assertRejects(() =>
      captureSourceSnapshots(owner, { ...backend, endpoint }, [read("image")])
    );
  }
  await assertRejects(() =>
    captureSourceSnapshots("not-owner", backend, [read("image")])
  );
  await assertRejects(() =>
    captureSourceSnapshots(owner, {
      ...backend,
      bucketName: { toString: () => "synthetic-capture" } as unknown as string,
    }, [read("image")])
  );
});

Deno.test("intent accepts only process-local snapshots with exact complete ordered membership", async () => {
  const snapshot = await captureSourceSnapshots(owner, backend, [
    read("image"),
    read("audio"),
    read("video"),
  ]);
  const input = {
    scanId,
    payload: { user_id: owner } as MultimodalPayload,
    mediaCounts: { ...counts },
    mediaObjectKeys: structuredClone(mediaKeys),
    captureSources: snapshot,
  };
  const pending = buildScanIngestionIntent(input);
  input.mediaObjectKeys.image[0] = key("replacement");
  input.mediaCounts.image_count = 90;
  const intent = await pending;
  assertEquals(intent.payload.captureSourceObservations, snapshot.observations);
  assertEquals(intent.payload.schemaVersion, 3);
  assertEquals((intent.payload.mediaCounts as typeof counts).image_count, 1);
  assertEquals(
    (intent.payload.media as { r2ObjectKeys: string[] }).r2ObjectKeys,
    mediaKeys.image,
  );
  assertEquals(JSON.stringify(intent.payload).includes("AQID"), false);
  for (
    const keys of [
      { ...mediaKeys, video: [] },
      { ...mediaKeys, audio: [key("other")] },
      { ...mediaKeys, image: [key("image"), key("image")] },
      { ...mediaKeys, image: [key("audio")], audio: [key("image")] },
    ]
  ) assertThrows(() => captureSourceObservationsForIntent(snapshot, keys));
  const fake = JSON.parse(JSON.stringify(snapshot)) as CaptureSourceSnapshots;
  assertThrows(() => captureSourceObservationsForIntent(fake, mediaKeys));
  await assertRejects(() =>
    buildScanIngestionIntent({
      ...input,
      mediaObjectKeys: mediaKeys,
      captureSources: fake,
    })
  );
  await assertRejects(() =>
    buildScanIngestionIntent({
      ...input,
      mediaObjectKeys: mediaKeys,
      payload: { user_id: owner, imageBase64s: ["AQID"] },
    })
  );
});

Deno.test("raw HTTP proof fields do not become server observations or alter legacy intent", async () => {
  const base = {
    scanId,
    payload: { user_id: owner } as MultimodalPayload,
    mediaCounts: counts,
    mediaObjectKeys: mediaKeys,
  };
  const legacy = await buildScanIngestionIntent(base);
  const forged = await buildScanIngestionIntent({
    ...base,
    payload: {
      captureSourceObservations: { version: 1, items: [read("image")] },
      captureSourceProofs: { version: 1 },
      captureSources: {},
    } as unknown as MultimodalPayload,
  });
  assertEquals(forged, legacy);
  assertEquals(
    Object.hasOwn(forged.payload, "captureSourceObservations"),
    false,
  );
  assertEquals(Object.hasOwn(forged.payload, "captureSourceProofs"), false);
});

Deno.test("source binding rejects noncanonical kind order and hashes exact subarray views", async () => {
  const ordered = await captureSourceSnapshots(owner, backend, [
    read("audio"),
    read("image"),
    read("video"),
  ]);
  assertThrows(() => captureSourceObservationsForIntent(ordered, mediaKeys));
  const backing = new Uint8Array([9, 1, 2, 3, 9]);
  const exact = await captureSourceSnapshots(owner, backend, [{
    ...read("image"),
    bytes: backing.subarray(1, 4),
  }]);
  assertEquals(exact.imageBase64s(), ["AQID"]);
  assertEquals(exact.observations.items[0].byteCount, 3);
  assertEquals(
    exact.observations.items[0].sha256,
    "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
  );
});

Deno.test("source snapshots preserve the full existing staging MIME allowlist", async () => {
  for (const kind of ["image", "audio", "video"] as const) {
    for (const contentType of STAGING_ALLOWED_CONTENT_TYPES[kind]) {
      const snapshot = await captureSourceSnapshots(owner, backend, [{
        ...read(kind),
        contentType,
      }]);
      assertEquals(snapshot.observations.items[0].contentType, contentType);
    }
  }
});

Deno.test("snapshot-bound intent rejects raw proof fields instead of downgrading", async () => {
  const captureSources = await captureSourceSnapshots(owner, backend, [
    read("image"),
    read("audio"),
    read("video"),
  ]);
  for (
    const field of [
      "captureSourceObservations",
      "captureSourceProofs",
      "captureSources",
    ]
  ) {
    for (const value of [null, {}, captureSources.observations]) {
      await assertRejects(
        () =>
          buildScanIngestionIntent({
            scanId,
            mediaCounts: counts,
            mediaObjectKeys: mediaKeys,
            captureSources,
            payload: { user_id: owner, [field]: value } as MultimodalPayload,
          }),
        Error,
        "invalid_capture_source_evidence",
      );
    }
  }
});
