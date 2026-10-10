import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import { parsePreparedVideoManifest } from "./videoManifest.ts";
import { parsePreparedAudioManifest } from "./audioManifest.ts";
import { parseProtectedEvidenceManifest } from "./protectedManifest.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { parseSourceReservationRequest } from "./sourceReservation.ts";

interface Vector {
  name: string;
  valid: boolean;
  observation_id: string;
  analysis_id: string;
  manifest: Record<string, unknown>;
}
const vectors: Vector[] = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/video-manifest-v4.json", import.meta.url),
  ),
);
Deno.test("video manifest V4 shared native/backend acceptance vectors", () => {
  assertEquals(vectors.length, 40);
  for (const v of vectors) {
    const parse = () =>
      parsePreparedVideoManifest(v.manifest, v.observation_id, v.analysis_id);
    if (v.valid) assertEquals<unknown>(parse(), v.manifest, v.name);
    else assertThrows(parse, Error, undefined, v.name);
  }
});
Deno.test("video manifest snapshot is deeply immutable and preserves description order", () => {
  const v = structuredClone(vectors[0]);
  const result = parsePreparedVideoManifest(
    v.manifest,
    v.observation_id,
    v.analysis_id,
  );
  const expected = structuredClone(v.manifest);
  v.manifest.descriptions = ["changed"];
  assertEquals<unknown>(result, expected);
  const frozen = (value: unknown): void => {
    if (value !== null && typeof value === "object") {
      assertEquals(Object.isFrozen(value), true);
      Object.values(value).forEach(frozen);
    }
  };
  frozen(result);
});
Deno.test("video V4 grants no photo, audio, executable or source admission", async () => {
  const v = vectors[0];
  assertThrows(() =>
    parsePreparedAudioManifest(v.manifest, v.observation_id, v.analysis_id)
  );
  assertThrows(() => parseProtectedEvidenceManifest(v.manifest));
  const input = {
    schema_version: 4,
    observation_id: v.observation_id,
    analysis_id: v.analysis_id,
    source_analysis_id: null,
    request_digest: "a".repeat(64),
    evidence_manifest: v.manifest,
    entitlement_protocol: 3,
    identification_protocol: 6,
    history_protocol: 10,
    expected_processor_permission: "google_gemini",
  };
  assertThrows(() => parseExecutableAnalysisInput(input));
  await assertRejects(() =>
    parseSourceReservationRequest({
      schema_version: 1,
      input,
      fingerprint_version: 1,
      fingerprint: "a".repeat(64),
    })
  );
});
