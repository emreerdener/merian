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
  throw new Error("Expected observation state lock not observed");
}
const settled = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
for (
  const scenario of [
    "review first",
    "read first",
    "deletion first",
    "account deletion first",
  ]
) {
  Deno.test({
    name: `Observation state read DB concurrency - ${scenario}`,
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
      let previous: {
        reader_enabled: boolean;
        enrollment_enabled: boolean;
        saved_import_enabled: boolean;
        state_reader_enabled: boolean;
      } | undefined;
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
          "SELECT pg_temp.seed_saved_observation($1,$2)",
          [owner, observation],
        );
        previous = (await observer.queryObject<NonNullable<typeof previous>>(
          "SELECT reader_enabled,enrollment_enabled,saved_import_enabled,state_reader_enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0];
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,state_reader_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT set_config('request.jwt.claims',$1,FALSE)",
          [JSON.stringify({ sub: owner, role: "authenticated" })],
        );
        await observer.queryArray(
          "SELECT public.enroll_owned_observation_history($1,9)",
          [observation],
        );
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
          await client.queryArray(
            "SELECT set_config('request.jwt.claims',$1,TRUE)",
            [JSON.stringify({ sub: owner, role: "authenticated" })],
          );
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const read = (client: Client) =>
          client.queryObject<
            {
              state: {
                state_revision: number;
                analysis: { review_revision: number };
              };
            }
          >(
            "SELECT public.get_owned_observation_analysis_state($1::jsonb,9) AS state",
            [JSON.stringify({
              schema_version: 1,
              observation_id: observation,
              analysis_id: null,
            })],
          );
        const review = (client: Client) =>
          client.queryArray(
            'UPDATE internal.observation_analysis_authorities SET review_revision=1,review_snapshot=review_snapshot||\'{"user_identification_override":"Changed fixture","user_review_state":"user_overridden"}\' WHERE observation_id=$1',
            [observation],
          );
        if (scenario === "read first") {
          const before = (await read(first)).rows[0].state;
          const pending = settled(review(second));
          await blocked(observer, waiter, blocker);
          assertEquals(
            [before.state_revision, before.analysis.review_revision],
            [1, 0],
          );
          await first.queryArray("COMMIT");
          assert((await pending).ok);
          await second.queryArray("COMMIT");
          const after = (await read(observer)).rows[0].state;
          assertEquals([after.state_revision, after.analysis.review_revision], [
            2,
            1,
          ]);
        } else {
          if (scenario === "review first") await review(first);
          else if (scenario === "account deletion first") {
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
          const pending = settled(read(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          if (scenario === "review first") {
            assert(result.ok);
            assertEquals([
              result.value.rows[0].state.state_revision,
              result.value.rows[0].state.analysis.review_revision,
            ], [2, 1]);
            await second.queryArray("COMMIT");
          } else {
            assertEquals(result.ok, false);
            await second.queryArray("ROLLBACK");
          }
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET reader_enabled=$1,enrollment_enabled=$2,saved_import_enabled=$3,state_reader_enabled=$4",
            [
              previous.reader_enabled,
              previous.enrollment_enabled,
              previous.saved_import_enabled,
              previous.state_reader_enabled,
            ],
          );
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
