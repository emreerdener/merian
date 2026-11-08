import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
async function connect(): Promise<Client> {
  assert(url);
  assert(["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname));
  const db = new Client(url);
  await db.connect();
  const sql = await Deno.readTextFile(
    new URL("../../tests/initial_analysis_admission.sql", import.meta.url),
  );
  await db.queryArray(
    sql.split("-- BEGIN INITIAL ADMISSION HELPERS\n")[1].split(
      "-- END INITIAL ADMISSION HELPERS",
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
    "admit-first",
    "cancel-first",
    "duplicate",
    "foreign",
    "delete-first",
    "delete-second",
    "account-first",
    "account-second",
    "shared-counters",
    "save-first",
    "save-second",
  ] as const
) {
  Deno.test({
    name: `IC-1 cancellation serialization - ${scenario}`,
    ignore: !url,
    async fn() {
      const first = await connect(),
        second = await connect(),
        observer = await connect();
      const owner = crypto.randomUUID(), other = crypto.randomUUID();
      const scan = crypto.randomUUID(), otherScan = crypto.randomUUID();
      let previous:
        | { enabled: boolean; mode: string; protocol: number }
        | undefined;
      const cancel = (db: Client, who = owner, id = scan) =>
        db.queryObject<
          { value: { version: number; outcome: string; dispatch: string } }
        >("SELECT public.cancel_initial_analysis($1,$2) AS value", [who, id]);
      const admit = (db: Client, who = owner, id = scan) =>
        db.queryArray("SELECT pg_temp.admit_initial($1,$2)", [who, id]);
      const save = async (db: Client) => {
        await db.queryArray(
          "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code) VALUES($1::text,$2,'failed_terminal','server_replay_limit_reached','replay_exhausted')",
          [scan, owner],
        );
        await db.queryArray(
          "INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture) VALUES($1,$2,'{}',0.8,FALSE,'flash','private',TRUE)",
          [scan, owner],
        );
      };
      const erase = async (db: Client) => {
        if (scenario.startsWith("account")) {
          await db.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
        } else {
          await db.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          await db.queryArray(
            "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||$1::text,0::bigint))",
            [scan],
          );
          await db.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES($1,NULL,now())",
            [scan],
          );
        }
      };
      try {
        previous = (await first.queryObject<
          { enabled: boolean; mode: string; protocol: number }
        >("SELECT initial_analysis_lifecycle_enabled AS enabled,entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.initial_analysis_rollout CROSS JOIN internal.entitlement_rollout_config WHERE config_key='current'"))
          .rows[0];
        await first.queryArray(
          "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE",
        );
        await first.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await first.queryArray("SELECT pg_temp.admission_owner($1)", [owner]);
        await first.queryArray("SELECT pg_temp.admission_owner($1)", [other]);
        if (!["admit-first", "cancel-first"].includes(scenario)) {
          await admit(first);
        }
        if (scenario === "shared-counters") {
          await admit(first, other, otherScan);
        }
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        const pid = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        if (scenario === "admit-first") await admit(first);
        else if (scenario === "save-first") await save(first);
        else if (scenario === "delete-first" || scenario === "account-first") {
          await erase(first);
        } else await cancel(first);
        const action = scenario === "save-second"
          ? save(second)
          : scenario === "cancel-first"
          ? admit(second)
          : scenario === "delete-second" || scenario === "account-second"
          ? erase(second)
          : cancel(
            second,
            scenario === "foreign" || scenario === "shared-counters"
              ? other
              : owner,
            scenario === "shared-counters" ? otherScan : scan,
          );
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
        assert(
          blocked,
          "competing operation must demonstrably block on the first transaction",
        );
        await first.queryArray("COMMIT");
        const result = await pending;
        const errors: Partial<Record<typeof scenario, string>> = {
          "cancel-first": "initial_analysis_identity_conflict",
          foreign: "initial_analysis_owner_unavailable",
          "delete-first": "initial_analysis_deleted",
          "account-first": "initial_analysis_owner_unavailable",
          "save-first": "initial_analysis_already_complete",
          "save-second": "initial_analysis_cancelled",
        };
        if (errors[scenario]) {
          assert(result.error instanceof Error);
          assert(result.error.message.includes(errors[scenario]!));
          await second.queryArray("ROLLBACK");
        } else {
          assertEquals(result.error, null);
          await second.queryArray("COMMIT");
        }
        const state = (await first.queryObject<{ state: string }>(
          "SELECT state FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=$1",
          [scan],
        )).rows[0].state;
        assertEquals(
          state,
          scenario === "save-first"
            ? "pending_pre_dispatch"
            : scenario === "cancel-first" || scenario === "delete-first"
            ? "cancelled_unknown"
            : "cancelled_pre_dispatch",
        );
        const receipts = (await first.queryObject<{ count: bigint }>(
          "SELECT count(*) FROM internal.initial_analysis_cancellations WHERE scan_id=$1",
          [scan],
        )).rows[0].count;
        assertEquals(
          receipts,
          scenario.startsWith("delete") || scenario.startsWith("account") ||
            scenario === "save-first"
            ? 0n
            : 1n,
        );
        const quotas =
          (await first.queryObject<{ state: string; refund_count: number }>(
            "SELECT state,refund_count FROM internal.ai_quota_reservations WHERE request_id=$1",
            [scan],
          )).rows;
        assertEquals(
          quotas,
          scenario.startsWith("account") || scenario === "cancel-first"
            ? []
            : [{
              state: scenario === "delete-first" || scenario === "save-first"
                ? "reserved"
                : "refunded",
              refund_count:
                scenario === "delete-first" || scenario === "save-first"
                  ? 0
                  : 1,
            }],
        );
        if (scenario === "shared-counters") {
          assertEquals(
            (await first.queryObject<{ state: string; refund_count: number }>(
              "SELECT state,refund_count FROM internal.ai_quota_reservations WHERE request_id=$1",
              [otherScan],
            )).rows,
            [{ state: "refunded", refund_count: 1 }],
          );
        }
        assertEquals(
          (await first.queryObject<{ count: bigint }>(
            "SELECT count(*) FROM internal.initial_analysis_submissions WHERE scan_id=$1",
            [scan],
          )).rows[0].count,
          scenario === "save-first" ? 1n : 0n,
        );
      } finally {
        await second.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray("ROLLBACK").catch(() => {});
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
            "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=$1",
            [previous.enabled],
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
