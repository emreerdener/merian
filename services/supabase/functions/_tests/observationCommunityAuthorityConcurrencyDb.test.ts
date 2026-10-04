import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const settled = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    (error: unknown) => ({
      ok: false as const,
      error: error instanceof Error ? error.message : "unknown",
    }),
  );
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
  throw new Error("Expected community serialization lock not observed");
}
for (
  const scenario of [
    "duplicate workers",
    "consensus before worker",
    "worker before withdrawal",
    "selection before worker",
    "account deletion first",
    "worker before account deletion",
    "request deletion first",
    "old request cannot bind",
  ]
) {
  Deno.test({
    name: `Community authority DB concurrency - ${scenario}`,
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
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        request = crypto.randomUUID(),
        post = crypto.randomUUID(),
        taxon = crypto.randomUUID();
      const flags = [
        "reader_enabled",
        "enrollment_enabled",
        "saved_import_enabled",
        "state_reader_enabled",
        "selection_enabled",
        "selection_api_enabled",
        "community_authority_enabled",
      ];
      let previous: Record<string, boolean> | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_community_authority.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.split("-- BEGIN COMMUNITY HISTORY HELPERS\n")[1].split(
            "-- END COMMUNITY HISTORY HELPERS",
          )[0],
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
          "SELECT pg_temp.seed_bound_community($1,$2,$3,$4,$5)",
          [
            owner,
            observation,
            request,
            post,
            scenario !== "old request cannot bind",
          ],
        );
        const analysis = (await observer.queryObject<{ id: string }>(
          "SELECT selected_analysis_id AS id FROM internal.observation_histories WHERE observation_id=$1",
          [observation],
        )).rows[0].id;
        await observer.queryArray(
          "INSERT INTO public.taxon_nodes(id,path,rank,scientific_name,taxonomy_version_id) VALUES($1,$2::public.ltree,'genus','Concurrentcommunity',public.active_taxonomy_version_id())",
          [taxon, `community_${taxon.replaceAll("-", "")}`],
        );
        for (const client of clients) {
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,FALSE)",
            [JSON.stringify({ sub: owner, role: "service_role" })],
          );
        }
        const resolve = (client: Client) =>
          client.queryArray(
            "UPDATE public.explore_community_requests SET status='resolved',resolved_at=now(),resolved_taxon_node_id=$1 WHERE id=$2",
            [taxon, request],
          );
        const withdraw = (client: Client) =>
          client.queryArray(
            "UPDATE public.explore_community_requests SET status='needs_id',resolved_at=NULL,resolved_taxon_node_id=NULL WHERE id=$1",
            [request],
          );
        const reconcile = (client: Client) =>
          client.queryObject<{ outcome: string }>(
            "SELECT internal.reconcile_observation_community_authority($1,$2) AS outcome",
            [owner, request],
          );
        if (
          !["consensus before worker", "old request cannot bind"].includes(
            scenario,
          )
        ) await resolve(observer);
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        if (scenario === "consensus before worker") {
          // Consensus holds outbox, then notification insertion can need owner.
          // Worker takes owner first, detects contention and yields without waiting.
          await resolve(first);
          assertEquals((await reconcile(second)).rows[0].outcome, "pending");
          await second.queryArray("COMMIT");
          await first.queryArray("COMMIT");
          assertEquals((await reconcile(observer)).rows[0].outcome, "applied");
        } else if (scenario === "old request cannot bind") {
          await first.queryArray("ROLLBACK");
          await second.queryArray("ROLLBACK");
          // A committed insertion fence is not reusable, including after update.
          const result = await settled(
            observer.queryArray(
              "SELECT internal.bind_observation_community_request($1,$2,$3,$4,1,0)",
              [owner, observation, analysis, request],
            ),
          );
          assert(!result.ok);
          assertEquals(
            result.error,
            "analysis_history_community_requires_new_request",
          );
        } else if (
          scenario === "account deletion first" ||
          scenario === "request deletion first"
        ) {
          if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
            const pending = settled(reconcile(second));
            await blocked(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            const result = await pending;
            assert(!result.ok);
            assertEquals(result.error, "analysis_history_not_found");
            await second.queryArray("ROLLBACK");
          } else {
            await first.queryArray(
              "DELETE FROM public.explore_community_requests WHERE id=$1",
              [request],
            );
            assertEquals((await reconcile(second)).rows[0].outcome, "pending");
            await second.queryArray("COMMIT");
            await first.queryArray("COMMIT");
            assertEquals(
              (await reconcile(observer)).rows[0].outcome,
              "applied",
            );
          }
        } else if (scenario === "selection before worker") {
          const other = crypto.randomUUID();
          await first.queryArray(
            "INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at) SELECT $1,observation_id,2,analysis_id,repeat('d',64),result_snapshot,'{\"schema_version\":1,\"captured_media\":[]}'::jsonb,now() FROM internal.observation_analysis_results WHERE analysis_id=$2",
            [other, analysis],
          );
          await first.queryArray(
            "INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot) SELECT observation_id,$1,review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=$2",
            [other, analysis],
          );
          await first.queryArray(
            "SELECT public.select_owned_observation_analysis($1::jsonb,9)",
            [JSON.stringify({
              schema_version: 1,
              observation_id: observation,
              analysis_id: other,
              operation_id: crypto.randomUUID(),
              expected_observation_revision: 2,
              expected_review_revision: 0,
            })],
          );
          const pending = settled(reconcile(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(result.ok);
          assertEquals(result.value.rows[0].outcome, "applied");
          await second.queryArray("COMMIT");
          const history =
            (await observer.queryObject<{ selected: string; pending: string }>(
              "SELECT selected_analysis_id AS selected, active_projection->>'pending_review' AS pending FROM internal.observation_histories WHERE observation_id=$1",
              [observation],
            )).rows[0];
          assertEquals(history, { selected: other, pending: "true" });
        } else {
          assertEquals((await reconcile(first)).rows[0].outcome, "applied");
          if (scenario === "duplicate workers") {
            const pending = settled(reconcile(second));
            await blocked(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            const result = await pending;
            assert(result.ok);
            assertEquals(result.value.rows[0].outcome, "current");
            await second.queryArray("COMMIT");
          } else {
            const pending = settled(
              scenario === "worker before withdrawal"
                ? withdraw(second)
                : second.queryArray("SELECT public.apply_user_tombstone($1)", [
                  owner,
                ]),
            );
            await blocked(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assert((await pending).ok);
            await second.queryArray("COMMIT");
            if (scenario === "worker before withdrawal") {
              assertEquals(
                (await reconcile(observer)).rows[0].outcome,
                "applied",
              );
            }
          }
        }
        if (
          ["worker before withdrawal", "request deletion first"].includes(
            scenario,
          )
        ) {
          assertEquals(
            (await observer.queryObject<{ pending: string }>(
              "SELECT active_projection->>'pending_review' AS pending FROM internal.observation_histories WHERE observation_id=$1",
              [observation],
            )).rows[0].pending,
            "true",
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
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        await observer.queryArray(
          "DELETE FROM public.taxon_nodes WHERE id=$1",
          [taxon],
        ).catch(() => {});
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
