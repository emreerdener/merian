import {
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import {
  sourceReservationCanonicalBytes,
  sourceReservationFingerprint,
} from "./sourceFingerprint.ts";
import fixtures from "./fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
const fresh = (n = 0) => structuredClone(fixtures[n].input);
const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (x) => x.toString(16).padStart(2, "0")).join("");

Deno.test("source fingerprint matches fixed UTF8 framing and SHA golden vectors", async () => {
  for (const fixture of fixtures) {
    assertEquals(
      hex(sourceReservationCanonicalBytes(fixture.input)),
      fixture.canonical_utf8_hex,
    );
    assertEquals(
      await sourceReservationFingerprint(fixture.input),
      fixture.sha256,
    );
  }
});
Deno.test("source fingerprint ignores JSON key order without rewriting original bytes", async () => {
  const input = fresh(), original = JSON.stringify(input);
  const reversed = JSON.parse(
    JSON.stringify(input),
    (_key, value) =>
      value && typeof value === "object" && !Array.isArray(value)
        ? Object.fromEntries(Object.entries(value).reverse())
        : value,
  );
  assertEquals(
    await sourceReservationFingerprint(reversed),
    await sourceReservationFingerprint(input),
  );
  assertEquals(JSON.stringify(input), original);
  assertEquals(input.request_digest, "b".repeat(64));
});
Deno.test("source fingerprint binds order, identities, descriptions, processor and media metadata", async () => {
  const baseline = await sourceReservationFingerprint(fresh());
  for (
    const change of [
      (x: ReturnType<typeof fresh>) => {
        x.evidence_manifest.items.reverse();
      },
      (x: ReturnType<typeof fresh>) => {
        x.analysis_id = "00000000-0000-4000-8000-000000000005";
      },
      (x: ReturnType<typeof fresh>) => {
        x.source_analysis_id = "00000000-0000-4000-8000-000000000006";
      },
      (x: ReturnType<typeof fresh>) => {
        x.request_digest = "c".repeat(64);
      },
      (x: ReturnType<typeof fresh>) => {
        x.expected_processor_permission = "google_gemini";
      },
      (x: ReturnType<typeof fresh>) => {
        x.evidence_manifest.items[0].text = "Before e\u0301 / : , 🦋\n";
      },
      (x: ReturnType<typeof fresh>) => {
        x.evidence_manifest.items[1].sha256 = "c".repeat(64);
      },
      (x: ReturnType<typeof fresh>) => {
        x.evidence_manifest.items[1].byte_count = 47;
      },
    ]
  ) {
    const input = fresh();
    change(input);
    assertNotEquals(await sourceReservationFingerprint(input), baseline);
  }
});
Deno.test("source fingerprint snapshots input before asynchronous hash", async () => {
  const input = fresh();
  const pending = sourceReservationFingerprint(input);
  input.evidence_manifest.items.reverse();
  input.request_digest = "c".repeat(64);
  assertEquals(await pending, fixtures[0].sha256);
});
Deno.test("source fingerprint rejects unsupported fresh shapes and identity aliases", async () => {
  for (
    const patch of [
      { schema_version: 1 },
      { schema_version: 4 },
      { source_analysis_id: null },
      { source_analysis_id: fresh().analysis_id },
      { owner_id: fresh().analysis_id },
      { input_profile: "multimodal_audio_v1" },
      { request_digest: "A".repeat(64) },
      { entitlement_protocol: 2 },
      { history_protocol: 9 },
    ]
  ) {
    await assertRejects(() =>
      sourceReservationFingerprint({ ...fresh(), ...patch })
    );
  }
  const alias = fresh();
  alias.evidence_manifest.items[1].media_id = alias.source_analysis_id;
  assertThrows(() => sourceReservationCanonicalBytes(alias));
});
Deno.test("source fingerprint refuses NUL and lone surrogates instead of changing text", () => {
  for (const text of ["a\u0000b", "a\ud800b", "a\udfffb"]) {
    const input = fresh();
    input.evidence_manifest.items[0].text = text;
    assertThrows(() => sourceReservationCanonicalBytes(input));
  }
});
Deno.test("source fingerprint enforces existing media count and description bounds", () => {
  const input = fresh();
  input.evidence_manifest.items[0].text = "x".repeat(8193);
  assertThrows(() => sourceReservationCanonicalBytes(input));
  const many = fresh();
  many.evidence_manifest.items = Array.from(
    { length: 65 },
    () => many.evidence_manifest.items[0],
  );
  assertThrows(() => sourceReservationCanonicalBytes(many));
  const audio = fresh(1);
  audio.expected_processor_permission = "openai";
  assertThrows(() => sourceReservationCanonicalBytes(audio));
});
