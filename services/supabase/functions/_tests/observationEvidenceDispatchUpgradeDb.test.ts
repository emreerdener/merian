import { assert, assertEquals, assertRejects } from "@std/assert";
import {
  Client,
  PostgresError,
} from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const names = [
  "retire_expired_observation_evidence",
  "retire_expired_observation_video_evidence",
  "claim_observation_evidence_erasure",
];

Deno.test({
  name:
    "actual cleanup migration preserves legacy OIDs and denies warmed SQL plans",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const db = new Client(url);
    await db.connect();
    await db.queryArray("BEGIN");
    try {
      await db.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=FALSE",
      );
      const oids = async () =>
        (await db.queryObject<{ name: string; oid: string }>(
          "SELECT proname name,oid::text oid FROM pg_proc WHERE pronamespace='public'::regnamespace AND pronargs=0 AND proname=ANY($1::text[]) ORDER BY proname",
          [names],
        )).rows;
      const original = await oids();
      assertEquals(original.length, 3);
      // Controlled effective-body reconstruction, not a historical-schema replay.
      for (const name of names) {
        const definition = (await db.queryObject<{ value: string }>(
          "SELECT pg_get_functiondef($1::regprocedure) value",
          [`internal.${name}_worker_impl()`],
        )).rows[0].value;
        assert(definition.includes(`FUNCTION internal.${name}_worker_impl()`));
        await db.queryArray(
          definition.replace(
            `FUNCTION internal.${name}_worker_impl()`,
            `FUNCTION public.${name}()`,
          ),
        );
        await db.queryArray(
          `GRANT EXECUTE ON FUNCTION public.${name}() TO service_role;
          DROP FUNCTION public.${name}_for_dispatch(uuid);
          DROP FUNCTION internal.${name}_worker_impl();`,
        );
        await db.queryArray(
          "DELETE FROM internal.privileged_routine_grants WHERE role_name='service_role' AND routine_signature=$1",
          [`public.${name}_for_dispatch(uuid)`],
        );
        await db.queryArray(
          "INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose) VALUES('service_role',$1,'Rollback-only legacy reconstruction')",
          [`public.${name}()`],
        );
      }
      await db.queryArray(
        "DROP FUNCTION internal.require_observation_evidence_dispatch(uuid); SET LOCAL plan_cache_mode=force_generic_plan",
      );
      for (const [index, name] of names.entries()) {
        await db.queryArray(
          `PREPARE warmed_${index} AS SELECT public.${name}()`,
        );
      }
      await db.queryArray("SET LOCAL ROLE service_role");
      for (const index of names.keys()) {
        assertEquals((await db.queryArray(`EXECUTE warmed_${index}`)).rows, [[
          index === 2 ? null : 0,
        ]]);
      }
      await db.queryArray("RESET ROLE");
      assertEquals(
        (await db.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM pg_prepared_statements WHERE name IN ('warmed_0','warmed_1','warmed_2') AND generic_plans=1",
        )).rows[0].n,
        3,
      );
      // Read through the Deno fixture owner: pg_prove does not mount migrations.
      const migration = await Deno.readTextFile(
        new URL(
          "../../migrations/20261112003746_fence_legacy_private_cleanup_acquisition.sql",
          import.meta.url,
        ),
      );
      await db.queryArray(migration);
      assertEquals(await oids(), original);
      const denied = async (query: string, message?: string) => {
        await db.queryArray("SAVEPOINT denied_call");
        const error = await assertRejects(
          () => db.queryArray(query),
          PostgresError,
        );
        assertEquals(error.fields.code, "42501");
        if (message) assertEquals(error.fields.message, message);
        await db.queryArray(
          "ROLLBACK TO SAVEPOINT denied_call; RELEASE SAVEPOINT denied_call",
        );
      };
      await db.queryArray("SET LOCAL ROLE service_role");
      for (const index of names.keys()) await denied(`EXECUTE warmed_${index}`);
      await db.queryArray("RESET ROLE");
      for (const name of names) {
        await denied(
          `SELECT public.${name}()`,
          "legacy_private_evidence_acquisition_denied",
        );
      }
      for (const index of names.keys()) {
        await db.queryArray(`DEALLOCATE warmed_${index}`);
      }
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});
