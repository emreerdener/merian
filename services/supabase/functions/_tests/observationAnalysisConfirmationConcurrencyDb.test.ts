import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    if (
      (await observer.queryObject<{ blocked: boolean }>(
        "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
        [blocker, waiter],
      )).rows[0].blocked
    ) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected confirmation owner lock not observed");
}
const settled = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    (error: unknown) => ({
      ok: false as const,
      error: error instanceof Error ? error.message : "unknown",
    }),
  );
for (
  const { scenario, candidateMode } of [
    "duplicate",
    "competing confirmation",
    "selection first",
    "confirmation first",
    "rejection first",
    "deletion first",
    "account deletion first",
    "confirmation before deletion",
    "pending intent rebind",
  ].flatMap((scenario) =>
    [false, true].map((candidateMode) => ({ scenario, candidateMode }))
  )
) {
  Deno.test({
    name: `Analysis confirmation DB concurrency - ${
      candidateMode ? "candidate v2" : "name v1"
    } - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [observer, first, second] = clients;
      const owner = crypto.randomUUID(), observation = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "state_reader_enabled",
        "selection_enabled",
        "selection_api_enabled",
        "rejection_api_enabled",
        "confirmation_api_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_saved_enrollment.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.split("-- BEGIN SAVED ENROLLMENT HELPERS\n")[1].split(
            "-- END SAVED ENROLLMENT HELPERS",
          )[0],
        );
        await observer.queryArray(
          "SELECT pg_temp.seed_saved_observation($1,$2,TRUE)",
          [owner, observation],
        );
        previous = (await observer.queryObject<Record<string, boolean>>(
          `SELECT ${
            flags.join(",")
          } FROM internal.observation_history_rollout WHERE singleton`,
        )).rows[0];
        await observer.queryArray(
          `UPDATE internal.observation_history_rollout SET ${
            flags.map((flag) => `${flag}=TRUE`).join(",")
          }`,
        );
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ sub: owner, role: "authenticated" })],
        );
        await observer.queryArray(
          "SELECT public.enroll_owned_observation_history($1,9)",
          [observation],
        );
        let analysis = (await observer.queryObject<{ id: string }>(
          "SELECT selected_analysis_id AS id FROM internal.observation_histories WHERE observation_id=$1",
          [observation],
        )).rows[0].id;
        if (candidateMode) {
          const candidateAnalysis = crypto.randomUUID();
          await observer.queryArray(
            `INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
             SELECT $2,observation_id,2,analysis_id,repeat('c',64),
               result_snapshot||'{"primary_identification":{"version":1,"resolution":"species","scientific_name":"Concurrencyfixture original","common_name":null},"candidates":[{"taxon_rank":"species","scientific_name":"Concurrencyfixture accepted","confidence_score":0.4}]}',
               '{"schema_version":1,"captured_media":[]}',now()
             FROM internal.observation_analysis_results WHERE analysis_id=$1`,
            [analysis, candidateAnalysis],
          );
          await observer.queryArray(
            `INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
             SELECT observation_id,$2,review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=$1`,
            [analysis, candidateAnalysis],
          );
          analysis = candidateAnalysis;
        }
        const request = {
          schema_version: candidateMode ? 2 : 1,
          ...(candidateMode
            ? {
              candidate_reference: {
                version: 1,
                analysis_id: analysis,
                representation: "stored_species_candidates_v1",
                ordinal: 0,
              },
            }
            : {}),
          observation_id: observation,
          analysis_id: analysis,
          operation_id: crypto.randomUUID(),
          expected_observation_revision: 1,
          expected_review_revision: 0,
          action: "confirm_name",
          scientific_name: "Concurrencyfixture accepted",
        };
        const competing = { ...request, operation_id: crypto.randomUUID() };
        const taxon = {
          scientific_name: request.scientific_name,
          gbif_taxon_key: 987699792,
          rank: "SPECIES",
          status: "ACCEPTED",
          kingdom: "Plantae",
        };
        const prepare = (client: Client, intent = request) =>
          client.queryObject<
            { result: { status: string; receipt?: { outcome: string } } }
          >(
            "SELECT public.prepare_observation_analysis_confirmation($1,$2::jsonb,9) AS result",
            [owner, JSON.stringify(intent)],
          );
        const complete = (client: Client, intent = request) =>
          client.queryObject<{ result: { receipt: { outcome: string } } }>(
            "SELECT public.complete_observation_analysis_confirmation($1,$2::jsonb,9,$3,$4::jsonb) AS result",
            [
              owner,
              JSON.stringify(intent),
              intent.scientific_name,
              JSON.stringify(taxon),
            ],
          );
        const select = (client: Client) =>
          client.queryObject<{ result: { receipt: { outcome: string } } }>(
            "SELECT jsonb_build_object('receipt',public.select_owned_observation_analysis($1::jsonb,9)) AS result",
            [JSON.stringify({
              schema_version: 1,
              observation_id: observation,
              analysis_id: analysis,
              operation_id: crypto.randomUUID(),
              expected_observation_revision: 1,
              expected_review_revision: 0,
            })],
          );
        const reject = (client: Client) =>
          client.queryArray(
            "SELECT public.review_owned_observation_analysis($1::jsonb,9)",
            [JSON.stringify({
              ...request,
              scientific_name: undefined,
              schema_version: 1,
              candidate_reference: undefined,
              action: "reject",
              undo_operation_id: null,
              operation_id: crypto.randomUUID(),
            })],
          );
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ sub: owner, role: "service_role" })],
        );
        if (scenario !== "pending intent rebind") await prepare(observer);
        if (scenario === "competing confirmation") {
          await prepare(observer, competing);
        }
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,TRUE)",
            [JSON.stringify({ sub: owner, role: "service_role" })],
          );
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        if (scenario === "pending intent rebind") {
          await prepare(first);
          const pending = settled(
            prepare(second, {
              ...request,
              scientific_name: "Rebound fixture",
            }),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(!result.ok);
          assertEquals(result.error, "analysis_history_operation_conflict");
          await second.queryArray("ROLLBACK");
        } else if (
          scenario === "deletion first" ||
          scenario === "account deletion first"
        ) {
          if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else {
            await first.queryArray(
              "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
              [owner],
            );
            await first.queryArray(
              "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
              [observation, owner],
            );
          }
          const pending = settled(complete(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(!result.ok);
          assertEquals(result.error, "analysis_history_not_found");
          await second.queryArray("ROLLBACK");
          assertEquals(
            (await observer.queryObject<{ n: number }>(
              "SELECT count(*)::int AS n FROM internal.observation_review_receipts WHERE observation_id=$1",
              [observation],
            )).rows[0].n,
            0,
          );
        } else if (scenario === "confirmation before deletion") {
          await complete(first);
          const pending = settled(
            second.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(result.ok);
          await second.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ n: number }>(
              "SELECT count(*)::int AS n FROM internal.observation_confirmation_intents WHERE observation_id=$1",
              [observation],
            )).rows[0].n,
            0,
          );
          const replay = await settled(prepare(observer));
          assert(!replay.ok);
          assertEquals(replay.error, "analysis_history_not_found");
        } else {
          const before = scenario === "selection first"
            ? await select(first)
            : scenario === "rejection first"
            ? await reject(first)
            : await complete(first);
          const pending = settled(
            scenario === "confirmation first" ? select(second) : complete(
              second,
              scenario === "competing confirmation" ? competing : request,
            ),
          );
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const after = await pending;
          assert(after.ok);
          await second.queryArray("COMMIT");
          if (scenario === "duplicate") {
            assertEquals(after.value.rows, before.rows);
          } else {
            const row = after.value.rows[0];
            assertEquals(
              row.result.receipt.outcome,
              "revision_conflict",
            );
          }
          assertEquals(
            (await observer.queryObject<{ revision: number }>(
              "SELECT state_revision AS revision FROM internal.observation_histories WHERE observation_id=$1",
              [observation],
            )).rows[0].revision,
            2,
          );
          assertEquals(
            (await observer.queryObject<{ n: number }>(
              "SELECT count(*)::int AS n FROM internal.observation_history_reconciliation WHERE observation_id=$1",
              [observation],
            )).rows[0].n,
            1,
          );
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              flags.map((flag, i) => `${flag}=$${i + 1}`).join(",")
            }`,
            flags.map((flag) => previous![flag]),
          );
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          owner,
        ])
          .catch(() => {});
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
