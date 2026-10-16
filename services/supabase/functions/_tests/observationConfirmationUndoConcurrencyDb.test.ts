import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const scenario of ["duplicate", "competing", "selection", "deletion"]) {
  Deno.test({
    name: `Confirmation Undo DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
      );
      const [setup, first, second] = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const owner = crypto.randomUUID(), observation = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "state_reader_enabled",
        "selection_enabled",
        "selection_api_enabled",
        "confirmation_api_enabled",
        "confirmation_undo_api_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      try {
        for (const client of [setup, first, second]) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_saved_enrollment.sql",
            import.meta.url,
          ),
        );
        await setup.queryArray(
          source.split("-- BEGIN SAVED ENROLLMENT HELPERS\n")[1].split(
            "-- END SAVED ENROLLMENT HELPERS",
          )[0],
        );
        await setup.queryArray(
          "SELECT pg_temp.seed_saved_observation($1,$2,TRUE)",
          [owner, observation],
        );
        previous = (await setup.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await setup.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((f) => `${f}=TRUE`).join(",")
          }`,
        );
        await setup.queryArray(
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ sub: owner, role: "authenticated" })],
        );
        await setup.queryArray(
          "SELECT public.enroll_owned_observation_history($1,9)",
          [observation],
        );
        const analysis = (await setup.queryObject<{ id: string }>(
          "SELECT selected_analysis_id AS id FROM internal.observation_histories WHERE observation_id=$1",
          [observation],
        )).rows[0].id;
        const confirmation = {
          schema_version: 1,
          observation_id: observation,
          analysis_id: analysis,
          operation_id: crypto.randomUUID(),
          expected_observation_revision: 1,
          expected_review_revision: 0,
          action: "confirm_name",
          scientific_name: "Concurrencyfixture accepted",
        };
        await setup.queryArray(
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ role: "service_role" })],
        );
        await setup.queryArray(
          "SELECT public.prepare_observation_analysis_confirmation($1,$2::jsonb,9)",
          [owner, JSON.stringify(confirmation)],
        );
        await setup.queryArray(
          "SELECT public.complete_observation_analysis_confirmation($1,$2::jsonb,9,$3,$4::jsonb)",
          [
            owner,
            JSON.stringify(confirmation),
            confirmation.scientific_name,
            JSON.stringify({
              scientific_name: confirmation.scientific_name,
              gbif_taxon_key: 987699792,
              rank: "SPECIES",
              status: "ACCEPTED",
              kingdom: "Plantae",
            }),
          ],
        );
        const request = {
          schema_version: 1,
          observation_id: observation,
          analysis_id: analysis,
          operation_id: crypto.randomUUID(),
          expected_observation_revision: 2,
          expected_review_revision: 1,
          action: "undo_confirmation",
          undo_operation_id: confirmation.operation_id,
        };
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,TRUE)",
            [JSON.stringify({ sub: owner, role: "authenticated" })],
          );
        }
        const undo = (client: Client, input = request) =>
          client.queryObject<{ result: { outcome: string } }>(
            "SELECT public.review_owned_observation_analysis($1::jsonb,9) AS result",
            [JSON.stringify(input)],
          );
        await first.queryArray(
          "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
          [owner],
        );
        const pid = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const pending = undo(
          second,
          scenario === "competing"
            ? { ...request, operation_id: crypto.randomUUID() }
            : request,
        ).then((value) => ({ value }), (error) => ({ error }));
        let observed = false;
        for (let n = 0; n < 100; n++) {
          if (
            (await setup.queryObject<{ blocked: boolean }>(
              "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
              [pid, waiter],
            )).rows[0].blocked
          ) {
            observed = true;
            break;
          }
          await new Promise((r) => setTimeout(r, 20));
        }
        assert(observed, "canonical owner lock must serialize contenders");
        if (scenario === "deletion") {
          await first.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        } else if (scenario === "selection") {
          await first.queryArray(
            "SELECT public.select_owned_observation_analysis($1::jsonb,9)",
            [JSON.stringify({
              schema_version: 1,
              observation_id: observation,
              analysis_id: analysis,
              operation_id: crypto.randomUUID(),
              expected_observation_revision: 2,
              expected_review_revision: 1,
            })],
          );
        } else {assertEquals(
            (await undo(first)).rows[0].result.outcome,
            "applied",
          );}
        await first.queryArray("COMMIT");
        const settled = await pending;
        if (scenario === "deletion") {
          assert("error" in settled);
          await second.queryArray("ROLLBACK");
        } else {
          assert("value" in settled);
          assertEquals(
            settled.value.rows[0].result.outcome,
            scenario === "duplicate" ? "applied" : "revision_conflict",
          );
          await second.queryArray("COMMIT");
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await setup.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              flags.map((f, n) => `${f}=$${n + 1}`).join(",")
            }`,
            flags.map((f) => previous![f]),
          );
        }
        await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        for (const client of [setup, first, second]) await client.end();
      }
    },
  });
}
