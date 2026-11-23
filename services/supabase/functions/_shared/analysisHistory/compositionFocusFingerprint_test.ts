import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import {
  parseCompositionAdmission,
  parseFocusedCompositionRequestStructure,
} from "./compositionAdmission.ts";
import {
  focusedCompositionFingerprint,
  focusedCompositionRequestDigest,
} from "./compositionFingerprint.ts";

const vectors = JSON.parse(
  await Deno.readTextFile(
    new URL("./fixtures/composition-request-v6.json", import.meta.url),
  ),
);

Deno.test("V6 unsigned request and source fingerprint share cross-runtime vectors", async () => {
  for (const vector of vectors) {
    assertEquals(
      await focusedCompositionRequestDigest(vector.input),
      vector.request_digest,
      vector.name,
    );
    assertEquals(
      await focusedCompositionFingerprint(vector.input),
      vector.fingerprint,
      vector.name,
    );
    assertThrows(() => parseCompositionAdmission(vector.input));
  }
  const byName = (name: string) =>
    vectors.find((row: { name: string }) => row.name === name);
  assertEquals(
    byName("negative-zero").fingerprint,
    byName("full-image").fingerprint,
  );
  for (
    const name of [
      "automatic",
      "full-image",
      "one-ulp",
      "absent",
      "reordered",
      "changed-artifact",
    ]
  ) {
    assertNotEquals(
      byName(name).request_digest,
      byName("manual-photo-audio").request_digest,
    );
    assertNotEquals(
      byName(name).fingerprint,
      byName("manual-photo-audio").fingerprint,
    );
  }
});

Deno.test("V6 equivalent numeric spellings and JSON key order do not change either digest", async () => {
  const vector = vectors[0];
  const reordered = Object.fromEntries(Object.entries(vector.input).reverse());
  const encoded = JSON.stringify(reordered).replace('"x":0.1', '"x":1e-1')
    .replace('"y":0.2', '"y":0.20000000000000001');
  const value = JSON.parse(encoded);
  assertEquals(
    await focusedCompositionRequestDigest(value),
    vector.request_digest,
  );
  assertEquals(await focusedCompositionFingerprint(value), vector.fingerprint);
  const changedDigest = { ...value, request_digest: "f".repeat(64) };
  assertEquals(
    await focusedCompositionRequestDigest(changedDigest),
    vector.request_digest,
  );
  await assertRejects(() => focusedCompositionFingerprint(changedDigest));
});

Deno.test("V6 fails closed on mismatched manifests, predecessors, null and extra focus fields", () => {
  const original = vectors[0].input;
  for (const change of [{ source_analysis_id: null }, { schema_version: 5 }]) {
    assertThrows(() =>
      parseFocusedCompositionRequestStructure({ ...original, ...change })
    );
  }
  assertThrows(() =>
    parseFocusedCompositionRequestStructure({
      ...original,
      evidence_manifest: { ...original.evidence_manifest, schema_version: 5 },
    })
  );
  for (
    const focus of [null, {
      ...original.evidence_manifest.items[0].focus_region,
      extra: true,
    }, { ...original.evidence_manifest.items[0].focus_region, x: "0.1" }]
  ) {
    const input = structuredClone(original);
    input.evidence_manifest.items[0].focus_region = focus;
    assertThrows(() => parseFocusedCompositionRequestStructure(input));
  }
});
