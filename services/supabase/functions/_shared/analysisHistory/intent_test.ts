import { assertEquals, assertThrows } from "@std/assert";
import {
  buildAdmittedObservationDraft,
  buildObservationAnalysisAdmission,
} from "./intent.ts";
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
const claims = {
  entitlement_protocol: 3,
  identification_protocol: 6,
  history_protocol: 7,
  expected_processor_permission: "google_gemini",
};
Deno.test("analysis admission freezes evidence and actual capability claims", () => {
  const media = structuredClone(original.evidence_manifest.captured_media);
  const saved = buildObservationAnalysisAdmission(identity, media, claims);
  media[0].description._0.freeText = "Changed later";
  assertEquals(JSON.parse(saved).evidence_manifest, original.evidence_manifest);
  assertEquals(JSON.parse(saved).history_protocol, 7);
});
Deno.test("analysis admission rejects unsupported readers and media before funding", () => {
  for (
    const patch of [
      { history_protocol: 6 },
      { entitlement_protocol: null },
      { identification_protocol: 7 },
      { expected_processor_permission: "recovery_only" },
      { owner_id: identity.observation_id },
    ]
  ) {
    assertThrows(() =>
      buildObservationAnalysisAdmission(
        identity,
        original.evidence_manifest.captured_media,
        { ...claims, ...patch },
      )
    );
  }
  assertThrows(() => buildObservationAnalysisAdmission(identity, [], claims));
  assertThrows(() =>
    buildObservationAnalysisAdmission(identity, [{
      image: {
        _0: {
          storage: "remoteURL",
          path: "https://media.merian.app/synthetic.jpg",
        },
      },
    }], claims)
  );
});
Deno.test("admitted draft uses frozen evidence and canonical result without review or credit authority", () => {
  const saved = buildObservationAnalysisAdmission(
    identity,
    original.evidence_manifest.captured_media,
    claims,
  );
  const draft = buildAdmittedObservationDraft(saved, {
    ...original.result,
    user_confirmed_identification: true,
    entitlement: { credit_consumed: true },
  }, {
    id: "00000000-0000-4000-8000-000000000004",
    scientific_name: original.result.scientific_name,
  });
  assertEquals(draft.evidence_manifest, original.evidence_manifest);
  assertEquals(Object.hasOwn(draft.result_snapshot, "entitlement"), false);
  assertEquals(
    Object.hasOwn(draft.result_snapshot, "user_confirmed_identification"),
    false,
  );
  assertThrows(() =>
    buildAdmittedObservationDraft(saved, {
      ...original.result,
      scan_id: identity.analysis_id,
    }, null)
  );
  assertThrows(() =>
    buildAdmittedObservationDraft(
      JSON.stringify({ ...JSON.parse(saved), extra: true }),
      original.result,
      null,
    )
  );
});
