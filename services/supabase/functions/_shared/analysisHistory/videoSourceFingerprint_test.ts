import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";
import { parsePreparedVideoAdmission } from "./videoAdmission.ts";
import { sourceReservationCanonicalBytes } from "./sourceFingerprint.ts";
import {
  videoSourceCanonicalBytes,
  videoSourceFingerprint,
} from "./videoSourceFingerprint.ts";
import vectors from "./fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import legacy from "./fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

Deno.test("held video fingerprint matches independent UTF8 netstring and SHA vectors", async () => {
  for (const vector of vectors) {
    const before = JSON.stringify(vector.input);
    assertEquals(
      hex(videoSourceCanonicalBytes(vector.input)),
      vector.canonical_utf8_hex,
    );
    assertEquals(await videoSourceFingerprint(vector.input), vector.sha256);
    assertEquals(JSON.stringify(vector.input), before);
  }
});
Deno.test("held video fingerprint ignores object order and snapshots before asynchronous hashing", async () => {
  const input = structuredClone(vectors[0].input);
  const reversed = JSON.parse(
    JSON.stringify(input),
    (_key, value) =>
      value && typeof value === "object" && !Array.isArray(value)
        ? Object.fromEntries(Object.entries(value).reverse())
        : value,
  );
  assertEquals(await videoSourceFingerprint(reversed), vectors[0].sha256);
  const pending = videoSourceFingerprint(input);
  input.evidence_manifest.descriptions.push("Changed");
  input.evidence_manifest.provenance.source.sha256 = "c".repeat(64);
  input.evidence_manifest.provenance.frames.reverse();
  assertEquals(await pending, vectors[0].sha256);
});
Deno.test("held video fingerprint binds or rejects every semantic leaf", async () => {
  const paths: (string | number)[][] = [];
  function visit(value: unknown, path: (string | number)[]) {
    if (Array.isArray(value)) value.forEach((v, i) => visit(v, [...path, i]));
    else if (value && typeof value === "object") {
      for (const [k, v] of Object.entries(value)) visit(v, [...path, k]);
    } else paths.push(path);
  }
  visit(vectors[0].input, []);
  assertEquals(paths.length > 80, true);
  for (const path of paths) {
    const input = structuredClone(vectors[0].input);
    let target: unknown = input;
    for (const part of path.slice(0, -1)) {
      target = (target as Record<string | number, unknown>)[part];
    }
    const record = target as Record<string | number, unknown>,
      key = path[path.length - 1];
    const old = record[key];
    record[key] = typeof old === "number"
      ? old + 1
      : typeof old === "boolean"
      ? !old
      : `${old}x`;
    let bytes: Uint8Array;
    try {
      bytes = videoSourceCanonicalBytes(input);
    } catch {
      continue;
    }
    assertNotEquals(hex(bytes), vectors[0].canonical_utf8_hex, path.join("."));
  }
  const reordered = structuredClone(vectors[2].input);
  reordered.evidence_manifest.descriptions.reverse();
  assertNotEquals(await videoSourceFingerprint(reordered), vectors[2].sha256);
});
Deno.test("held video fingerprint rejects aliases, unsupported text and alternate schemas", async () => {
  for (const text of ["NUL\u0000text", "surrogate\ud800"]) {
    const input = structuredClone(vectors[0].input);
    input.evidence_manifest.descriptions = [text];
    await assertRejects(() => videoSourceFingerprint(input));
  }
  const alias = structuredClone(vectors[0].input);
  alias.source_analysis_id = alias.evidence_manifest.provenance.source.media_id;
  assertThrows(() => videoSourceCanonicalBytes(alias));
  const reversed = structuredClone(vectors[0].input);
  reversed.evidence_manifest.provenance.frames.reverse();
  assertThrows(() => videoSourceCanonicalBytes(reversed));
  assertThrows(() =>
    videoSourceCanonicalBytes({ ...vectors[0].input, owner_id: "unexpected" })
  );
  for (const old of legacy) {
    assertThrows(() => videoSourceCanonicalBytes(old.input));
  }
});
Deno.test("held video fingerprint leaves executable admission and photo/audio fingerprints unchanged", () => {
  for (const vector of vectors) {
    assertThrows(() => parseExecutableAnalysisInput(vector.input));
    assertThrows(() => sourceReservationCanonicalBytes(vector.input));
  }
  for (const old of legacy) {
    assertEquals(
      hex(sourceReservationCanonicalBytes(old.input)),
      old.canonical_utf8_hex,
    );
  }
});

Deno.test("held video fingerprint binds semantic integers across JSON runtimes", async () => {
  for (const field of ["crop", "actual", "start", "index"]) {
    const zero = structuredClone(vectors[0].input);
    const graph = zero.evidence_manifest.provenance;
    if (field === "crop") graph.parameters.crop_center_basis_points = 0;
    if (field === "actual") graph.frames[0].actual_time_ticks = 0;
    if (field === "start") {
      graph.audio!.start_ticks = 0;
      graph.audio!.end_ticks = 1200;
    }
    const baseline = await videoSourceFingerprint(zero);
    if (field === "crop") graph.parameters.crop_center_basis_points = -0;
    if (field === "actual") graph.frames[0].actual_time_ticks = -0;
    if (field === "start") graph.audio!.start_ticks = -0;
    if (field === "index") graph.frames[0].index = -0;
    assertEquals(await videoSourceFingerprint(zero), baseline);
    parsePreparedVideoAdmission(zero);
  }
  const json = JSON.stringify(vectors[0].input);
  const decimal = json.replaceAll(":100,", ":1e2,");
  assertNotEquals(decimal, json);
  assertEquals(
    await videoSourceFingerprint(JSON.parse(decimal)),
    vectors[0].sha256,
  );
});
