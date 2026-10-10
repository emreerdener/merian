import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import fixtures from "../_shared/analysisHistory/fixtures/source-fingerprint-v1.json" with {
  type: "json",
};
import {
  sourceReservationCanonicalBytes,
  sourceReservationFingerprint,
} from "../_shared/analysisHistory/sourceFingerprint.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "Source fingerprint DB parity - fixed bytes, hashes and metadata boundaries",
  ignore: !databaseUrl,
  async fn() {
    assert(
      databaseUrl &&
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
    );
    const db = new Client(databaseUrl);
    await db.connect();
    const read = async (value: unknown) =>
      (await db.queryObject<{ bytes: string; hash: string }>(
        "SELECT encode(internal.observation_source_fingerprint_bytes($1::jsonb),'hex') bytes, internal.observation_source_fingerprint($1::jsonb) hash",
        [JSON.stringify(value)],
      )).rows[0];
    const parity = async (value: unknown) => {
      const result = await read(value);
      assertEquals(
        result.bytes,
        Array.from(
          sourceReservationCanonicalBytes(value),
          (x) => x.toString(16).padStart(2, "0"),
        ).join(""),
      );
      assertEquals(result.hash, await sourceReservationFingerprint(value));
    };
    const denied = async (value: unknown) => {
      assertThrows(() => sourceReservationCanonicalBytes(value));
      await assertRejects(() => read(value));
    };
    try {
      for (const f of fixtures) {
        assertEquals(await read(f.input), {
          bytes: f.canonical_utf8_hex,
          hash: f.sha256,
        });
        await parity(f.input);
      }
      for (
        const text of [
          "\u0085",
          "\u200b",
          "\u180e",
          "x\ufeff",
          "é",
          "e\u0301",
          "🦋",
          "x".repeat(8192),
        ]
      ) {
        const input = structuredClone(fixtures[0].input);
        input.evidence_manifest.items[0].text = text;
        await parity(input);
      }
      for (
        const text of [
          "",
          " \n\t",
          "\u00a0",
          "\ufeff",
          "\u2028\u2029",
          "x".repeat(8193),
          "a\u0000b",
          "a\ud800b",
        ]
      ) {
        const input = structuredClone(fixtures[0].input);
        input.evidence_manifest.items[0].text = text;
        await denied(input);
      }
      for (
        const patch of [
          { schema_version: 1 },
          { schema_version: null },
          { schema_version: true },
          { source_analysis_id: null },
          { source_analysis_id: fixtures[0].input.analysis_id },
          { owner_id: fixtures[0].input.analysis_id },
          { request_digest: "A".repeat(64) },
          { history_protocol: 9 },
          { expected_processor_permission: "recovery_only" },
        ]
      ) {
        await denied({ ...fixtures[0].input, ...patch });
      }
      for (const count of [0, 1.5, true, "46", 5242881]) {
        const input = structuredClone(fixtures[0].input) as unknown as Record<
          string,
          unknown
        >;
        const evidence = input.evidence_manifest as {
          items: Record<string, unknown>[];
        };
        evidence.items[1].byte_count = count;
        await denied(input);
      }
      const audio = structuredClone(fixtures[1].input);
      audio.evidence_manifest.items[1].byte_count = 2700000;
      await parity(audio);
      audio.evidence_manifest.items[1].byte_count = 2700001;
      await denied(audio);
      const alias = structuredClone(fixtures[0].input);
      alias.evidence_manifest.items[1].media_id = alias.source_analysis_id;
      await denied(alias);
      const many = structuredClone(fixtures[0].input);
      many.evidence_manifest.items = Array.from(
        { length: 65 },
        () => many.evidence_manifest.items[0],
      );
      await denied(many);
      const total = structuredClone(fixtures[0].input);
      total.evidence_manifest.items = [
        total.evidence_manifest.items[1],
        ...Array.from(
          { length: 4 },
          () => ({ kind: "description", text: "x".repeat(8000) }),
        ),
      ];
      await parity(total);
      total.evidence_manifest.items.push({ kind: "description", text: "x" });
      await denied(total);
      // JSON numeric spelling must not leak into canonical integer bytes.
      const row = await db.queryObject<{ hash: string }>(
        "SELECT internal.observation_source_fingerprint($1::jsonb) hash",
        [
          JSON.stringify(fixtures[0].input).replace(
            '"byte_count":46',
            '"byte_count":46.0',
          ),
        ],
      );
      assertEquals(row.rows[0].hash, fixtures[0].sha256);
    } finally {
      await db.end();
    }
  },
});
