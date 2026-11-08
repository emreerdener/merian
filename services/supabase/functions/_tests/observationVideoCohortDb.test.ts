import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import inputs from "../_shared/analysisHistory/fixtures/video-source-fingerprint-v1.json" with {
  type: "json",
};
import inventories from "../_shared/analysisHistory/fixtures/video-cohort-inventory-v1.json" with {
  type: "json",
};
import { preparedVideoCohortItems } from "../_shared/analysisHistory/videoCohort.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name: "held video cohort DB projection matches whole ordered inventory",
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
    const read = async (value: unknown) =>
      (await db.queryObject<{ items: unknown }>(
        "SELECT internal.observation_video_source_cohort_items($1::jsonb) items",
        [JSON.stringify(value)],
      )).rows[0].items;
    try {
      for (const [i, vector] of inputs.entries()) {
        assertEquals(await read(vector.input), inventories[i].items);
        assertEquals(
          await read(vector.input),
          preparedVideoCohortItems(vector.input),
        );
      }
      const changed = structuredClone(inputs[0].input);
      changed.evidence_manifest.provenance.frames.reverse();
      for (
        const bad of [null, {}, changed, {
          ...inputs[0].input,
          schema_version: 3,
        }]
      ) await assertRejects(() => read(bad));
      for (const role of ["anon", "authenticated", "service_role"]) {
        await db.queryArray(`SET ROLE ${role}`);
        try {
          await assertRejects(() => read(inputs[0].input));
        } finally {
          await db.queryArray("RESET ROLE");
        }
      }
    } finally {
      await db.end();
    }
  },
});
