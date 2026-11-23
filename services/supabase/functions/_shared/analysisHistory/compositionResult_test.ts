import { assertEquals, assertThrows } from "@std/assert";
import { decodeAnalysisResultSnapshot } from "./result.ts";
import vectors from "./fixtures/composition-request-v5.json" with {
  type: "json",
};
import page from "./fixtures/page-v1.json" with { type: "json" };
for (const vector of vectors.filter((v) => v.valid)) {
  Deno.test(`reader14 preserves composition result6 ${vector.name}`, () => {
    const input = vector.input;
    const value = {
      ...JSON.parse(page.items[0].snapshot),
      schema_version: 6,
      observation_id: input.observation_id,
      analysis_id: input.analysis_id,
      source_analysis_id: input.source_analysis_id,
      request_digest: input.request_digest,
      evidence_manifest: input.evidence_manifest,
    };
    value.result.scan_id = input.observation_id;
    const text = JSON.stringify(value);
    assertEquals<unknown>(
      decodeAnalysisResultSnapshot(text, 14).evidence_manifest,
      input.evidence_manifest,
    );
    for (const reader of [7, 8, 9, 10, 11, 13] as const) {
      assertThrows(() => decodeAnalysisResultSnapshot(text, reader));
    }
    assertThrows(() =>
      decodeAnalysisResultSnapshot(
        JSON.stringify({
          ...value,
          evidence_manifest: { ...input.evidence_manifest, schema_version: 6 },
        }),
        14,
      )
    );
    assertThrows(() =>
      decodeAnalysisResultSnapshot(
        JSON.stringify({ ...value, schema_version: 5 }),
        14,
      )
    );
    assertThrows(() =>
      decodeAnalysisResultSnapshot(
        JSON.stringify({ ...value, source_analysis_id: null }),
        14,
      )
    );
    assertThrows(() =>
      decodeAnalysisResultSnapshot(
        JSON.stringify({
          ...value,
          evidence_manifest: { ...input.evidence_manifest, items: [] },
        }),
        14,
      )
    );
  });
}
