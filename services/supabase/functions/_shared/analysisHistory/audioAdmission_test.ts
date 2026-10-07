import { assertEquals, assertThrows } from "@std/assert";
import {
  buildPreparedAudioAdmission,
  buildPreparedAudioDraft,
  parsePreparedAudioAdmission,
} from "./audioAdmission.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { buildProtectedAnalysisAdmission } from "./protectedManifest.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";
const page = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/page-v1.json", import.meta.url)),
);
const snapshot = JSON.parse(page.items[0].snapshot);
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const request = () => ({
  schema_version: 3,
  observation_id: snapshot.observation_id,
  analysis_id: snapshot.analysis_id,
  source_analysis_id: id(61),
  request_digest: snapshot.request_digest,
  evidence_manifest: {
    schema_version: 3,
    items: [
      { kind: "description", text: "Before\n\u00e9" },
      {
        kind: "audio",
        media_id: id(62),
        content_type: "audio/wav",
        byte_count: 46,
        sha256: "a".repeat(64),
      },
      { kind: "description", text: "After e\u0301" },
    ],
  },
  entitlement_protocol: 3,
  identification_protocol: 6,
  history_protocol: 9,
  expected_processor_permission: "google_gemini",
});
Deno.test("prepared audio admission owns exact ordered metadata and pins protocol/processor", () => {
  const source = request();
  const input = parsePreparedAudioAdmission(source);
  const bytes = buildPreparedAudioAdmission(source);
  assertEquals(JSON.parse(bytes), source);
  assertEquals(Object.isFrozen(input), true);
  assertEquals(Object.isFrozen(input.evidence_manifest.items), true);
  assertEquals(input.evidence_manifest.items.every(Object.isFrozen), true);
  source.evidence_manifest.items.reverse();
  assertEquals(buildPreparedAudioAdmission(input), bytes);
  assertEquals(
    parsePreparedAudioAdmission({ ...request(), source_analysis_id: null })
      .source_analysis_id,
    null,
  );
});
Deno.test("prepared audio admission rejects capability changes and caller authority", () => {
  for (
    const change of [
      { schema_version: 2 },
      { schema_version: 4 },
      { history_protocol: 8 },
      { history_protocol: 10 },
      { entitlement_protocol: 2 },
      { identification_protocol: 7 },
      { expected_processor_permission: "openai" },
      { expected_processor_permission: null },
      { provider: "google" },
      { input_profile: "multimodal_audio_v1" },
      { owner_id: id(90) },
      { operation_id: id(90) },
      { request_digest: "A".repeat(64) },
      { analysis_id: snapshot.observation_id },
      { source_analysis_id: snapshot.analysis_id },
      { source_analysis_id: snapshot.observation_id },
      { source_analysis_id: id(62) },
    ]
  ) {
    assertThrows(() =>
      parsePreparedAudioAdmission({ ...request(), ...change })
    );
  }
  const missing: Record<string, unknown> = request();
  delete missing.history_protocol;
  assertThrows(() => parsePreparedAudioAdmission(missing));
});
Deno.test("prepared audio admission rejects photo substitution and unbounded or private evidence", () => {
  const original = request(), audio = original.evidence_manifest.items[1];
  for (
    const evidence of [
      { ...original.evidence_manifest, schema_version: 2 },
      { schema_version: 3, items: [] },
      { schema_version: 3, items: [audio, audio] },
      {
        schema_version: 3,
        items: [{ ...audio, kind: "image", content_type: "image/jpeg" }],
      },
      {
        schema_version: 3,
        items: [{ ...audio, media_id: snapshot.analysis_id }],
      },
      { schema_version: 3, items: [{ ...audio, object_id: id(91) }] },
      { schema_version: 3, items: [{ ...audio, byte_count: 2700001 }] },
      {
        schema_version: 3,
        items: [audio, { kind: "description", text: "x".repeat(16385) }],
      },
    ]
  ) {
    assertThrows(() =>
      parsePreparedAudioAdmission({ ...original, evidence_manifest: evidence })
    );
  }
});
Deno.test("prepared audio draft preserves exact input and removes mutable review/funding fields", () => {
  const bytes = buildPreparedAudioAdmission(request());
  const species = {
    id: id(4),
    scientific_name: snapshot.result.scientific_name,
  };
  const draft = buildPreparedAudioDraft(bytes, {
    ...snapshot.result,
    user_confirmed_identification: true,
    user_identification_override: "Injected",
    entitlement: { credit_consumed: true },
  }, species);
  assertEquals(draft.schema_version, 3);
  assertEquals(
    JSON.stringify(draft.evidence_manifest),
    JSON.stringify(request().evidence_manifest),
  );
  assertEquals(draft.request_digest, request().request_digest);
  assertEquals(draft.source_analysis_id, id(61));
  for (
    const key of [
      "user_confirmed_identification",
      "user_identification_override",
      "entitlement",
    ]
  ) {
    assertEquals(Object.hasOwn(draft.result_snapshot, key), false);
  }
  assertThrows(() =>
    buildPreparedAudioDraft(
      bytes,
      { ...snapshot.result, scan_id: id(91) },
      species,
    )
  );
  assertThrows(() => buildPreparedAudioDraft(bytes, snapshot.result, null));
  assertThrows(() => buildPreparedAudioDraft("{", snapshot.result, species));
  assertThrows(() =>
    buildPreparedAudioDraft(" ".repeat(1048577), snapshot.result, species)
  );
});
Deno.test("prepared audio cannot widen execution or imported result readers; V2 stays exact", () => {
  const input = request();
  assertThrows(() => parseExecutableAnalysisInput(input));
  for (const reader of [7, 8, 9] as const) {
    assertThrows(() =>
      decodeAnalysisResultSnapshot(
        JSON.stringify({
          ...snapshot,
          schema_version: 4,
          evidence_manifest: input.evidence_manifest,
        }),
        reader,
      )
    );
    assertThrows(() =>
      decodeAnalysisResultSnapshot(
        JSON.stringify({
          ...snapshot,
          schema_version: 3,
          evidence_manifest: input.evidence_manifest,
        }),
        reader,
      )
    );
  }
  const {
    evidence_manifest,
    entitlement_protocol,
    identification_protocol,
    history_protocol: _history,
    expected_processor_permission,
    ...identity
  } = input;
  const photo = {
    schema_version: 2,
    items: [{
      ...evidence_manifest.items[1],
      kind: "image",
      content_type: "image/jpeg",
    }],
  };
  const bytes = buildProtectedAnalysisAdmission(
    { ...identity, schema_version: 2 },
    photo,
    {
      entitlement_protocol,
      identification_protocol,
      history_protocol: 8,
      expected_processor_permission,
    },
  );
  assertEquals(
    JSON.stringify(parseExecutableAnalysisInput(JSON.parse(bytes))),
    bytes,
  );
  assertThrows(() => buildPreparedAudioAdmission(JSON.parse(bytes)));
});
