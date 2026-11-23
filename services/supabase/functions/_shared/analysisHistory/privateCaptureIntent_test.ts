import { assertEquals, assertRejects } from "@std/assert";
import { buildPrivateCaptureIntent } from "./privateCaptureIntent.ts";
import { initialEvidenceDigest } from "./initialEvidenceManifest.ts";
import { parseInitialEvidenceCapturePlan } from "./initialEvidenceCapturePlan.ts";
import { SCAN_INGESTION_INTENT_SCHEMA_VERSION } from "../scanIngestionIntents.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
async function fixture() {
  const source = {
      media_id: id(4),
      content_type: "audio/wav",
      byte_count: 100,
      sha256: "a".repeat(64),
    },
    prepared = {
      media_id: id(5),
      content_type: "audio/wav",
      byte_count: 16044,
      sha256: "b".repeat(64),
    };
  const note = { kind: "description", text: "Original field note" };
  const plan = parseInitialEvidenceCapturePlan(id(1), {
    schema_version: 1,
    scan_id: id(2),
    generation: id(3),
    items: [{ kind: "audio", source, prepared_media_id: id(5) }, note],
  });
  const manifest = {
    schema_version: 9,
    items: [{ kind: "audio", source, prepared }, note],
  };
  return {
    plan,
    initialEvidence: {
      schema_version: 1,
      scan_id: id(2),
      generation: id(3),
      evidence_manifest: manifest,
      evidence_digest: await initialEvidenceDigest(manifest, id(2), id(3)),
    },
    payload: { user_id: id(1) },
  };
}
Deno.test("private successor preserves V3 and derives counts notes and empty public inventory from frozen evidence", async () => {
  const input = await fixture();
  const pending = buildPrivateCaptureIntent(input);
  input.payload.user_id = id(10);
  Object.assign(input.initialEvidence.evidence_manifest.items[1], {
    text: "Changed after invocation",
  });
  const value = await pending;
  assertEquals(SCAN_INGESTION_INTENT_SCHEMA_VERSION, 3);
  assertEquals(value.payloadSchemaVersion, 4);
  assertEquals(value.payload.observationContexts, [{
    freeText: "Original field note",
  }]);
  assertEquals(value.payload.media, {
    r2ObjectKeys: [],
    audioR2ObjectKeys: [],
    videoR2ObjectKeys: [],
  });
  assertEquals(value.mediaCounts, {
    image_count: 0,
    audio_count: 1,
    video_count: 0,
    required_video_count: 0,
    video_frame_count: 0,
    video_inference_frame_count: 0,
    has_description: true,
  });
  assertEquals(value.payload.uploadSessionIds, []);
  assertEquals(value.storageKeys, []);
});
Deno.test("private intent rejects caller transport, foreign owner and changed full-plan associations", async () => {
  for (
    const patch of [
      { user_id: id(9) },
      { imageBase64s: ["AA=="] },
      { audioBase64s: ["AA=="] },
      { r2ObjectKeys: ["staging/forbidden"] },
      { audioR2ObjectKeys: ["staging/forbidden"] },
      { videoR2ObjectKeys: ["staging/forbidden"] },
      { captureSourceProofs: {} },
      { privateCaptureStage: {} },
    ]
  ) {
    const input = await fixture();
    Object.assign(input.payload, patch);
    await assertRejects(() => buildPrivateCaptureIntent(input));
  }
  const input = await fixture();
  Object.assign(input.initialEvidence.evidence_manifest.items[1], {
    text: "Different sealed note",
  });
  input.initialEvidence.evidence_digest = await initialEvidenceDigest(
    input.initialEvidence.evidence_manifest,
    id(2),
    id(3),
  );
  await assertRejects(() => buildPrivateCaptureIntent(input));
});
