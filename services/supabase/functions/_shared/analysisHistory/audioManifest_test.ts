import { assertEquals, assertThrows } from "@std/assert";
import { parsePreparedAudioManifest } from "./audioManifest.ts";
import { parseProtectedEvidenceManifest } from "./protectedManifest.ts";
import { parseExecutableAnalysisInput } from "./analysisInput.ts";

const observation = "00000000-0000-4000-8000-000000000001";
const analysis = "00000000-0000-4000-8000-000000000002";
const audio = {
  kind: "audio" as const,
  media_id: "00000000-0000-4000-8000-000000000003",
  content_type: "audio/wav" as const,
  byte_count: 46,
  sha256: "a".repeat(64),
};
const description = {
  kind: "description" as const,
  text: "Synthetic audio context",
};
const parse = (items: unknown[]) =>
  parsePreparedAudioManifest(
    { schema_version: 3, items },
    observation,
    analysis,
  );

Deno.test("prepared audio metadata preserves exact order and owns immutable values", () => {
  const input = [structuredClone(description), structuredClone(audio)] as const;
  const manifest = parse([...input]);
  input[0].text = "Changed input";
  input[1].sha256 = "b".repeat(64);
  assertEquals(manifest.items, [description, audio]);
  assertEquals(Object.isFrozen(manifest), true);
  assertEquals(Object.isFrozen(manifest.items), true);
  assertEquals(manifest.items.every(Object.isFrozen), true);
  assertEquals(
    parsePreparedAudioManifest(
      JSON.parse(JSON.stringify(manifest)),
      observation,
      analysis,
    ),
    manifest,
  );
});

Deno.test("prepared audio metadata closes keys, media count, type and identity", () => {
  for (
    const items of [
      [],
      [description],
      [audio, audio],
      [null],
      [true],
      [{ ...audio, kind: "image" }],
      [{ ...audio, kind: "video" }],
      [{ ...audio, content_type: "audio/mp4" }],
      [{ ...audio, media_id: observation }],
      [{ ...audio, media_id: analysis }],
      [{
        ...audio,
        media_id: audio.media_id.toUpperCase().replace("003", "00A"),
      }],
      [audio, ...Array(64).fill(description)],
    ]
  ) {
    assertThrows(() => parse(items));
  }
  for (
    const key of [
      "owner_id",
      "object_id",
      "storage_key",
      "url",
      "path",
      "duration",
      "provider",
      "source_filename",
    ]
  ) {
    assertThrows(() => parse([{ ...audio, [key]: "forbidden" }]));
  }
  assertThrows(() =>
    parsePreparedAudioManifest(
      { schema_version: 3, items: [audio], extra: true },
      observation,
      analysis,
    )
  );
  assertThrows(() =>
    parsePreparedAudioManifest(
      { schema_version: 3, items: [audio] },
      observation,
      observation,
    )
  );
});

Deno.test("prepared audio metadata bounds numbers, digests and Unicode text", () => {
  for (
    const byte_count of [0, 44, 45, 46.5, 2_700_001, NaN, Infinity, true, "46"]
  ) {
    assertThrows(() => parse([{ ...audio, byte_count }]));
  }
  assertEquals(parse([{ ...audio, byte_count: 2_700_000 }]).items.length, 1);
  for (const sha256 of ["", "a".repeat(63), "A".repeat(64), "z".repeat(64)]) {
    assertThrows(() => parse([{ ...audio, sha256 }]));
  }
  for (const text of [" ", "a".repeat(8193), "🦋".repeat(8193)]) {
    assertThrows(() => parse([audio, { kind: "description", text }]));
  }
  assertEquals(
    parse([audio, { kind: "description", text: "🦋".repeat(8192) }]).items
      .length,
    2,
  );
  const part = { kind: "description", text: "a".repeat(8000) };
  assertEquals(parse([audio, part, part, part, part]).items.length, 5);
  assertThrows(() => parse([audio, part, part, part, part, description]));
});

Deno.test("prepared audio generation cannot enter current photo or executable routes", () => {
  const manifest = parse([audio]);
  assertThrows(() => parseProtectedEvidenceManifest(manifest));
  assertThrows(() =>
    parseProtectedEvidenceManifest({ ...manifest, schema_version: 2 })
  );
  for (const schema_version of [1, 2, 4, "3"]) {
    assertThrows(() =>
      parsePreparedAudioManifest(
        { ...manifest, schema_version },
        observation,
        analysis,
      )
    );
  }
  assertThrows(() =>
    parseExecutableAnalysisInput({
      schema_version: 3,
      observation_id: observation,
      analysis_id: analysis,
      source_analysis_id: null,
      request_digest: "b".repeat(64),
      evidence_manifest: manifest,
      entitlement_protocol: 3,
      identification_protocol: 6,
      history_protocol: 9,
      expected_processor_permission: "google_gemini",
    })
  );
  const photo = { ...audio, kind: "image", content_type: "image/jpeg" };
  const oldManifest = { schema_version: 2, items: [photo, description] };
  assertEquals(
    JSON.stringify(parseProtectedEvidenceManifest(oldManifest)),
    JSON.stringify(oldManifest),
  );
});
