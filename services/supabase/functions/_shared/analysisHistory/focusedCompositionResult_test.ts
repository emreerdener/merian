import { assertEquals, assertThrows } from "@std/assert";
import { decodeAnalysisResultSnapshot } from "./result.ts";
import vectors from "./fixtures/composition-request-v6.json" with {
  type: "json",
};
import page from "./fixtures/page-v1.json" with { type: "json" };

for (const vector of vectors) {
  Deno.test(`reader15 preserves focused result7 ${vector.name}`, () => {
    const input = vector.input;
    const snapshot = {
      ...JSON.parse(page.items[0].snapshot),
      schema_version: 7,
      observation_id: input.observation_id,
      analysis_id: input.analysis_id,
      source_analysis_id: input.source_analysis_id,
      request_digest: input.request_digest,
      evidence_manifest: input.evidence_manifest,
    };
    snapshot.result.scan_id = input.observation_id;
    const text = JSON.stringify(snapshot);
    assertEquals<unknown>(
      decodeAnalysisResultSnapshot(text, 15).evidence_manifest,
      input.evidence_manifest,
    );
    for (const reader of [7, 8, 9, 10, 11, 13, 14] as const) {
      assertThrows(() => decodeAnalysisResultSnapshot(text, reader));
    }
    for (
      const change of [
        { source_analysis_id: null },
        { schema_version: 6 },
        { schema_version: 8 },
        {
          evidence_manifest: { ...input.evidence_manifest, schema_version: 5 },
        },
      ]
    ) {
      assertThrows(() =>
        decodeAnalysisResultSnapshot(
          JSON.stringify({ ...snapshot, ...change }),
          15,
        )
      );
    }
  });
}
