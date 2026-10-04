import { assertEquals, assertThrows } from "@std/assert";
import { buildObservationAnalysisAppend } from "./append.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";

const fixture = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/page-v1.json", import.meta.url)),
);
const original = JSON.parse(fixture.items[0].snapshot);
const identity = {
  schema_version: 1,
  observation_id: original.observation_id,
  analysis_id: original.analysis_id,
  source_analysis_id: null,
  request_digest: original.request_digest,
};
const species = {
  id: "00000000-0000-4000-8000-000000000004",
  scientific_name: original.result.scientific_name,
};
const media = original.evidence_manifest.captured_media;

Deno.test("append builder derives a canonical readable result with an independently resolved species link", () => {
  const request = buildObservationAnalysisAppend(
    identity,
    original.result,
    media,
    species,
  );
  assertEquals(request.result_snapshot.species_id, species.id);
  assertEquals(request.result_snapshot.scan_id, identity.observation_id);
  assertEquals(request.evidence_manifest, original.evidence_manifest);
  const snapshot = decodeAnalysisResultSnapshot(JSON.stringify({
    ...identity,
    ordinal: 1,
    completed_at_ms: original.completed_at_ms,
    result: request.result_snapshot,
    evidence_manifest: request.evidence_manifest,
  }));
  assertEquals(snapshot.analysis_id, identity.analysis_id);
  assertEquals(snapshot.result.scientific_name, species.scientific_name);
});

Deno.test("append never inherits correction, confirmation, funding or caller species authority", () => {
  const request = buildObservationAnalysisAppend(
    identity,
    {
      ...original.result,
      species_id: identity.observation_id,
      user_confirmed_identification: true,
      confirmed_species_id: identity.observation_id,
      ai_identification_review: { community: { rank: "species" } },
      entitlement: { credit_consumed: true },
    },
    media,
    species,
  );
  assertEquals(request.result_snapshot.species_id, species.id);
  for (
    const field of [
      "user_confirmed_identification",
      "confirmed_species_id",
      "ai_identification_review",
      "entitlement",
    ]
  ) assertEquals(Object.hasOwn(request.result_snapshot, field), false);
});

Deno.test("append requires observation binding and a matching resolved taxonomy", () => {
  for (
    const changedSpecies of [
      null,
      { ...species, id: "bad" },
      { ...species, scientific_name: "Different synthetic species" },
    ]
  ) {
    assertThrows(() =>
      buildObservationAnalysisAppend(
        identity,
        original.result,
        media,
        changedSpecies,
      )
    );
  }
  assertThrows(() =>
    buildObservationAnalysisAppend(
      identity,
      {
        ...original.result,
        scan_id: identity.analysis_id,
      },
      media,
      species,
    )
  );
  assertThrows(() =>
    buildObservationAnalysisAppend(
      {
        ...identity,
        analysis_id: identity.observation_id,
      },
      original.result,
      media,
      species,
    )
  );
  assertThrows(() =>
    buildObservationAnalysisAppend(
      { ...identity, source_analysis_id: identity.observation_id },
      original.result,
      media,
      species,
    )
  );
  assertThrows(() =>
    buildObservationAnalysisAppend(identity, {}, media, species)
  );
});

Deno.test("non-biological append clears the species link and cannot manufacture authority", () => {
  const result = {
    ...original.result,
    is_biological_subject: false,
    scientific_name: null,
  };
  const request = buildObservationAnalysisAppend(identity, result, media, null);
  assertEquals(request.result_snapshot.species_id, null);
  assertThrows(() =>
    buildObservationAnalysisAppend(identity, result, media, species)
  );
});

Deno.test("all media delivery references fail closed until protected evidence admission exists", () => {
  const ref = {
    storage: "remoteURL",
    path:
      "https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-000000000003/synthetic.jpg",
  };
  for (
    const invalid of [
      [],
      [{ image: { _0: ref } }],
      [{ audio: { _0: ref } }],
      [{ video: { _0: { video: ref } } }],
      [...media, { image: { _0: ref } }],
      [{ image: { _0: { storage: "localFile", path: "fixture.jpg" } } }],
      [{ description: { _0: { freeText: "x".repeat(8193) } } }],
      Array(65).fill(media[0]),
    ]
  ) {
    assertThrows(() =>
      buildObservationAnalysisAppend(
        identity,
        original.result,
        invalid,
        species,
      )
    );
  }
});
