import { assertEquals, assertThrows } from "@std/assert";
import {
  buildProtectedAnalysisAdmission,
  buildProtectedAnalysisDraft,
  parseProtectedEvidenceManifest,
  protectedImageReference,
} from "./protectedManifest.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";
import type { EvidenceReceipt } from "./evidence.ts";
const fixture = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/page-v1.json", import.meta.url)),
);
const original = JSON.parse(fixture.items[0].snapshot);
const identity = {
  schema_version: 2,
  observation_id: original.observation_id,
  analysis_id: original.analysis_id,
  source_analysis_id: null,
  request_digest: original.request_digest,
};
const claims = {
  entitlement_protocol: 3,
  identification_protocol: 6,
  history_protocol: 8,
  expected_processor_permission: "google_gemini",
};
const photo = {
  kind: "image" as const,
  media_id: "00000000-0000-4000-8000-000000000030",
  content_type: "image/jpeg",
  byte_count: 3,
  sha256: "a".repeat(64),
};
const manifest = {
  schema_version: 2,
  items: [photo, { kind: "description", text: "Synthetic observation" }],
};
Deno.test("protected manifest freezes ordered photo references and excludes delivery data", () => {
  const mutable = structuredClone(manifest);
  const input = buildProtectedAnalysisAdmission(identity, mutable, claims);
  if ("byte_count" in mutable.items[0]) mutable.items[0].byte_count = 10;
  assertEquals(JSON.parse(input).evidence_manifest, manifest);
  for (const key of ["object_id", "url", "storage_key", "owner_id"]) {
    assertThrows(() =>
      parseProtectedEvidenceManifest({
        schema_version: 2,
        items: [{ ...photo, [key]: "private" }],
      })
    );
  }
});
Deno.test("protected manifest rejects unsupported modalities, duplicate IDs and aggregate bytes", () => {
  for (
    const items of [
      [],
      [photo, photo],
      [{ ...photo, kind: "audio", content_type: "audio/mp4" }],
      [{ ...photo, kind: "video", content_type: "video/mp4" }],
      [{ kind: "description", text: "Only text" }],
      [{ ...photo, byte_count: 33554432 }, {
        ...photo,
        media_id: "00000000-0000-4000-8000-000000000031",
      }],
      [{ ...photo, byte_count: 0 }],
      [{ ...photo, sha256: "z".repeat(64) }],
      [{ kind: "description", text: " " }, photo],
    ]
  ) {
    assertThrows(() =>
      parseProtectedEvidenceManifest({ schema_version: 2, items })
    );
  }
});
Deno.test("protected admission requires explicit V2 and new history capability", () => {
  assertThrows(() =>
    buildProtectedAnalysisAdmission(
      { ...identity, schema_version: 1 },
      manifest,
      claims,
    )
  );
  assertThrows(() =>
    buildProtectedAnalysisAdmission(identity, manifest, {
      ...claims,
      history_protocol: 7,
    })
  );
  assertThrows(() =>
    buildProtectedAnalysisAdmission(identity, {
      schema_version: 2,
      items: [{ ...photo, media_id: identity.analysis_id }],
    }, claims)
  );
});
Deno.test("protected draft uses original evidence and canonical taxonomy without authority", () => {
  const input = buildProtectedAnalysisAdmission(identity, manifest, claims);
  const draft = buildProtectedAnalysisDraft(input, {
    ...original.result,
    user_confirmed_identification: true,
    entitlement: { credit_consumed: true },
  }, {
    id: "00000000-0000-4000-8000-000000000004",
    scientific_name: original.result.scientific_name,
  });
  assertEquals(draft.schema_version, 2);
  assertEquals(draft.evidence_manifest, manifest);
  assertEquals(Object.hasOwn(draft.result_snapshot, "entitlement"), false);
  assertEquals(
    Object.hasOwn(draft.result_snapshot, "user_confirmed_identification"),
    false,
  );
  assertThrows(() =>
    buildProtectedAnalysisDraft(input, {
      ...original.result,
      scan_id: photo.media_id,
    }, null)
  );
});
Deno.test("private receipt projection retains no object key or owner and requires readiness", () => {
  const receipt = {
    ...photo,
    object_id: "00000000-0000-4000-8000-000000000040",
    owner_id: "00000000-0000-4000-8000-000000000050",
    observation_id: identity.observation_id,
    analysis_id: identity.analysis_id,
    expires_at: "2026-10-03T00:00:00Z",
    ready_at: "2026-10-02T23:59:00Z",
  } satisfies EvidenceReceipt;
  assertEquals(protectedImageReference(receipt), photo);
  assertThrows(() => protectedImageReference({ ...receipt, ready_at: null }));
});
Deno.test("V1 decoder preserves original bytes and fails closed on protected V2", () => {
  assertEquals(
    decodeAnalysisResultSnapshot(fixture.items[0].snapshot).analysis_id,
    identity.analysis_id,
  );
  assertThrows(() =>
    decodeAnalysisResultSnapshot(
      JSON.stringify({
        ...original,
        schema_version: 2,
        evidence_manifest: manifest,
      }),
    )
  );
});
