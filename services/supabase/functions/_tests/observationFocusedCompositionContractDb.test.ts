import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import vectors from "../_shared/analysisHistory/fixtures/composition-request-v6.json" with {
  type: "json",
};
import {
  focusedCompositionFingerprint,
  focusedCompositionRequestDigest,
} from "../_shared/analysisHistory/compositionFingerprint.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");

Deno.test({
  name:
    "focused composition SQL and Edge agree on typed request and source fingerprints",
  ignore: !databaseUrl,
  async fn() {
    assert(
      databaseUrl &&
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
    );
    const db = new Client(databaseUrl);
    await db.connect();
    const read = async (raw: string) =>
      (await db.queryObject<{
        contract: {
          fingerprint: string;
          request_digest: string;
          items: unknown[];
        };
      }>(
        "SELECT internal.observation_focused_composition_contract($1::jsonb) contract",
        [raw],
      )).rows[0].contract;
    const parity = async (raw: string, constructDigest = true) => {
      const input = JSON.parse(raw);
      let expected;
      try {
        if (constructDigest) {
          const computed = await focusedCompositionRequestDigest(input);
          raw = raw.replace(input.request_digest, computed);
          input.request_digest = computed;
        }
        expected = {
          fingerprint: await focusedCompositionFingerprint(input),
          request_digest: await focusedCompositionRequestDigest(input),
        };
      } catch {
        await assertRejects(() => read(raw));
        return;
      }
      const actual = await read(raw);
      assertEquals(actual.fingerprint, expected.fingerprint);
      assertEquals(actual.request_digest, expected.request_digest);
    };
    try {
      for (const vector of vectors) {
        const raw = JSON.stringify(vector.input);
        await parity(raw);
        const actual = await read(raw);
        assertEquals(actual.fingerprint, vector.fingerprint, vector.name);
        assertEquals(actual.request_digest, vector.request_digest, vector.name);
      }
      const raw = JSON.stringify(vectors[0].input);
      await parity(
        raw.replace(vectors[0].input.request_digest, "f".repeat(64)),
        false,
      );
      await parity(raw.replace('"schema_version":6', '"schema_version":5'));
      for (
        const value of [
          "1e-1",
          "0.10000000000000001",
          "-0",
          "5e-324",
          "3e-324",
          "4e-324",
          "2.4703282292062327e-324",
          "2.4703282292062328e-324",
          "-2.4703282292062327e-324",
          "-2.4703282292062328e-324",
          "1e-400",
          "-1e-400",
          "1e309",
        ]
      ) {
        await parity(raw.replace('"x":0.1', `"x":${value}`));
      }
      for (const field of ["x", "y", "width", "height", "source"]) {
        for (const value of [null, true, "invalid", [], {}]) {
          const input = JSON.parse(raw);
          input.evidence_manifest.items[0].focus_region[field] = value;
          await parity(JSON.stringify(input));
        }
        const input = JSON.parse(raw);
        delete input.evidence_manifest.items[0].focus_region[field];
        await parity(JSON.stringify(input));
      }
      for (
        const focus of [null, {}, {
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          source: "user_selection",
          extra: true,
        }]
      ) {
        const input = JSON.parse(raw);
        input.evidence_manifest.items[0].focus_region = focus;
        await parity(JSON.stringify(input));
      }
      for (const role of ["anon", "authenticated", "service_role"]) {
        await db.queryArray(`SET ROLE ${role}`);
        try {
          await assertRejects(() => read(raw));
        } finally {
          await db.queryArray("RESET ROLE");
        }
      }
    } finally {
      await db.end();
    }
  },
});
