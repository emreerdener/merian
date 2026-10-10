import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const version of [2, 3]) {
  for (const deletionFirst of [false, true]) {
    Deno.test({
      name: `Source quota cleanup DB - V${version} ${
        deletionFirst ? "deletion" : "expiry"
      } first`,
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
            "SELECT append_enabled,media_enabled,prepared_audio_evidence_enabled,admission_enabled,protected_analysis_enabled,audio_analysis_enabled FROM internal.observation_history_rollout WHERE singleton",
          )).rows[0];
          entitlement =
            (await first.queryObject<{ mode: string; protocol: number }>(
              "SELECT entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
            )).rows[0];
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
          );
          await first.queryArray(
            "UPDATE internal.observation_history_rollout SET append_enabled=true,media_enabled=true,prepared_audio_evidence_enabled=true,admission_enabled=true,protected_analysis_enabled=true,audio_analysis_enabled=true",
          );
          const input = (await first.queryObject<{ value: unknown }>(
            "SELECT pg_temp.seed_bound_admission($1,$2,$3,$4,$5,$6) AS value",
            [...ids, version],
          )).rows[0].value;
          await first.queryArray("SELECT pg_temp.admit_bound($1,$2::jsonb)", [
            owner,
            JSON.stringify(input),
          ]);
          await first.queryArray(
            "UPDATE internal.ai_quota_reservations SET lease_expires_at=clock_timestamp()-interval '1 second' WHERE original_analysis_id=$1",
            [child],
          );
          const unrelated = crypto.randomUUID();
          const lease = (await first.queryObject<{ lease_token: string }>(
            "INSERT INTO internal.ai_quota_reservations SELECT (jsonb_populate_record(NULL::internal.ai_quota_reservations,to_jsonb(q)||jsonb_build_object('id',$1::text,'request_id',$1::text,'original_analysis_id',NULL))).* FROM internal.ai_quota_reservations q WHERE original_analysis_id=$2 RETURNING lease_token",
            [unrelated, child],
          )).rows[0].lease_token;
          await first.queryArray("BEGIN ISOLATION LEVEL REPEATABLE READ");
          assertEquals(
            (await first.queryObject<{ done: boolean }>(
              "SELECT public.finalize_ai_quota_reservation($1,$2,$3,'refunded') AS done",
              [unrelated, owner, lease],
            )).rows[0].done,
            true,
          );
          await first.queryArray("COMMIT");
          await first.queryArray("BEGIN");
          await second.queryArray("BEGIN");
          await second.queryArray("SET LOCAL statement_timeout='2s'");
          const erase = (client: Client) =>
            client.queryArray(
              "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
              [parent, owner],
            );
          const expire = (client: Client) =>
            client.queryArray(
              "SELECT internal.refund_expired_ai_quota_reservations(1000)",
            );
          if (deletionFirst) {
            await erase(first);
            await expire(second);
          } else {
            await expire(first);
            await erase(second);
          }
          // The second transaction must finish before the first commits: expiry
          // cannot lock/refund this bound row in either statement-snapshot order.
          await second.queryArray("COMMIT");
          await first.queryArray("COMMIT");
          const quota =
            (await first.queryObject<{ state: string; refund_count: number }>(
              "SELECT state,refund_count FROM internal.ai_quota_reservations WHERE original_analysis_id=$1",
              [child],
            )).rows[0];
          assertEquals(quota, { state: "refunded", refund_count: 1 });
          assertEquals(
            (await first.queryObject<{ n: string }>(
              "SELECT count(*)::text AS n FROM internal.observation_analysis_intents WHERE analysis_id=$1",
              [child],
            )).rows[0].n,
            "0",
          );
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
              "UPDATE internal.observation_history_rollout SET append_enabled=$1,media_enabled=$2,prepared_audio_evidence_enabled=$3,admission_enabled=$4,protected_analysis_enabled=$5,audio_analysis_enabled=$6",
              [
                rollout.append_enabled,
                rollout.media_enabled,
                rollout.prepared_audio_evidence_enabled,
                rollout.admission_enabled,
                rollout.protected_analysis_enabled,
                rollout.audio_analysis_enabled,
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
