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
    "duplicate",
    "foreign",
    "cancel-first",
    "cancel-second",
    "delete-first",
    "delete-second",
    "account-first",
    "account-second",
    "retire-first",
    "read-first",
    "ack-first",
    "ack-second",
  ] as const
) {
  Deno.test({
    name: `IC-1 M1 observed serialization - ${scenario}`,
    ignore: !url,
    async fn() {
      const first = await connect(),
        second = await connect(),
        observer = await connect();
      const owner = crypto.randomUUID(),
        other = crypto.randomUUID(),
        scan = crypto.randomUUID(),
        backend = crypto.randomUUID();
      let digest = "", object = "", claim = "";
      let firstBinding: unknown;
      let previous: {
        enabled: boolean;
        backend: string | null;
        mode: string;
        protocol: number;
      } | undefined;
      const allocate = (db: Client, who = owner) =>
        db.queryObject<{ value: { binding: unknown } }>(
          "SELECT public.allocate_initial_analysis_media($1,$2,$3,$4) AS value",
          [who, scan, digest, backend],
        );
      const retire = (db: Client) =>
        db.queryObject<{ value: Record<string, unknown> }>(
          "SELECT public.retire_initial_analysis_media($1,$2,$3) AS value",
          [
            owner,
            scan,
            digest,
          ],
        );
      const read = (db: Client) =>
        db.queryObject<{ value: Record<string, unknown> }>(
          "SELECT public.get_initial_analysis_media($1,$2,$3) AS value",
          [
            owner,
            scan,
            digest,
          ],
        );
      const cancel = (db: Client) =>
        db.queryArray("SELECT public.cancel_initial_analysis($1,$2)", [
          owner,
          scan,
        ]);
      const ack = (db: Client) =>
        db.queryArray(
          "SELECT public.finish_initial_analysis_media_erasure($1,$2,true)",
          [object, claim],
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
          "INSERT INTO internal.initial_analysis_media_backends VALUES($1,'r2','https://00000000000000000000000000000000.r2.cloudflarestorage.com','synthetic-initial-private','initial-analysis/v1','synthetic_profile')",
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
        await first.queryArray("SELECT pg_temp.admission_owner($1)", [other]);
        await first.queryArray(
          "SELECT pg_temp.admit_initial($1,$2,pg_temp.media_input())",
          [owner, scan],
        );
        digest = (await first.queryObject<{ digest: string }>(
          "SELECT pg_temp.media_digest($1) AS digest",
          [scan],
        )).rows[0].digest;
        if (
          ["retire-first", "read-first", "ack-first", "ack-second"].includes(
            scenario,
          )
        ) {
          await allocate(first);
          // Synthetic elapsed time only; production has no mutation route.
          await first.queryArray(
            "ALTER TABLE internal.initial_analysis_media_cohorts DISABLE TRIGGER guard_initial_media_cohort",
          );
          await first.queryArray(
            "UPDATE internal.initial_analysis_media_cohorts SET binding=jsonb_set(binding,'{expires_at}','1') WHERE scan_id=$1",
            [scan],
          );
          await first.queryArray(
            "ALTER TABLE internal.initial_analysis_media_cohorts ENABLE TRIGGER guard_initial_media_cohort",
          );
        }
        if (scenario.startsWith("ack")) {
          await retire(first);
          object = (await first.queryObject<{ id: string }>(
            "SELECT object_id AS id FROM internal.initial_analysis_media_registry WHERE scan_id=$1 ORDER BY object_id LIMIT 1",
            [scan],
          )).rows[0].id;
          claim = crypto.randomUUID();
          await first.queryArray(
            "UPDATE internal.initial_analysis_media_registry SET claim_token=$2,claim_expires_at=clock_timestamp()+interval '1 minute' WHERE object_id=$1",
            [object, claim],
          );
        }
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        if (scenario === "cancel-first" || scenario === "ack-second") {
          await cancel(first);
        } else if (
          scenario === "delete-first" || scenario === "account-first"
        ) await erase(first);
        else if (scenario === "retire-first") await retire(first);
        else if (scenario === "read-first") await read(first);
        else if (scenario === "ack-first") await ack(first);
        else firstBinding = (await allocate(first)).rows[0].value.binding;
        const action = scenario === "cancel-second" || scenario === "ack-first"
          ? cancel(second)
          : scenario === "delete-second" || scenario === "account-second"
          ? erase(second)
          : scenario === "retire-first"
          ? read(second)
          : scenario === "read-first"
          ? retire(second)
          : scenario === "ack-second"
          ? ack(second)
          : allocate(second, scenario === "foreign" ? other : owner);
        const pending = action.then(
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
        assert(blocked, "race must demonstrably wait on original transaction");
        await first.queryArray("COMMIT");
        const result = await pending;
        const denial = scenario === "foreign" || scenario === "account-first"
          ? "initial_analysis_owner_unavailable"
          : scenario === "cancel-first"
          ? "initial_analysis_cancelled"
          : scenario === "delete-first"
          ? "initial_analysis_deleted"
          : null;
        if (denial) {
          assert(
            result.error instanceof Error &&
              result.error.message.includes(denial),
          );
          await second.queryArray("ROLLBACK");
        } else {
          assertEquals(result.error, null);
          if (scenario === "duplicate") {
            assertEquals(
              (result.value!.rows[0] as { value: { binding: unknown } }).value
                .binding,
              firstBinding,
            );
          } else if (scenario === "retire-first") {
            assertEquals((result.value!.rows[0] as { value: unknown }).value, {
              version: 1,
              outcome: "held",
              reason: "retired",
            });
          } else if (scenario === "read-first") {
            assertEquals((result.value!.rows[0] as { value: unknown }).value, {
              version: 1,
              outcome: "retired",
            });
          }
          await second.queryArray("COMMIT");
        }
        const rows =
          (await first.queryObject<{ count: bigint; retired: bigint }>(
            "SELECT count(*) AS count,count(*) FILTER(WHERE retired) AS retired FROM internal.initial_analysis_media_registry WHERE scan_id=$1",
            [scan],
          )).rows[0];
        const absent = ["cancel-first", "delete-first", "account-first"]
          .includes(scenario);
        assertEquals(rows.count, absent ? 0n : 10n);
        assertEquals(
          rows.retired,
          absent || scenario === "duplicate" || scenario === "foreign"
            ? 0n
            : 10n,
        );
        if (scenario.startsWith("ack")) {
          assertEquals(
            (await first.queryObject<{ confirmed: boolean }>(
              "SELECT marker_confirmed AS confirmed FROM internal.initial_analysis_media_registry WHERE object_id=$1",
              [object],
            )).rows[0].confirmed,
            true,
          );
        }
      } finally {
        await second.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray(
          "ALTER TABLE internal.initial_analysis_media_cohorts ENABLE TRIGGER guard_initial_media_cohort",
        );
        await first.queryArray("SELECT public.apply_user_tombstone($1)", [
          owner,
        ]);
        await first.queryArray(
          "DELETE FROM public.users WHERE id=ANY($1::uuid[])",
          [[owner, other]],
        );
        await first.queryArray(
          "DELETE FROM auth.users WHERE id=ANY($1::uuid[])",
          [[owner, other]],
        );
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
        await Promise.all([first.end(), second.end(), observer.end()]);
      }
    },
  });
}
