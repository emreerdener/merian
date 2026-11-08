import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
async function connect(): Promise<Client> {
  assert(url);
  assert(["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname));
  const db = new Client(url);
  await db.connect();
  const sql = await Deno.readTextFile(
    new URL(
      "../../tests/initial_analysis_media_allocation.sql",
      import.meta.url,
    ),
  );
  await db.queryArray(
    sql.split("-- BEGIN INITIAL MEDIA HELPERS\n")[1].split(
      "-- END INITIAL MEDIA HELPERS",
    )[0],
  );
  await db.queryArray("SET statement_timeout='10s'");
  await db.queryArray(
    "SELECT set_config('request.jwt.claim.role','service_role',false)",
  );
  return db;
}
for (
  const scenario of [
    "claim-duplicate",
    "settle-duplicate",
    "cancel-first",
    "cancel-second",
    "delete-first",
    "delete-second",
    "account-first",
    "account-second",
    "retire-first",
    "settle-first",
    "reclaim-first",
  ] as const
) {
  Deno.test({
    name: `IC-1 M2 observed serialization - ${scenario}`,
    ignore: !url,
    async fn() {
      const first = await connect(),
        second = await connect(),
        observer = await connect();
      const owner = crypto.randomUUID(),
        scan = crypto.randomUUID(),
        backend = crypto.randomUUID();
      let digest = "", manifest = "", token = "";
      let previous: {
        enabled: boolean;
        backend: string | null;
        mode: string;
        protocol: number;
      } | undefined;
      const action = (db: Client, name: string) =>
        db.queryObject<{ value: Record<string, unknown> }>(
          `SELECT public.${name}($1,$2,$3,$4${
            name === "settle_initial_media_verification" ? ",$5" : ""
          }) AS value`,
          [
            owner,
            scan,
            digest,
            manifest,
            ...(name === "settle_initial_media_verification" ? [token] : []),
          ],
        );
      const claim = (db: Client) =>
        action(db, "claim_initial_media_preparation");
      const settle = (db: Client) =>
        action(db, "settle_initial_media_verification");
      const retire = (db: Client) =>
        db.queryObject<{ value: Record<string, unknown> }>(
          "SELECT public.retire_initial_analysis_media($1,$2,$3) AS value",
          [owner, scan, digest],
        );
      const cancel = (db: Client) =>
        db.queryObject<{ value: Record<string, unknown> }>(
          "SELECT public.cancel_initial_analysis($1,$2) AS value",
          [owner, scan],
        );
      const erase = async (db: Client) => {
        if (scenario.startsWith("account")) {
          return await db.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
        }
        await db.queryArray(
          "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
          [owner],
        );
        await db.queryArray(
          "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||$1::text,0::bigint))",
          [scan],
        );
        return await db.queryArray(
          "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES($1,NULL,clock_timestamp())",
          [scan],
        );
      };
      const expire = async (db: Client, cohort: boolean) => {
        await db.queryArray(
          "ALTER TABLE internal.initial_analysis_media_preparations DISABLE TRIGGER guard_initial_media_preparation",
        );
        await db.queryArray(
          "UPDATE internal.initial_analysis_media_preparations SET issued_at=1,expires_at=2 WHERE scan_id=$1",
          [scan],
        );
        await db.queryArray(
          "ALTER TABLE internal.initial_analysis_media_preparations ENABLE TRIGGER guard_initial_media_preparation",
        );
        if (cohort) {
          await db.queryArray(
            "ALTER TABLE internal.initial_analysis_media_cohorts DISABLE TRIGGER guard_initial_media_cohort",
          );
          await db.queryArray(
            "UPDATE internal.initial_analysis_media_cohorts SET binding=jsonb_set(binding,'{expires_at}','1') WHERE scan_id=$1",
            [scan],
          );
          await db.queryArray(
            "ALTER TABLE internal.initial_analysis_media_cohorts ENABLE TRIGGER guard_initial_media_cohort",
          );
        }
      };
      try {
        previous = (await first.queryObject<
          {
            enabled: boolean;
            backend: string | null;
            mode: string;
            protocol: number;
          }
        >("SELECT initial_analysis_lifecycle_enabled AS enabled,media_backend_generation AS backend,entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.initial_analysis_rollout CROSS JOIN internal.entitlement_rollout_config WHERE config_key='current'"))
          .rows[0];
        await first.queryArray(
          "INSERT INTO internal.initial_analysis_media_backends VALUES($1,'r2','https://00000000000000000000000000000000.r2.cloudflarestorage.com','synthetic-private','initial-analysis/v1','synthetic_profile')",
          [backend],
        );
        await first.queryArray(
          "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=true,media_backend_generation=$1",
          [backend],
        );
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await first.queryArray("SELECT pg_temp.admission_owner($1)", [owner]);
        await first.queryArray(
          "SELECT pg_temp.admit_initial($1,$2,pg_temp.media_input())",
          [owner, scan],
        );
        digest = (await first.queryObject<{ digest: string }>(
          "SELECT pg_temp.media_digest($1) AS digest",
          [scan],
        )).rows[0].digest;
        const allocation = (await first.queryObject<
          { value: { binding: { manifest_digest: string } } }
        >(
          "SELECT public.allocate_initial_analysis_media($1,$2,$3,$4) AS value",
          [owner, scan, digest, backend],
        )).rows[0].value;
        manifest = allocation.binding.manifest_digest;
        if (scenario !== "claim-duplicate") {
          token =
            ((await claim(first)).rows[0].value.claim as { token: string })
              .token;
        }
        if (
          scenario === "retire-first" || scenario === "reclaim-first"
        ) await expire(first, scenario === "retire-first");
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        let receipt: unknown;
        if (scenario === "cancel-first") await cancel(first);
        else if (
          scenario === "delete-first" || scenario === "account-first"
        ) await erase(first);
        else if (scenario === "retire-first") await retire(first);
        else if (
          scenario === "claim-duplicate" || scenario === "reclaim-first"
        ) await claim(first);
        else {
          receipt = (await settle(first)).rows[0].value.receipt;
          if (scenario === "settle-first") await expire(first, true);
        }
        const promise = scenario === "cancel-second"
          ? cancel(second)
          : scenario === "delete-second" || scenario === "account-second"
          ? erase(second)
          : scenario === "settle-first"
          ? retire(second)
          : scenario === "claim-duplicate"
          ? claim(second)
          : settle(second);
        const pending = promise.then(
          (value) => ({ value, error: null }),
          (error: unknown) => ({ value: null, error }),
        );
        let blocked = false;
        for (let i = 0; i < 150; i++) {
          if (
            (await observer.queryObject<{ blocked: boolean }>(
              "SELECT cardinality(pg_blocking_pids($1))>0 AS blocked",
              [pid],
            )).rows[0].blocked
          ) {
            blocked = true;
            break;
          }
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
        assert(blocked, "race must actually wait on original transaction");
        await first.queryArray("COMMIT");
        const result = await pending;
        const denial = scenario === "cancel-first"
          ? "initial_analysis_cancelled"
          : scenario === "delete-first"
          ? "initial_analysis_deleted"
          : scenario === "account-first"
          ? "initial_analysis_owner_unavailable"
          : null;
        if (denial) {
          assert(
            result.error instanceof Error &&
              result.error.message.includes(denial),
          );
          await second.queryArray("ROLLBACK");
        } else {
          assertEquals(result.error, null);
          const value = (result.value!.rows[0] as
            | { value: Record<string, unknown> }
            | undefined)?.value;
          if (scenario === "claim-duplicate") {
            assertEquals(value, {
              version: 1,
              outcome: "held",
              reason: "busy",
            });
          }
          if (scenario === "settle-duplicate") {
            assertEquals(value, { version: 1, outcome: "replay", receipt });
          }
          if (scenario === "retire-first") {
            assertEquals(value, {
              version: 1,
              outcome: "held",
              reason: "retired",
            });
          }
          if (scenario === "settle-first") {
            assertEquals(value, {
              version: 1,
              outcome: "held",
              reason: "in_use",
            });
          }
          if (scenario === "reclaim-first") {
            assertEquals(value, {
              version: 1,
              outcome: "held",
              reason: "stale",
            });
          }
          await second.queryArray("COMMIT");
        }
        const survivors = (await first.queryObject<{ count: bigint }>(
          "SELECT count(*) FROM internal.initial_analysis_media_verifications WHERE scan_id=$1",
          [scan],
        )).rows[0].count;
        assertEquals(
          survivors,
          scenario === "settle-first" || scenario === "settle-duplicate"
            ? 1n
            : 0n,
        );
        const retired = (await first.queryObject<{ all_retired: boolean }>(
          "SELECT bool_and(retired) AS all_retired FROM internal.initial_analysis_media_registry WHERE scan_id=$1",
          [scan],
        )).rows[0].all_retired;
        assertEquals(
          retired,
          scenario.startsWith("cancel") || scenario.startsWith("delete") ||
            scenario.startsWith("account") || scenario === "retire-first",
        );
      } finally {
        await second.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray(
          "ALTER TABLE internal.initial_analysis_media_preparations ENABLE TRIGGER guard_initial_media_preparation",
        );
        await first.queryArray(
          "ALTER TABLE internal.initial_analysis_media_cohorts ENABLE TRIGGER guard_initial_media_cohort",
        );
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]);
        await first.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
        if (previous) {
          await first.queryArray(
            "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=$1,media_backend_generation=$2",
            [previous.enabled, previous.backend],
          );
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
            [previous.mode, previous.protocol],
          );
        }
        await first.end();
        await second.end();
        await observer.end();
      }
    },
  });
}
