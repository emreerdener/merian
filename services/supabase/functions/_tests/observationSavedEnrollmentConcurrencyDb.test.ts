import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const settled = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected enrollment lock not observed");
}
for (
  const scenario of [
    "duplicate import",
    "deletion first",
    "account deletion first",
    "import first",
  ]
) {
  Deno.test({
    name: `Saved history enrollment DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
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
          "SELECT reader_enabled,enrollment_enabled,saved_import_enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0];
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE",
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
        const enroll = (client: Client) =>
          client.queryObject<{ receipt: { baseline_analysis_id: string } }>(
            "SELECT public.enroll_owned_observation_history($1,9) AS receipt",
            [observation],
          );
        const erase = async (client: Client) => {
          await client.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          await client.queryArray(
            "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||$1::text,0::bigint))",
            [observation],
          );
          await client.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
          await client.queryArray("DELETE FROM public.scans WHERE id=$1", [
            observation,
          ]);
        };
        if (scenario === "duplicate import") {
          const original = await enroll(first);
          const pending = settled(enroll(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          const result = await pending;
          assert(result.ok);
          assertEquals(result.value.rows[0].receipt, original.rows[0].receipt);
          await second.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_analysis_results WHERE observation_id=$1",
              [observation],
            )).rows[0].count,
            1,
          );
        } else if (scenario === "import first") {
          const original = await enroll(first);
          const pending = settled(erase(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assert((await pending).ok);
          await second.queryArray("COMMIT");
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.scan_deletion_tombstones WHERE scan_id=$1 AND user_id IS NULL",
              [original.rows[0].receipt.baseline_analysis_id],
            )).rows[0].count,
            1,
          );
        } else {
          if (scenario === "deletion first") await erase(first);
          else {await first.queryArray(
              "SELECT public.apply_user_tombstone($1)",
              [owner],
            );}
          const pending = settled(enroll(second));
          await blocked(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals((await pending).ok, false);
          await second.queryArray("ROLLBACK");
        }
        if (scenario !== "duplicate import") {
          assertEquals(
            (await observer.queryObject<{ count: number }>(
              "SELECT count(*)::int AS count FROM internal.observation_histories WHERE observation_id=$1",
              [observation],
            )).rows[0].count,
            0,
          );
        }
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (previous) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET reader_enabled=$1,enrollment_enabled=$2,saved_import_enabled=$3",
            [
              previous.reader_enabled,
              previous.enrollment_enabled,
              previous.saved_import_enabled,
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
