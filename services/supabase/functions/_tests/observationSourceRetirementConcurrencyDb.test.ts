import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const version of [2, 3]) {
  for (
    const scenario of [
      "retire-first-dispatch",
      "dispatch-first-retire",
      "delete-first",
      "retire-first-delete",
      "duplicate",
      "different-operation",
      "witness-held",
      "frozen-replay",
    ]
  ) {
    Deno.test({
      name: `Source retirement DB - V${version} ${scenario}`,
      ignore: !url,
      async fn() {
        assert(url);
        assert(
          ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
        );
        const first = new Client(url), second = new Client(url);
        const ids = Array.from({ length: 5 }, () => crypto.randomUUID());
        const [owner, parent, , child] = ids;
        let rollout: Record<string, boolean> | undefined;
        let entitlement: { mode: string; protocol: number } | undefined;
        try {
          await first.connect();
          await second.connect();
          const text = await Deno.readTextFile(
            new URL(
              "../../tests/observation_source_initial_admission.sql",
              import.meta.url,
            ),
          );
          await first.queryArray(
            text.split("-- BEGIN SOURCE ADMISSION HELPERS\n")[1].split(
              "-- END SOURCE ADMISSION HELPERS",
            )[0],
          );
          for (const client of [first, second]) {
            await client.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false)",
            );
          }
          rollout = (await first.queryObject<Record<string, boolean>>(
            "SELECT append_enabled,media_enabled,prepared_audio_evidence_enabled,admission_enabled,protected_analysis_enabled,audio_analysis_enabled,dispatch_enabled,source_dispatch_enabled,source_retirement_enabled,execution_retirement_api_enabled FROM internal.observation_history_rollout WHERE singleton",
          )).rows[0];
          entitlement =
            (await first.queryObject<{ mode: string; protocol: number }>(
              "SELECT entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
            )).rows[0];
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
          );
          await first.queryArray(
            "UPDATE internal.observation_history_rollout SET append_enabled=true,media_enabled=true,prepared_audio_evidence_enabled=true,admission_enabled=true,protected_analysis_enabled=true,audio_analysis_enabled=true,dispatch_enabled=true,source_dispatch_enabled=true,source_retirement_enabled=true,execution_retirement_api_enabled=true",
          );
          const input = (await first.queryObject<{ value: unknown }>(
            "SELECT pg_temp.seed_bound_admission($1,$2,$3,$4,$5,$6) AS value",
            [...ids, version],
          )).rows[0].value;
          await first.queryArray("SELECT pg_temp.admit_bound($1,$2::jsonb)", [
            owner,
            JSON.stringify(input),
          ]);
          const fixture = await Deno.readTextFile(
            new URL(
              "../../tests/observation_source_dispatch.sql",
              import.meta.url,
            ),
          );
          const provenanceFunction =
            "CREATE FUNCTION pg_temp.funded_provenance" +
            fixture.split("CREATE FUNCTION pg_temp.funded_provenance")[1].split(
              "$$;",
            )[0] + "$$;";
          await first.queryArray(provenanceFunction);
          const values = (await first.queryObject<
            { lease: string; provenance: unknown; reservation: string }
          >(
            "SELECT quota->>'lease_token' AS lease,quota->>'reservation_id' AS reservation,pg_temp.funded_provenance(analysis_id) AS provenance FROM internal.observation_analysis_intents WHERE analysis_id=$1",
            [child],
          )).rows[0];
          const dispatch = (client: Client) =>
            client.queryObject<{ value: { may_dispatch: boolean } }>(
              "SELECT internal.dispatch_observation_analysis($1,$2,$3,$4,$5::jsonb) AS value",
              [
                owner,
                parent,
                child,
                values.lease,
                JSON.stringify(values.provenance),
              ],
            );
          const erase = (client: Client) =>
            client.queryArray(
              "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
              [parent, owner],
            );
          const operation = crypto.randomUUID();
          const request = {
            schema_version: 1,
            operation_id: operation,
            observation_id: parent,
            analysis_id: child,
            source_analysis_id: ids[2],
            request_digest: "a".repeat(64),
          };
          const retire = (client: Client, op = operation) =>
            client.queryObject<{ value: unknown }>(
              "SELECT public.retire_owned_observation_analysis_execution($1,$2::jsonb,10) AS value",
              [owner, JSON.stringify({ ...request, operation_id: op })],
            );
          if (scenario === "witness-held") {
            await first.queryArray(
              "SELECT internal.prepare_source_dispatch_witness($1,$2,$3,$4,$5::jsonb)",
              [
                owner,
                parent,
                child,
                values.lease,
                JSON.stringify(values.provenance),
              ],
            );
            let denied = false;
            try {
              await retire(second);
            } catch (error) {
              denied = String(error).includes(
                "analysis_history_operation_conflict",
              );
            }
            assert(denied);
            assertEquals(
              (await first.queryObject<{ state: string }>(
                "SELECT state FROM internal.ai_quota_reservations WHERE id=$1",
                [values.reservation],
              )).rows[0].state,
              "reserved",
            );
          } else if (scenario === "frozen-replay") {
            await retire(first);
            await second.queryArray("BEGIN ISOLATION LEVEL REPEATABLE READ");
            let denied = false;
            try {
              await retire(second);
            } catch (error) {
              denied = String(error).includes(
                "analysis_history_current_snapshot_required",
              );
            }
            assert(denied);
            await second.queryArray("ROLLBACK");
            await second.queryArray("BEGIN ISOLATION LEVEL SERIALIZABLE");
            denied = false;
            try {
              await retire(second);
            } catch (error) {
              denied = String(error).includes(
                "analysis_history_current_snapshot_required",
              );
            }
            assert(denied);
            await second.queryArray("ROLLBACK");
          } else {
            const pid = (await second.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() AS pid",
            )).rows[0].pid;
            await first.queryArray("BEGIN");
            await second.queryArray("BEGIN");
            await second.queryArray("SET LOCAL statement_timeout='3s'");
            if (scenario === "delete-first") await erase(first);
            else if (scenario === "dispatch-first-retire") {
              assertEquals(
                (await dispatch(first)).rows[0].value.may_dispatch,
                true,
              );
            } else await retire(first);
            const pending = (scenario === "retire-first-dispatch"
              ? dispatch(second)
              : scenario === "retire-first-delete"
              ? erase(second)
              : retire(
                second,
                scenario === "different-operation"
                  ? crypto.randomUUID()
                  : operation,
              )).then(
                (value) => ({ value, error: false }),
                (error) => ({ error: true, message: String(error) }),
              );
            let blocked = false;
            for (let n = 0; n < 100 && !blocked; n++) {
              blocked = (await first.queryObject<{ blocked: boolean }>(
                "SELECT cardinality(pg_blocking_pids($1))>0 AS blocked",
                [pid],
              )).rows[0].blocked;
              if (!blocked) {
                await new Promise((resolve) =>
                  setTimeout(resolve, 5)
                );
              }
            }
            assert(
              blocked,
              "competing operation must actually wait on the first transaction",
            );
            await first.queryArray("COMMIT");
            const result = await pending;
            const denied = [
              "retire-first-dispatch",
              "dispatch-first-retire",
              "delete-first",
              "different-operation",
            ].includes(scenario);
            assertEquals(result.error, denied);
            await second.queryArray(denied ? "ROLLBACK" : "COMMIT");
            const quota =
              (await first.queryObject<{ state: string; refund_count: number }>(
                "SELECT state,refund_count FROM internal.ai_quota_reservations WHERE id=$1",
                [values.reservation],
              )).rows[0];
            assertEquals(
              quota,
              scenario === "dispatch-first-retire"
                ? { state: "committed", refund_count: 0 }
                : { state: "refunded", refund_count: 1 },
            );
            const occupancy = (await first.queryObject<{ n: string }>(
              "SELECT count(*)::text AS n FROM internal.observation_analysis_source_occupancy WHERE analysis_id=$1",
              [child],
            )).rows[0].n;
            assertEquals(
              occupancy,
              scenario === "dispatch-first-retire" ? "1" : "0",
            );
            if (scenario === "duplicate") {
              assertEquals((await retire(first)).rows[0].value, {
                ...request,
                state: "retired_before_dispatch",
              });
            }
          }
        } finally {
          await first.queryArray("ROLLBACK").catch(() => {});
          await second.queryArray("ROLLBACK").catch(() => {});
          await first.queryArray("SELECT public.apply_user_tombstone($1)", [
            owner,
          ]).catch(() => {});
          await first.queryArray("DELETE FROM auth.users WHERE id=$1", [owner])
            .catch(() => {});
          if (rollout) {
            await first.queryArray(
              "UPDATE internal.observation_history_rollout SET append_enabled=$1,media_enabled=$2,prepared_audio_evidence_enabled=$3,admission_enabled=$4,protected_analysis_enabled=$5,audio_analysis_enabled=$6,dispatch_enabled=$7,source_dispatch_enabled=$8,source_retirement_enabled=$9,execution_retirement_api_enabled=$10",
              [
                rollout.append_enabled,
                rollout.media_enabled,
                rollout.prepared_audio_evidence_enabled,
                rollout.admission_enabled,
                rollout.protected_analysis_enabled,
                rollout.audio_analysis_enabled,
                rollout.dispatch_enabled,
                rollout.source_dispatch_enabled,
                rollout.source_retirement_enabled,
                rollout.execution_retirement_api_enabled,
              ],
            );
          }
          if (entitlement) {
            await first.queryArray(
              "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
              [entitlement.mode, entitlement.protocol],
            );
          }
          await first.end().catch(() => {});
          await second.end().catch(() => {});
        }
      },
    });
  }
}
