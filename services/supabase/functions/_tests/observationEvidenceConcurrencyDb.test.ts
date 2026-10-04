import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const completeSQL =
  "SELECT internal.complete_observation_evidence($1,$2,$3,$4,$5) AS receipt";
const settle = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
async function waitForBlock(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int = ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected evidence lock was not observed");
}

for (
  const scenario of [
    "duplicate completion",
    "deletion first",
    "completion first",
    "account deletion first",
  ]
) {
  Deno.test({
    name: `Observation evidence DB concurrency - ${scenario}`,
    ignore: !databaseUrl,
    async fn() {
      assert(databaseUrl);
      assert(
        ["127.0.0.1", "localhost", "[::1]"].includes(
          new URL(databaseUrl).hostname,
        ),
        "Requires disposable loopback DB",
      );
      const clients = [
        new Client(databaseUrl),
        new Client(databaseUrl),
        new Client(databaseUrl),
      ];
      const [observer, first, second] = clients;
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        analysis = crypto.randomUUID(),
        media = crypto.randomUUID();
      const args = [owner, observation, analysis, media];
      let objectId: string | undefined;
      let oldGate = false;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_append.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split(
          "-- BEGIN HISTORY APPEND SYNTHETIC HELPERS\n",
        )[1]?.split("-- END HISTORY APPEND SYNTHETIC HELPERS")[0];
        assert(helpers);
        await observer.queryArray(helpers);
        oldGate = (await observer.queryObject<{ enabled: boolean }>(
          "SELECT media_enabled AS enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0].enabled;
        await observer.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET media_enabled=TRUE",
        );
        objectId = (await observer.queryObject<{ object_id: string }>(
          "SELECT internal.reserve_observation_evidence($1,$2,$3,$4,'image/jpeg',3,repeat('a',64))->>'object_id' AS object_id",
          args,
        )).rows[0].object_id;
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
        const fence = async (client: Client) => {
          await client.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          await client.queryArray(
            "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || $1::text,0::bigint))",
            [observation],
          );
          await client.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        };
        if (scenario.endsWith("deletion first")) {
          if (scenario === "account deletion first") {
            await first.queryArray("SELECT public.apply_user_tombstone($1)", [
              owner,
            ]);
          } else await fence(first);
          const pending = settle(
            second.queryObject(completeSQL, [...args, objectId]),
          );
          await waitForBlock(observer, waiter, blocker);
          await first.queryArray("COMMIT");
          assertEquals((await pending).ok, false);
          await second.queryArray("ROLLBACK");
        } else {
          const saved =
            (await first.queryObject<{ receipt: unknown }>(completeSQL, [
              ...args,
              objectId,
            ]))
              .rows[0].receipt;
          if (scenario === "completion first") {
            const pending = settle(fence(second));
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assert((await pending).ok);
            await second.queryArray("COMMIT");
          } else {
            const pending = settle(
              second.queryObject<{ receipt: unknown }>(completeSQL, [
                ...args,
                objectId,
              ]),
            );
            await waitForBlock(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            const result = await pending;
            assert(result.ok);
            await second.queryArray("COMMIT");
            assertEquals(result.value.rows[0].receipt, saved);
          }
        }
        const state =
          (await observer.queryObject<{ objects: number; erasures: number }>(
            "SELECT (SELECT count(*)::int FROM internal.observation_evidence_objects WHERE media_id=$1) AS objects,(SELECT count(*)::int FROM internal.observation_evidence_erasure WHERE object_id=$2) AS erasures",
            [media, objectId],
          )).rows[0];
        assertEquals(
          state,
          scenario === "duplicate completion"
            ? { objects: 1, erasures: 0 }
            : { objects: 0, erasures: 1 },
        );
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET media_enabled=$1",
          [oldGate],
        );
        await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
          observation,
        ]);
        await observer.queryArray(
          "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
          [observation],
        );
        if (objectId) {
          await observer.queryArray(
            "DELETE FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [objectId],
          );
        }
        await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
          owner,
        ]);
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          owner,
        ]);
        await Promise.all(clients.map((client) => client.end()));
      }
    },
  });
}

for (const reservationFirst of [true, false]) {
  Deno.test({
    name:
      `Observation evidence DB concurrency - cross-owner append collision, reserve first ${reservationFirst}`,
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
      const owners = [crypto.randomUUID(), crypto.randomUUID()],
        observations = [crypto.randomUUID(), crypto.randomUUID()],
        analysis = crypto.randomUUID(),
        media = crypto.randomUUID();
      let gates = { media_enabled: false, append_enabled: false };
      let objectId: string | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_append.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split(
          "-- BEGIN HISTORY APPEND SYNTHETIC HELPERS\n",
        )[1]?.split("-- END HISTORY APPEND SYNTHETIC HELPERS")[0];
        assert(helpers);
        for (const client of clients) await client.queryArray(helpers);
        gates = (await observer.queryObject<typeof gates>(
          "SELECT media_enabled,append_enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0];
        for (let i = 0; i < 2; i++) {
          await observer.queryArray(
            "SELECT pg_temp.seed_history_append($1,$2)",
            [owners[i], observations[i]],
          );
        }
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET media_enabled=TRUE,append_enabled=TRUE",
        );
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
        }
        const blocker = (await first.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid,
          waiter = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
        const reserve = async (client: Client) => {
          const result = await client.queryObject<{ object_id: string }>(
            "SELECT internal.reserve_observation_evidence($1,$2,$3,$4,'image/jpeg',3,repeat('a',64))->>'object_id' AS object_id",
            [owners[0], observations[0], analysis, media],
          );
          objectId = result.rows[0].object_id;
        };
        const append = (client: Client) =>
          client.queryArray(
            "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
            [owners[1], observations[1], analysis],
          );
        if (reservationFirst) await reserve(first);
        else await append(first);
        const pending = settle<unknown>(
          reservationFirst ? append(second) : reserve(second),
        );
        await waitForBlock(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        assertEquals((await pending).ok, false);
        await second.queryArray("ROLLBACK");
        const state =
          (await observer.queryObject<{ objects: number; results: number }>(
            "SELECT (SELECT count(*)::int FROM internal.observation_evidence_objects WHERE analysis_id=$1) AS objects,(SELECT count(*)::int FROM internal.observation_analysis_results WHERE analysis_id=$1) AS results",
            [analysis],
          )).rows[0];
        assertEquals(
          state,
          reservationFirst
            ? { objects: 1, results: 0 }
            : { objects: 0, results: 1 },
        );
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET media_enabled=$1,append_enabled=$2",
          [gates.media_enabled, gates.append_enabled],
        );
        for (let i = 0; i < 2; i++) {
          await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
            observations[i],
          ]);
          await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
            owners[i],
          ]);
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owners[i],
          ]);
        }
        if (objectId) {
          await observer.queryArray(
            "DELETE FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [objectId],
          );
        }
        await Promise.all(clients.map((client) => client.end()));
      }
    },
  });
}
