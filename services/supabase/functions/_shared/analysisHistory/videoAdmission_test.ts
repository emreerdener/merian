import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  buildPreparedVideoAdmission,
  buildPreparedVideoDraft,
  parsePreparedVideoAdmission,
} from "./videoAdmission.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { parsePreparedAudioAdmission } from "./audioAdmission.ts";
import { parseSourceReservationRequest } from "./sourceReservation.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";
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

const historyPage = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/page-v1.json", import.meta.url)),
);
const historySnapshot = JSON.parse(historyPage.items[0].snapshot);
const species = {
  id: "00000000-0000-4000-8000-000000000099",
  scientific_name: historySnapshot.result.scientific_name,
};
const resultFor = (input: Record<string, unknown>) => ({
  ...structuredClone(historySnapshot.result),
  scan_id: input.observation_id,
});
Deno.test("prepared video draft preserves exact silent and audio provenance and strips mutable authority", () => {
  for (const v of vectors) {
    const input = structuredClone(v.input), result = resultFor(input);
    const draft = buildPreparedVideoDraft(v.canonical_body, {
      ...result,
      user_confirmed_identification: true,
      user_identification_override: "Injected",
      confirmed_species_identity: { scientific_name: "Injected" },
      confirmed_species_identity_revision: 10,
      ai_identification_review: { status: "confirmed" },
      user_review_state: "confirmed",
      entitlement: { credit_consumed: true },
      species_id: "injected",
    }, species);
    const {
      entitlement_protocol: _e,
      identification_protocol: _i,
      history_protocol: _h,
      expected_processor_permission: _p,
      ...identity
    } = input;
    assertEquals({ ...draft, result_snapshot: undefined }, {
      ...identity,
      result_snapshot: undefined,
    });
    assertEquals(draft.result_snapshot.species_id, species.id);
    for (
      const key of [
        "user_confirmed_identification",
        "user_identification_override",
        "confirmed_species_identity",
        "confirmed_species_identity_revision",
        "ai_identification_review",
        "user_review_state",
        "entitlement",
      ]
    ) assertEquals(Object.hasOwn(draft.result_snapshot, key), false);
    assertEquals(Object.isFrozen(draft), true);
    assertEquals(
      Object.isFrozen(draft.evidence_manifest.provenance.frames),
      true,
    );
    assertEquals<unknown>(draft.evidence_manifest, input.evidence_manifest);
    const saved = JSON.stringify(draft);
    result.common_name = "changed";
    input.evidence_manifest = {};
    assertEquals(JSON.stringify(draft), saved);
  }
});
Deno.test("prepared video draft rejects wrong result identity, invalid semantics and taxonomy links", () => {
  const v = vectors[0], result = resultFor(v.input);
  for (
    const changed of [null, {}, { ...result, scan_id: species.id }, {
      ...result,
      confidence_score: 1.1,
    }, { ...result, is_biological_subject: "yes" }]
  ) {
    assertThrows(() =>
      buildPreparedVideoDraft(v.canonical_body, changed, species)
    );
  }
  assertThrows(() => buildPreparedVideoDraft(v.canonical_body, result, null));
  assertThrows(() =>
    buildPreparedVideoDraft(v.canonical_body, result, {
      ...species,
      id: "invalid",
    })
  );
  assertThrows(() =>
    buildPreparedVideoDraft(v.canonical_body, result, {
      ...species,
      scientific_name: "Different species",
    })
  );
});
Deno.test("prepared video draft requires bounded saved V4 bytes and cannot become a completion or executable request", () => {
  const v = vectors[0], result = resultFor(v.input);
  for (
    const bytes of [
      "{",
      "null",
      "[]",
      " ".repeat(1048577),
      "é".repeat(524289),
      JSON.stringify({ ...v.input, schema_version: 3 }),
      JSON.stringify({ ...v.input, history_protocol: 12 }),
    ]
  ) {
    assertThrows(() => buildPreparedVideoDraft(bytes, result, species));
  }
  const draft = buildPreparedVideoDraft(v.canonical_body, result, species);
  assertThrows(() => parseExecutableAnalysisInput(v.input));
  assertThrows(() => parseExecutableAnalysisInput(draft));
  for (const reader of [7, 8, 9, 10] as const) {
    assertThrows(() =>
      decodeAnalysisResultSnapshot(JSON.stringify(draft), reader)
    );
  }
});
