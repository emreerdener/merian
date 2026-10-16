import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const url = Deno.env.get("SUPABASE_DB_TEST_URL");
const cases = [
  "pre-row owner",
  "pre-row fence",
  "funded account",
  "funded raw owner",
] as const;
for (const scenario of cases) {
  for (const deletionFirst of [false, true]) {
    Deno.test({
      name: `Initial storage DB - ${scenario}, ${
        deletionFirst ? "deletion" : "result"
      } first`,
      ignore: !url,
      async fn() {
        assert(url);
        assert(
          ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
        );
        const first = new Client(url),
          second = new Client(url),
          observer = new Client(url);
        const [owner, scan, source, child, media] = Array.from(
          { length: 5 },
          () => crypto.randomUUID(),
        );
        let flags: Record<string, boolean> | undefined;
        let entitlement: { mode: string; protocol: number } | undefined;
        let gate: boolean | undefined;
        let fixtureObjectIds: string[] = [];
        const funded = scenario.startsWith("funded");
        try {
          await first.connect();
          await second.connect();
          await observer.connect();
          const helperText = await Deno.readTextFile(
            new URL(
              "../../tests/initial_analysis_storage.sql",
              import.meta.url,
            ),
          );
          const helpers =
            helperText.split("-- BEGIN INITIAL STORAGE HELPERS\n")[1].split(
              "-- END INITIAL STORAGE HELPERS",
            )[0];
          for (const client of [first, second]) {
            await client.queryArray(helpers);
            await client.queryArray("SET statement_timeout='10s'");
            await client.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false)",
            );
          }
          gate = (await first.queryObject<{ value: boolean }>(
            "SELECT initial_analysis_lifecycle_enabled AS value FROM internal.initial_analysis_rollout",
          )).rows[0].value;
          await first.queryArray(
            "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE",
          );
          if (funded) {
            flags = (await first.queryObject<Record<string, boolean>>(
              "SELECT append_enabled,media_enabled,prepared_audio_evidence_enabled,admission_enabled,protected_analysis_enabled,audio_analysis_enabled FROM internal.observation_history_rollout",
            )).rows[0];
            entitlement =
              (await first.queryObject<{ mode: string; protocol: number }>(
                "SELECT entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
              )).rows[0];
            await first.queryArray(
              "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
            );
            await first.queryArray(
              "UPDATE internal.observation_history_rollout SET append_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,admission_enabled=TRUE,protected_analysis_enabled=TRUE,audio_analysis_enabled=TRUE",
            );
            const sourceText = await Deno.readTextFile(
              new URL(
                "../../tests/observation_source_initial_admission.sql",
                import.meta.url,
              ),
            );
            const sourceHelpers = sourceText.split(
              "-- BEGIN SOURCE ADMISSION HELPERS\n",
            )[1].split("-- END SOURCE ADMISSION HELPERS")[0]
              .replace(
                "    INSERT INTO public.scan_ingestion_jobs",
                "    PERFORM pg_temp.initial_submission(owner_id,observation);\n    INSERT INTO public.scan_ingestion_jobs",
              );
            await first.queryArray(sourceHelpers);
            const input = (await first.queryObject<{ value: unknown }>(
              "SELECT pg_temp.seed_bound_admission($1,$2,$3,$4,$5,2) AS value",
              [owner, scan, source, child, media],
            )).rows[0].value;
            fixtureObjectIds = (await first.queryObject<{ object_id: string }>(
              "SELECT object_id FROM internal.observation_evidence_objects WHERE owner_id=$1 AND analysis_id=$2",
              [owner, child],
            )).rows.map((row) => row.object_id);
            await first.queryArray("SELECT pg_temp.admit_bound($1,$2::jsonb)", [
              owner,
              JSON.stringify(input),
            ]);
            assertEquals(
              (await first.queryObject<{ count: bigint }>(
                "SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id=$1 AND state='admitted'",
                [child],
              )).rows[0].count,
              1n,
            );
          } else {
            await first.queryArray("SELECT pg_temp.initial_owner($1)", [owner]);
            await first.queryArray("SELECT pg_temp.initial_submission($1,$2)", [
              owner,
              scan,
            ]);
          }
          const erase = async (client: Client) => {
            if (scenario === "pre-row fence") {
              await client.queryArray(
                "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
                [owner],
              );
              await client.queryArray(
                "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:' || $1::text,0::bigint))",
                [scan],
              );
              await client.queryArray(
                "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES($1,NULL,now())",
                [scan],
              );
            } else if (scenario === "funded account") {
              await client.queryArray(
                "SELECT public.apply_user_tombstone($1)",
                [owner],
              );
            } else {
              if (funded) {
                // Raw deletion must fail without partial erasure. Then use the
                // supported detachment API under the same transaction scope.
                await client.queryArray("SAVEPOINT raw_delete");
                const denial = await client.queryArray(
                  "DELETE FROM public.users WHERE id=$1",
                  [owner],
                ).then(() => null, (error: unknown) => error);
                assert(denial instanceof Error);
                assert(
                  denial.message.includes(
                    "initial_analysis_account_detachment_required",
                  ),
                );
                await client.queryArray("ROLLBACK TO SAVEPOINT raw_delete");
                assertEquals(
                  (await client.queryObject<{ count: bigint }>(
                    "SELECT count(*) FROM internal.initial_analysis_submissions WHERE scan_id=$1",
                    [scan],
                  )).rows[0].count,
                  1n,
                );
                assertEquals(
                  (await client.queryObject<{ count: bigint }>(
                    "SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id=$1",
                    [child],
                  )).rows[0].count,
                  1n,
                );
                await client.queryArray(
                  "SELECT public.apply_user_tombstone($1)",
                  [owner],
                );
              } else {
                await client.queryArray(
                  "DELETE FROM public.users WHERE id=$1",
                  [owner],
                );
              }
            }
          };
          const save = async (client: Client) => {
            await client.queryArray("SELECT pg_temp.initial_result($1,$2)", [
              owner,
              scan,
            ]);
            await client.queryArray("SELECT pg_temp.initial_receipt($1,$2)", [
              owner,
              scan,
            ]);
          };
          await first.queryArray("BEGIN");
          await second.queryArray("BEGIN");
          const secondPid = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() AS pid",
          )).rows[0].pid;
          await (deletionFirst ? erase(first) : save(first));
          const pending = (deletionFirst ? save(second) : erase(second)).then(
            () => null,
            (error: unknown) => error,
          );
          let blocked = false;
          for (let attempt = 0; attempt < 100; attempt++) {
            const row = (await observer.queryObject<{ blocked: boolean }>(
              "SELECT cardinality(pg_blocking_pids($1))>0 AS blocked",
              [secondPid],
            )).rows[0];
            if (row.blocked) {
              blocked = true;
              break;
            }
            await new Promise((resolve) => setTimeout(resolve, 10));
          }
          assert(
            blocked,
            "must observe the competing statement waiting on the first transaction",
          );
          await first.queryArray("COMMIT");
          const outcome = await pending;
          if (deletionFirst) {
            assert(outcome instanceof Error);
            assert(
              ["initial_analysis_deleted", "initial_analysis_owner_unavailable"]
                .some((code) => outcome.message.includes(code)),
            );
            await second.queryArray("ROLLBACK");
          } else {
            assertEquals(outcome, null);
            await second.queryArray("COMMIT");
          }
          for (
            const table of [
              "initial_analysis_submissions",
              "initial_analysis_results",
              "initial_analysis_completions",
            ]
          ) {
            assertEquals(
              (await first.queryObject<{ count: bigint }>(
                `SELECT count(*) FROM internal.${table} WHERE scan_id=$1`,
                [scan],
              )).rows[0].count,
              0n,
            );
          }
          assertEquals(
            (await first.queryObject<{ count: bigint }>(
              "SELECT count(*) FROM internal.scan_deletion_tombstones WHERE scan_id=$1 AND user_id IS NULL",
              [scan],
            )).rows[0].count,
            1n,
          );
          if (funded) {
            assertEquals(
              (await first.queryObject<{ count: bigint }>(
                "SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id=$1",
                [child],
              )).rows[0].count,
              0n,
            );
            assertEquals(
              (await first.queryObject<{ count: bigint }>(
                "SELECT count(*) FROM internal.observation_evidence_objects WHERE analysis_id=$1",
                [child],
              )).rows[0].count,
              0n,
            );
            assertEquals(
              (await first.queryObject<{ count: bigint }>(
                "SELECT count(*) FROM internal.scan_deletion_tombstones WHERE scan_id=$1 AND user_id IS NULL",
                [child],
              )).rows[0].count,
              1n,
            );
            assertEquals(
              (await first.queryObject<{ count: bigint }>(
                "SELECT count(*) FROM internal.ai_quota_reservations WHERE original_analysis_id=$1 AND state='reserved'",
                [child],
              )).rows[0].count,
              0n,
            );
          }
        } finally {
          await second.queryArray("ROLLBACK").catch(() => {});
          await first.queryArray("ROLLBACK").catch(() => {});
          // Synthetic fixture cleanup only; never prune production tombstones.
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]);
          await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
          await first.queryArray("DELETE FROM public.scans WHERE id=$1", [
            scan,
          ]);
          await first.queryArray(
            "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id=ANY($1::uuid[])",
            [[scan, source, child]],
          );
          if (fixtureObjectIds.length) {
            await first.queryArray(
              "DELETE FROM internal.observation_evidence_erasure WHERE object_id=ANY($1::uuid[])",
              [fixtureObjectIds],
            );
          }
          if (flags) {
            await first.queryArray(
              "UPDATE internal.observation_history_rollout SET append_enabled=$1,media_enabled=$2,prepared_audio_evidence_enabled=$3,admission_enabled=$4,protected_analysis_enabled=$5,audio_analysis_enabled=$6",
              [
                flags.append_enabled,
                flags.media_enabled,
                flags.prepared_audio_evidence_enabled,
                flags.admission_enabled,
                flags.protected_analysis_enabled,
                flags.audio_analysis_enabled,
              ],
            );
          }
          if (entitlement) {
            await first.queryArray(
              "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
              [entitlement.mode, entitlement.protocol],
            );
          }
          if (gate !== undefined) {
            await first.queryArray(
              "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=$1",
              [gate],
            );
          }
          await first.end();
          await second.end();
          await observer.end();
        }
      },
    });
  }
}

for (
  const mutation of [
    "pre-row fence",
    "scan fence",
    "scan detach",
    "scan delete",
  ]
) {
  Deno.test({
    name:
      `Initial storage DB - raw ${mutation} fails fast then erases on retry`,
    ignore: !url,
    async fn() {
      assert(url);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
      );
      const first = new Client(url), second = new Client(url);
      const owner = crypto.randomUUID(), scan = crypto.randomUUID();
      let gate: boolean | undefined;
      try {
        await first.connect();
        await second.connect();
        const source = await Deno.readTextFile(
          new URL("../../tests/initial_analysis_storage.sql", import.meta.url),
        );
        await first.queryArray(
          source.split("-- BEGIN INITIAL STORAGE HELPERS\n")[1].split(
            "-- END INITIAL STORAGE HELPERS",
          )[0],
        );
        gate = (await first.queryObject<{ value: boolean }>(
          "SELECT initial_analysis_lifecycle_enabled AS value FROM internal.initial_analysis_rollout",
        )).rows[0].value;
        await first.queryArray(
          "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE",
        );
        await first.queryArray("SELECT pg_temp.initial_owner($1)", [owner]);
        if (mutation !== "pre-row fence") {
          await first.queryArray("SELECT pg_temp.initial_submission($1,$2)", [
            owner,
            scan,
          ]);
          await first.queryArray("SELECT pg_temp.initial_scan($1,$2)", [
            owner,
            scan,
          ]);
        }
        await first.queryArray("BEGIN");
        if (mutation === "pre-row fence") {
          // First admission is uncommitted and invisible to the fence writer.
          await first.queryArray("SELECT pg_temp.initial_submission($1,$2)", [
            owner,
            scan,
          ]);
        } else {
          await first.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
        }
        await second.queryArray("SET statement_timeout='2s'");
        const sql = mutation.endsWith("fence")
          ? "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id,completed_at) VALUES($1,NULL,now())"
          : mutation === "scan detach"
          ? "UPDATE public.scans SET user_id=NULL,is_tombstoned=TRUE WHERE id=$1"
          : "DELETE FROM public.scans WHERE id=$1";
        const error = await second.queryArray(sql, [scan]).then(
          () => null,
          (error: unknown) => error,
        );
        assert(error instanceof Error);
        assertEquals(
          (error as Error & { fields?: { code?: string } }).fields?.code,
          "55P03",
        );
        assertEquals(
          (await second.queryObject<{ count: bigint }>(
            "SELECT count(*) FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
            [scan],
          )).rows[0].count,
          0n,
        );
        if (mutation !== "pre-row fence") {
          assertEquals(
            (await second.queryObject<{ user_id: string }>(
              "SELECT user_id FROM public.scans WHERE id=$1",
              [scan],
            )).rows[0].user_id,
            owner,
          );
        }
        await first.queryArray("COMMIT");
        await second.queryArray(sql, [scan]);
        assertEquals(
          (await first.queryObject<{ count: bigint }>(
            "SELECT count(*) FROM internal.initial_analysis_submissions WHERE scan_id=$1",
            [scan],
          )).rows[0].count,
          0n,
        );
        assertEquals(
          (await first.queryObject<{ count: bigint }>(
            "SELECT count(*) FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
            [scan],
          )).rows[0].count,
          1n,
        );
      } finally {
        await first.queryArray("ROLLBACK").catch(() => {});
        await first.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
        await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
        await first.queryArray("DELETE FROM public.scans WHERE id=$1", [scan]);
        await first.queryArray(
          "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
          [scan],
        );
        if (gate !== undefined) {
          await first.queryArray(
            "UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=$1",
            [gate],
          );
        }
        await first.end();
        await second.end();
      }
    },
  });
}
