import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const lock of ["request", "projection"] as const) {
  Deno.test({
    name: `Scientific retention DB concurrency - busy publication ${lock}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
      );
      const writer = new Client(databaseUrl), holder = new Client(databaseUrl);
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        request = crypto.randomUUID(),
        post = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "state_reader_enabled",
        "selection_enabled",
        "selection_api_enabled",
        "community_authority_enabled",
        "publication_snapshot_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      try {
        await writer.connect();
        await holder.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_publication_snapshots.sql",
            import.meta.url,
          ),
        );
        await writer.queryArray(
          source.split("-- BEGIN PUBLICATION HELPERS\n")[1].split(
            "-- END PUBLICATION HELPERS",
          )[0],
        );
        previous = (await writer.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await writer.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((flag) => `${flag}=TRUE`).join(",")
          }`,
        );
        await writer.queryArray(
          "SELECT pg_temp.seed_publication($1,$2,$3,$4,$5)",
          [owner, observation, request, post, crypto.randomUUID()],
        );
        await writer.queryArray(
          "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',FALSE)",
        );
        await writer.queryArray("SET statement_timeout='3s'");
        await holder.queryArray("BEGIN");
        await holder.queryArray(
          lock === "request"
            ? "SELECT id FROM public.explore_community_requests WHERE id=$1 FOR UPDATE"
            : "SELECT post_id FROM public.explore_analysis_public_projection WHERE post_id=$1 FOR UPDATE",
          [lock === "request" ? request : post],
        );
        let failure: string | undefined;
        try {
          await writer.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
        } catch (error) {
          failure = error instanceof Error ? error.message : "unknown";
        }
        assertEquals(failure, "analysis_history_unavailable");
        const preserved = (await writer.queryObject<
          { owner: boolean; scan: boolean; history: boolean; result: boolean }
        >(
          "SELECT EXISTS(SELECT 1 FROM public.users WHERE id=$1) AS owner, EXISTS(SELECT 1 FROM public.scans WHERE id=$2 AND user_id=$1 AND retained_identification IS NULL AND NOT is_tombstoned) AS scan, EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=$2) AS history, EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=$2) AS result",
          [owner, observation],
        )).rows[0];
        assertEquals(preserved, {
          owner: true,
          scan: true,
          history: true,
          result: true,
        });
        await holder.queryArray("ROLLBACK");
        await writer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]);
        assertEquals(
          (await writer.queryObject<{ retained: boolean }>(
            "SELECT user_id IS NULL AND retained_identification IS NOT NULL AS retained FROM public.scans WHERE id=$1",
            [observation],
          )).rows[0].retained,
          true,
        );
      } finally {
        await holder.queryArray("ROLLBACK").catch(() => {});
        if (previous) {
          await writer.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              flags.map((flag, i) => `${flag}=$${i + 1}`).join(",")
            }`,
            flags.map((flag) => previous![flag]),
          );
        }
        await writer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await writer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        await writer.end().catch(() => {});
        await holder.end().catch(() => {});
      }
    },
  });
}
