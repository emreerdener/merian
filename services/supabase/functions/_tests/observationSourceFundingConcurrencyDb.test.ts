import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected source storage lock not observed");
}
for (
  const scenario of [
    "binding before quota",
    "quota before binding",
    "repeatable read quota",
    "binding before invocation",
    "invocation before binding",
    "repeatable read invocation",
  ]
) {
  Deno.test({
    name: `Source funding DB concurrency - ${scenario}`,
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
      const otherOwner = crypto.randomUUID(),
        otherObservation = crypto.randomUUID();
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        source = crypto.randomUUID(),
        child = crypto.randomUUID();
      let invocation: {
        reservation: string;
        owner_id: string;
        token: string;
        scan: string;
      } | undefined;
      let previous: boolean | undefined;
      let pending: Promise<boolean> | undefined;
      try {
        for (const client of clients) await client.connect();
        const fixture = await Deno.readTextFile(
          new URL(
            "../../tests/observation_source_funding.sql",
            import.meta.url,
          ),
        );
        const helpers =
          fixture.split("-- BEGIN SOURCE FUNDING HELPERS\n")[1].split(
            "-- END SOURCE FUNDING HELPERS",
          )[0];
        for (const client of clients) await client.queryArray(helpers);
        previous = (await observer.queryObject<{ enabled: boolean }>(
          "SELECT append_enabled AS enabled FROM internal.observation_history_rollout WHERE singleton",
        )).rows[0].enabled;
        await observer.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
          otherOwner,
          otherObservation,
        ]);
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET append_enabled=TRUE",
        );
        await observer.queryArray(
          "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
          [owner, observation, source],
        );
        if (scenario.includes("invocation")) {
          invocation = (await observer.queryObject<
            {
              reservation: string;
              owner_id: string;
              token: string;
              scan: string;
            }
          >("SELECT * FROM pg_temp.seed_invocation()")).rows[0];
        }
        for (const client of [first, second]) {
          await client.queryArray(
            scenario.startsWith("repeatable read")
              ? "BEGIN ISOLATION LEVEL REPEATABLE READ"
              : "BEGIN",
          );
          await client.queryArray("SET LOCAL statement_timeout='10s'");
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const insert = (client: Client, analysis: string) =>
          client.queryArray("SELECT pg_temp.store_source($1,$2,$3,$4)", [
            owner,
            observation,
            source,
            analysis,
          ]);
        if (scenario.includes("invocation")) {
          assert(invocation);
          if (scenario === "invocation before binding") {
            await first.queryArray(
              "UPDATE internal.ai_quota_reservations SET original_analysis_id=$1 WHERE id=$2",
              [child, invocation.reservation],
            );
            const dispatch =
              (await first.queryObject<{ may_dispatch: boolean }>(
                "SELECT * FROM pg_temp.commit_invocation($1,$2,$3,1)",
                [invocation.reservation, invocation.owner_id, invocation.token],
              )).rows[0];
            assert(dispatch.may_dispatch);
            pending = insert(second, child).then(() => true, (error) => {
              assertEquals(error.fields?.code, "22023");
              return false;
            });
            await blocked(observer, waiter, blocker);
            await first.queryArray("COMMIT");
            assertEquals(await pending, false);
            await second.queryArray("ROLLBACK");
            return;
          }

          if (!scenario.startsWith("repeatable read")) {
            await insert(first, child);
            await second.queryArray(
              "UPDATE internal.ai_quota_reservations SET original_analysis_id=$1 WHERE id=$2",
              [child, invocation.reservation],
            );
          }
          const call = second.queryArray(
            "SELECT * FROM pg_temp.commit_invocation($1,$2,$3,1)",
            [invocation.reservation, invocation.owner_id, invocation.token],
          );
          pending = call.then(() => true, (error) => {
            assertEquals(
              error.fields?.code,
              scenario.startsWith("repeatable read") ? "25000" : "55000",
            );
            return false;
          });
          if (!scenario.startsWith("repeatable read")) {
            await blocked(observer, waiter, blocker);
            await first.queryArray("COMMIT");
          }
          assertEquals(await pending, false);
          await second.queryArray("ROLLBACK");
          const state = (await observer.queryObject<{ state: string }>(
            "SELECT state FROM internal.ai_quota_reservations WHERE id=$1",
            [invocation.reservation],
          )).rows[0].state;
          assertEquals(state, "reserved");
          return;
        }
        const quota = (client: Client) =>
          client.queryArray(
            "SELECT * FROM internal.reserve_ai_quota_core($1,'scan_identification',$2,repeat('a',64),$3,FALSE,3,FALSE)",
            [otherOwner, crypto.randomUUID(), child],
          );
        if (scenario.startsWith("repeatable read")) {
          await quota(second).then(() => {
            throw new Error("Frozen snapshot accepted");
          }, (error) => {
            assertEquals(error.fields?.code, "25000");
          });
          return;
        }
        const bindingFirst = scenario.startsWith("binding");
        await (bindingFirst ? insert(first, child) : quota(first));
        pending = (bindingFirst ? quota(second) : insert(second, child)).then(
          () => true,
          (error) => {
            assertEquals(error.fields?.code, bindingFirst ? "55000" : "22023");
            return false;
          },
        );
        await blocked(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        assertEquals(await pending, false);
        await second.queryArray("ROLLBACK");
        const count =
          (await observer.queryObject<{ bindings: string; quota: string }>(
            "SELECT (SELECT count(*) FROM internal.observation_analysis_source_bindings WHERE analysis_id=$1)::text AS bindings,(SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id=$1)::text AS quota",
            [child],
          )).rows[0];
        assertEquals(
          count,
          bindingFirst
            ? { bindings: "1", quota: "0" }
            : { bindings: "0", quota: "1" },
        );
      } finally {
        for (const client of [first, second]) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        await pending;
        if (previous !== undefined) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET append_enabled=$1,enrollment_enabled=FALSE",
            [previous],
          );
        }
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
          .catch(() => {});
        await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
          otherOwner,
        ]).catch(() => {});
        await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
          otherOwner,
        ]).catch(() => {});
        if (invocation) {
          await observer.queryArray("SELECT public.apply_user_tombstone($1)", [
            invocation.owner_id,
          ]).catch(() => {});
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            invocation.owner_id,
          ]).catch(() => {});
        }
        for (const client of clients) await client.end().catch(() => {});
      }
    },
  });
}
