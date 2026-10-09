import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  buildPreparedVideoAdmission,
  parsePreparedVideoAdmission,
} from "./videoAdmission.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { parsePreparedAudioAdmission } from "./audioAdmission.ts";
import { parseSourceReservationRequest } from "./sourceReservation.ts";
import { sourceReservationCanonicalBytes } from "./sourceFingerprint.ts";

interface Vector {
  name: string;
  input: Record<string, unknown>;
  canonical_body: string;
}
const vectors: Vector[] = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/video-request-v4.json", import.meta.url),
  ),
);
Deno.test("prepared video request accepts shared native payloads without rewriting old generations", () => {
  assertEquals(vectors.length, 2);
  for (const v of vectors) {
    const parsed = parsePreparedVideoAdmission(v.input);
    assertEquals<unknown>(parsed, v.input);
    assertEquals<unknown>(JSON.parse(v.canonical_body), parsed);
    assertEquals<unknown>(
      JSON.parse(buildPreparedVideoAdmission(v.input)),
      parsed,
    );
    assertEquals(Object.isFrozen(parsed), true);
    assertEquals(
      Object.isFrozen(parsed.evidence_manifest.provenance.frames),
      true,
    );
  }
});
Deno.test("prepared video request rejects parent aliases for every source and derived artifact", () => {
  const input = vectors[0].input;
  const manifest = parsePreparedVideoAdmission(input).evidence_manifest;
  const graph = manifest.provenance;
  const ids = [
    graph.source.media_id,
    ...graph.frames.map((f) => f.artifact.media_id),
    graph.audio?.artifact.media_id,
  ];
  for (
    const source_analysis_id of [
      ...ids,
      input.observation_id,
      input.analysis_id,
      null,
    ]
  ) {
    assertThrows(() =>
      parsePreparedVideoAdmission({ ...input, source_analysis_id })
    );
  }
});
Deno.test("prepared video request has closed protocols, fields and metadata boundaries", () => {
  const input = vectors[0].input;
  for (
    const [key, value] of Object.entries({
      schema_version: 3,
      entitlement_protocol: true,
      identification_protocol: 5,
      history_protocol: 12,
      expected_processor_permission: "openai",
      request_digest: "A".repeat(64),
      owner_id: input.observation_id,
      input_profile: "multimodal_video_audio_v1",
      source_analysis_id: "not-a-uuid",
      evidence_manifest: { schema_version: 4 },
    })
  ) {
    assertThrows(() => parsePreparedVideoAdmission({ ...input, [key]: value }));
  }
  for (const key of Object.keys(input)) {
    const missing = { ...input };
    delete missing[key];
    assertThrows(() => parsePreparedVideoAdmission(missing));
  }
  // This identifier is deliberately not reinterpreted as backend JSON hashing proof.
  assertEquals(
    parsePreparedVideoAdmission({ ...input, request_digest: "b".repeat(64) })
      .request_digest,
    "b".repeat(64),
  );
});
Deno.test("prepared video request remains outside live execution, audio and reservation", async () => {
  for (const v of vectors) {
    assertThrows(() => parseExecutableAnalysisInput(v.input));
    assertThrows(() => parsePreparedAudioAdmission(v.input));
    assertThrows(() => sourceReservationCanonicalBytes(v.input));
    await assertRejects(() =>
      parseSourceReservationRequest({
        schema_version: 1,
        input: v.input,
        fingerprint_version: 1,
        fingerprint: "a".repeat(64),
      })
    );
  }
});
