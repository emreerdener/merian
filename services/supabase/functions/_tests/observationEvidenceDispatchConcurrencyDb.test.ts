import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { evidenceDispatchFixture } from "./observationEvidenceDispatchFixture.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const claimSql =
  "SELECT public.claim_observation_evidence_erasure_for_dispatch($1) value";
type Claim = { object_id: string; claim_token: string };
async function blocked(db: Client, waiter: number, blocker: number) {
  for (let i = 0; i < 100; i++) {
    if (
      (await db.queryObject<{ yes: boolean }>(
        "SELECT $1::int=ANY(pg_blocking_pids($2::int)) yes",
        [blocker, waiter],
      )).rows[0].yes
    ) return;
    await new Promise((r) => setTimeout(r, 20));
  }
  throw new Error("Expected dispatch singleton barrier was not observed");
}

for (const operation of ["rotate", "pause"] as const) {
  for (const firstAction of ["acquire", "control"] as const) {
    Deno.test({
      name: `private dispatch singleton: ${operation}, ${firstAction} wins`,
      ignore: !url,
      async fn() {
        assert(
          url &&
            ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
        );
        const clients = [new Client(url), new Client(url), new Client(url)];
        const [observer, first, second] = clients;
        const object = crypto.randomUUID();
        let fixture:
          | Awaited<ReturnType<typeof evidenceDispatchFixture>>
          | undefined;
        let gate: boolean | undefined;
        try {
          for (const db of clients) await db.connect();
          fixture = await evidenceDispatchFixture(observer);
          gate = (await observer.queryObject<{ enabled: boolean }>(
            "SELECT private_evidence_erasure_enabled enabled FROM internal.observation_history_rollout WHERE singleton",
          )).rows[0].enabled;
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE",
          );
          await observer.queryArray(
            "INSERT INTO internal.observation_evidence_erasure(object_id,available_at) VALUES($1,'1970-01-01')",
            [object],
          );
          const controlSql = operation === "pause"
            ? "UPDATE internal.observation_evidence_worker_state SET enabled=FALSE WHERE singleton"
            : "UPDATE internal.observation_evidence_worker_state SET pending_dispatch_id='00000000-0000-4000-8000-00000000ee99' WHERE singleton";
          for (const db of [first, second]) {
            await db.queryArray("BEGIN; SET LOCAL statement_timeout='10s'");
          }
          const firstPid = (await first.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() pid",
          )).rows[0].pid;
          const secondPid = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() pid",
          )).rows[0].pid;
          let original: Claim | undefined;
          if (firstAction === "acquire") {
            await first.queryArray("SET LOCAL ROLE service_role");
            original = (await first.queryObject<{ value: Claim }>(claimSql, [
              fixture.dispatch,
            ])).rows[0].value;
            assertEquals(original.object_id, object);
          } else {
            await first.queryArray(controlSql);
            await second.queryArray("SET LOCAL ROLE service_role");
          }
          const pending = (firstAction === "acquire"
            ? second.queryArray(controlSql)
            : second.queryObject(claimSql, [fixture.dispatch])).then(
              () => ({ ok: true, code: undefined }),
              (error) => ({ ok: false, code: error.fields?.code }),
            );
          await blocked(observer, secondPid, firstPid);
          await first.queryArray("COMMIT");
          const outcome = await pending;
          assertEquals(
            outcome,
            firstAction === "acquire"
              ? { ok: true, code: undefined }
              : { ok: false, code: "42501" },
          );
          await second.queryArray(
            firstAction === "acquire" ? "COMMIT" : "ROLLBACK",
          );
          const saved = (await observer.queryObject<{ token: string | null }>(
            "SELECT claim_token token FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [object],
          )).rows[0];
          assertEquals(saved.token, original?.claim_token ?? null);
          if (original) {
            // Current dispatch can lose admission while an original claim settles.
            await observer.queryArray(
              "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=FALSE",
            );
            await first.queryArray("BEGIN; SET LOCAL ROLE service_role");
            assertEquals(
              (await first.queryObject<{ value: boolean }>(
                "SELECT public.finish_observation_evidence_erasure($1,$2,TRUE) value",
                [object, original.claim_token],
              )).rows[0].value,
              true,
            );
            await first.queryArray("COMMIT");
          }
        } finally {
          for (const db of clients) {
            await db.queryArray("ROLLBACK").catch(() => {});
          }
          await observer.queryArray(
            "DELETE FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [object],
          );
          if (gate !== undefined) {
            await observer.queryArray(
              "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=$1",
              [gate],
            );
          }
          await fixture?.restore();
          await Promise.all(clients.map((db) => db.end()));
        }
      },
    });
  }
}

Deno.test({
  name:
    "same dispatch permits bounded reclaim but rejects the expired original token",
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
      const fixture = await evidenceDispatchFixture(db);
      await db.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE",
      );
      const object = crypto.randomUUID();
      const backlog = crypto.randomUUID();
      await db.queryArray(
        "INSERT INTO internal.observation_evidence_erasure(object_id,available_at) VALUES($1,'1970-01-01'),($2,'1971-01-01')",
        [object, backlog],
      );
      await db.queryArray("SET LOCAL ROLE service_role");
      const first =
        (await db.queryObject<{ value: Claim }>(claimSql, [fixture.dispatch]))
          .rows[0].value;
      assertEquals(first.object_id, object);
      // A live lease excludes this object, not other eligible backlog.
      assertEquals(
        (await db.queryObject<{ value: Claim }>(claimSql, [fixture.dispatch]))
          .rows[0].value.object_id,
        backlog,
      );
      await db.queryArray("RESET ROLE");
      // Privileged local clock positioning only; no production lease rewrite.
      await db.queryArray(
        "UPDATE internal.observation_evidence_erasure SET claim_expires_at=clock_timestamp()-interval '1 second' WHERE object_id=$1",
        [object],
      );
      await db.queryArray("SET LOCAL ROLE service_role");
      const second =
        (await db.queryObject<{ value: Claim }>(claimSql, [fixture.dispatch]))
          .rows[0].value;
      assertEquals(first.object_id, second.object_id);
      assert(first.claim_token !== second.claim_token);
      for (
        const [token, expected] of [[first.claim_token, false], [
          second.claim_token,
          true,
        ]] as const
      ) {
        assertEquals(
          (await db.queryObject<{ value: boolean }>(
            "SELECT public.finish_observation_evidence_erasure($1,$2,TRUE) value",
            [object, token],
          )).rows[0].value,
          expected,
        );
      }
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});
