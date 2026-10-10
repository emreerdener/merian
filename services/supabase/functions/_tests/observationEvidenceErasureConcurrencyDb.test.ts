import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const retirement =
  "SELECT public.retire_expired_observation_evidence() AS count";
const settle = <T>(promise: Promise<T>) =>
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
  throw new Error("Expected canonical evidence lock was not observed");
}

Deno.test({
  name:
    "Private evidence erasure DB concurrency - claims skip a locked obligation",
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
    const objects = [crypto.randomUUID(), crypto.randomUUID()];
    let gate = false;
    try {
      for (const client of clients) await client.connect();
      gate = (await observer.queryObject<{ enabled: boolean }>(
        "SELECT private_evidence_erasure_enabled AS enabled FROM internal.observation_history_rollout WHERE singleton",
      )).rows[0].enabled;
      await observer.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE",
      );
      await observer.queryArray(
        "INSERT INTO internal.observation_evidence_erasure(object_id,available_at) VALUES($1,'1970-01-01'),($2,'1970-01-01')",
        objects,
      );
      const claims: {
        object_id: string;
        claim_token: string;
        claim_expires_at: string;
      }[] = [];
      for (const client of [first, second]) {
        await client.queryArray("BEGIN");
        await client.queryArray("SET LOCAL statement_timeout='3s'");
        await client.queryArray("SET LOCAL ROLE service_role");
        claims.push(
          (await client.queryObject<{ value: typeof claims[number] }>(
            "SELECT public.claim_observation_evidence_erasure() AS value",
          )).rows[0].value,
        );
      }
      assertEquals(
        claims.map((claim) => claim.object_id).sort(),
        objects.sort(),
      );
      assert(claims[0].claim_token !== claims[1].claim_token);
      for (const client of [first, second]) await client.queryArray("COMMIT");
      await observer.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=FALSE",
      );
      await first.queryArray("BEGIN");
      await first.queryArray("SET LOCAL ROLE service_role");
      assertEquals(
        (await first.queryObject<{ success: boolean }>(
          "SELECT public.finish_observation_evidence_erasure($1,$2,TRUE) AS success",
          [claims[0].object_id, claims[0].claim_token],
        )).rows[0].success,
        true,
      );
      await first.queryArray("COMMIT");
    } finally {
      for (const client of clients) {
        await client.queryArray("ROLLBACK").catch(() => {});
      }
      await observer.queryArray(
        "UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=$1",
        [gate],
      );
      await observer.queryArray(
        "DELETE FROM internal.observation_evidence_erasure WHERE object_id IN ($1,$2)",
        objects,
      );
      await Promise.all(clients.map((client) => client.end()));
    }
  },
});

for (
  const scenario of [
    "duplicate retirement",
    "retirement before replay",
    "deletion first",
    "admission first",
  ]
) {
  Deno.test({
    name: `Private evidence erasure DB concurrency - ${scenario}`,
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
      const owner = crypto.randomUUID(),
        observation = crypto.randomUUID(),
        analysis = crypto.randomUUID(),
        media = crypto.randomUUID();
      const items = [{
        media_id: media,
        content_type: "image/jpeg",
        byte_count: 3,
        sha256: "a".repeat(64),
      }];
      const reserve =
        "SELECT public.reserve_owned_observation_evidence_cohort($1,$2,$3,$4::jsonb) AS value";
      let object: string | undefined;
      let gates: Record<string, boolean> | undefined;
      let entitlement: { mode: string; protocol: number } | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_protected_analysis.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split("-- BEGIN PROTECTED ANALYSIS HELPERS\n")[1]
          ?.split("-- END PROTECTED ANALYSIS HELPERS")[0];
        assert(helpers);
        for (const client of [observer, first]) {
          await client.queryArray(helpers);
        }
        gates = (await observer.queryObject<{ value: Record<string, boolean> }>(
          "SELECT to_jsonb(r) AS value FROM internal.observation_history_rollout r WHERE singleton",
        )).rows[0].value;
        await observer.queryArray("SELECT pg_temp.seed_funded_history($1,$2)", [
          owner,
          observation,
        ]);
        entitlement =
          (await observer.queryObject<{ mode: string; protocol: number }>(
            "SELECT entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
          )).rows[0];
        await observer.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET media_enabled=TRUE,private_evidence_erasure_enabled=TRUE,admission_enabled=TRUE,protected_analysis_enabled=TRUE",
        );
        await observer.queryArray("BEGIN");
        await observer.queryArray("SET LOCAL ROLE service_role");
        const receipts =
          (await observer.queryObject<{ value: { object_id: string }[] }>(
            reserve,
            [owner, observation, analysis, JSON.stringify(items)],
          )).rows[0].value;
        object = receipts[0].object_id;
        await observer.queryArray("COMMIT");
        await observer.queryArray(
          "SELECT internal.complete_observation_evidence($1,$2,$3,$4,$5)",
          [owner, observation, analysis, media, object],
        );
        // Fixture-only clock positioning; source immutability remains enabled.
        await observer.queryArray("BEGIN");
        await observer.queryArray(
          "ALTER TABLE internal.observation_evidence_upload_cohorts DISABLE TRIGGER guard_observation_upload_cohort",
        );
        await observer.queryArray(
          "ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update",
        );
        const delta = scenario === "admission first"
          ? "3 seconds"
          : "-1 minute";
        await observer.queryArray(
          "UPDATE internal.observation_evidence_upload_cohorts SET expires_at=transaction_timestamp()+$2::interval WHERE analysis_id=$1",
          [analysis, delta],
        );
        await observer.queryArray(
          "UPDATE internal.observation_evidence_objects SET expires_at=(SELECT expires_at FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=$1) WHERE analysis_id=$1",
          [analysis],
        );
        await observer.queryArray(
          "ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE TRIGGER guard_observation_upload_cohort",
        );
        await observer.queryArray(
          "ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update",
        );
        await observer.queryArray("COMMIT");
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
        if (scenario === "deletion first") {
          await first.queryArray(
            "SELECT internal.lock_owned_observation_evidence($1,$2)",
            [owner, observation],
          );
          await first.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        } else if (scenario === "admission first") {
          await first.queryArray(
            "SELECT internal.admit_protected_observation_analysis($1,pg_temp.protected_input($2,$3,$4),repeat('a',64))",
            [owner, observation, analysis, media],
          );
          await observer.queryArray(
            "SELECT pg_sleep(GREATEST(0,extract(epoch FROM expires_at-clock_timestamp()))+0.05) FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=$1",
            [analysis],
          );
        } else {
          await first.queryArray("SET LOCAL ROLE service_role");
          assertEquals(
            (await first.queryObject<{ count: number }>(retirement)).rows[0]
              .count,
            1,
          );
        }
        await second.queryArray("SET LOCAL ROLE service_role");
        const pending = settle(
          scenario === "retirement before replay"
            ? second.queryObject(reserve, [
              owner,
              observation,
              analysis,
              JSON.stringify(items),
            ])
            : second.queryObject<{ count: number }>(retirement),
        );
        await blocked(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        const result = await pending;
        assertEquals(result.ok, scenario !== "retirement before replay");
        if (result.ok) assertEquals(result.value.rows, [{ count: 0 }]);
        await second.queryArray("ROLLBACK");
        const state = (await observer.queryObject<
          { receipts: number; cohorts: number; erasures: number }
        >(
          "SELECT (SELECT count(*)::int FROM internal.observation_evidence_objects WHERE analysis_id=$1) AS receipts,(SELECT count(*)::int FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=$1) AS cohorts,(SELECT count(*)::int FROM internal.observation_evidence_erasure WHERE object_id=$2) AS erasures",
          [analysis, object],
        )).rows[0];
        assertEquals(state, {
          receipts: scenario === "admission first" ? 1 : 0,
          cohorts: scenario === "deletion first" ? 0 : 1,
          erasures: scenario === "admission first" ? 0 : 1,
        });
      } finally {
        for (const client of clients) {
          await client.queryArray("ROLLBACK").catch(() => {});
        }
        if (gates) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET media_enabled=$1,private_evidence_erasure_enabled=$2,admission_enabled=$3,protected_analysis_enabled=$4",
            [
              gates.media_enabled,
              gates.private_evidence_erasure_enabled,
              gates.admission_enabled,
              gates.protected_analysis_enabled,
            ],
          );
        }
        if (entitlement) {
          await observer.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [entitlement.mode, entitlement.protocol],
          );
        }
        await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
          observation,
        ]);
        await observer.queryArray(
          "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
          [observation],
        );
        if (object) {
          await observer.queryArray(
            "DELETE FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [object],
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
