import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const version of [2, 3]) {
  for (
    const scenario of [
      "duplicate",
      "delete-first",
      "dispatch-first",
      "abandoned-witness",
    ]
  ) {
    Deno.test({
      name: `Source dispatch DB - V${version} ${scenario}`,
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
            "SELECT append_enabled,media_enabled,prepared_audio_evidence_enabled,admission_enabled,protected_analysis_enabled,audio_analysis_enabled,dispatch_enabled,source_dispatch_enabled FROM internal.observation_history_rollout WHERE singleton",
          )).rows[0];
          entitlement =
            (await first.queryObject<{ mode: string; protocol: number }>(
              "SELECT entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
            )).rows[0];
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
          );
          await first.queryArray(
            "UPDATE internal.observation_history_rollout SET append_enabled=true,media_enabled=true,prepared_audio_evidence_enabled=true,admission_enabled=true,protected_analysis_enabled=true,audio_analysis_enabled=true,dispatch_enabled=true,source_dispatch_enabled=true",
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
          if (scenario === "abandoned-witness") {
            // Only the database owner can arrange this impossible partial state.
            // A later service call must not reuse its committed audit witness.
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
            await second.queryArray(
              "SELECT set_config('merian.observation_analysis_provider',$1,false)",
              [`${owner}:${child}`],
            );
            let denied = false;
            try {
              await second.queryArray(
                "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
                [
                  values.reservation,
                  owner,
                  values.lease,
                  JSON.stringify(values.provenance),
                ],
              );
            } catch {
              denied = true;
            }
            assert(denied);
            await erase(first);
            let deletedDenied = false;
            try {
              await second.queryArray(
                "SELECT * FROM public.commit_identification_invocation($1,$2,$3,1,$4::jsonb)",
                [
                  values.reservation,
                  owner,
                  values.lease,
                  JSON.stringify(values.provenance),
                ],
              );
            } catch (error) {
              deletedDenied = String(error).includes("scan_generation_deleted");
            }
            assert(deletedDenied);
            assertEquals(
              (await first.queryObject<{ state: string }>(
                "SELECT state FROM internal.ai_quota_reservations WHERE id=$1",
                [values.reservation],
              )).rows[0].state,
              "reserved",
            );
          } else {
            await first.queryArray("BEGIN");
            await second.queryArray("BEGIN");
            await second.queryArray("SET LOCAL statement_timeout='3s'");
            if (scenario === "delete-first") await erase(first);
            else {assertEquals(
                (await dispatch(first)).rows[0].value.may_dispatch,
                true,
              );}
            // Start a competing operation while the first holds canonical locks.
            const pending =
              (scenario === "dispatch-first" ? erase(second) : dispatch(second))
                .then(
                  (value) => ({ value, error: false }),
                  () => ({ error: true }),
                );
            await first.queryArray("COMMIT");
            const result = await pending;
            if (scenario === "delete-first") {
              assert(result.error);
              await second.queryArray("ROLLBACK");
            } else {
              assert(!result.error && "value" in result);
              if (scenario === "duplicate") {
                assertEquals(
                  (result.value as Awaited<ReturnType<typeof dispatch>>).rows[0]
                    .value.may_dispatch,
                  false,
                );
              }
              await second.queryArray("COMMIT");
            }
            const quota =
              (await first.queryObject<{ state: string; refund_count: number }>(
                "SELECT state,refund_count FROM internal.ai_quota_reservations WHERE id=$1",
                [values.reservation],
              )).rows[0];
            assertEquals(
              quota,
              scenario === "delete-first"
                ? { state: "refunded", refund_count: 1 }
                : { state: "committed", refund_count: 0 },
            );
            assertEquals(
              (await first.queryObject<{ n: string }>(
                "SELECT count(*)::text n FROM internal.identification_invocations WHERE reservation_id=$1",
                [values.reservation],
              )).rows[0].n,
              scenario === "delete-first" ? "0" : "1",
            );
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
              "UPDATE internal.observation_history_rollout SET append_enabled=$1,media_enabled=$2,prepared_audio_evidence_enabled=$3,admission_enabled=$4,protected_analysis_enabled=$5,audio_analysis_enabled=$6,dispatch_enabled=$7,source_dispatch_enabled=$8",
              [
                rollout.append_enabled,
                rollout.media_enabled,
                rollout.prepared_audio_evidence_enabled,
                rollout.admission_enabled,
                rollout.protected_analysis_enabled,
                rollout.audio_analysis_enabled,
                rollout.dispatch_enabled,
                rollout.source_dispatch_enabled,
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
