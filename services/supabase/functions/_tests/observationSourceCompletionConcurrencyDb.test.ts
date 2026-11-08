import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const version of [2, 3]) {
  for (
    const scenario of [
      "complete-reserve",
      "reserve-complete",
      "complete-delete",
      "delete-complete",
    ]
  ) {
    Deno.test({
      name: `Source completion DB - V${version} ${scenario}`,
      ignore: !url,
      async fn() {
        assert(url);
        assert(
          ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
        );
        const first = new Client(url), second = new Client(url);
        const [owner, parent, source, child, next, media] = Array.from({
          length: 6,
        }, () => crypto.randomUUID());
        let rollout: Record<string, boolean> | undefined;
        let entitlement: {
          entitlement_mode: string;
          required_client_protocol: number;
        } | undefined;
        try {
          await first.connect();
          await second.connect();
          const fixtures = await Deno.readTextFile(
            new URL(
              "../../tests/observation_source_completion.sql",
              import.meta.url,
            ),
          );
          await first.queryArray(
            fixtures.split("-- BEGIN SOURCE COMPLETION HELPERS")[1].split(
              "-- END SOURCE COMPLETION HELPERS",
            )[0],
          );
          for (const c of [first, second]) {
            await c.queryArray(
              "SELECT set_config('request.jwt.claim.role','service_role',false)",
            );
          }
          const columns = [
            "append_enabled",
            "media_enabled",
            "prepared_audio_evidence_enabled",
            "admission_enabled",
            "protected_analysis_enabled",
            "audio_analysis_enabled",
            "dispatch_enabled",
            "source_dispatch_enabled",
            "orchestration_enabled",
            "source_reservation_enabled",
            "source_completion_release_enabled",
          ];
          rollout = (await first.queryObject<Record<string, boolean>>(
            `SELECT ${
              columns.join(",")
            } FROM internal.observation_history_rollout WHERE singleton`,
          )).rows[0];
          entitlement = (await first.queryObject<
            { entitlement_mode: string; required_client_protocol: number }
          >("SELECT entitlement_mode,required_client_protocol FROM internal.entitlement_rollout_config WHERE config_key='current'"))
            .rows[0];
          await first.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              columns.map((c) => `${c}=true`).join(",")
            }`,
          );
          await first.queryArray(
            "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
          );
          const work = (await first.queryObject<{ work: string }>(
            "SELECT pg_temp.prepare_source_draft($1,$2,$3,$4,$5) work",
            [owner, parent, source, child, version],
          )).rows[0].work;
          const request = (await first.queryObject<{ value: unknown }>(
            "SELECT jsonb_build_object('schema_version',1,'input',input,'fingerprint_version',1,'fingerprint',internal.observation_source_fingerprint(input)) value FROM (SELECT pg_temp.admission_input($1,$2,$3,$4,$5) input) s",
            [parent, source, next, media, version],
          )).rows[0].value;
          const complete = (c: Client) =>
            c.queryObject<{ value: { state: string } }>(
              "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'complete','{}') value",
              [owner, parent, child, work],
            );
          const reserve = (c: Client) =>
            c.queryObject<{ value: { state: string } }>(
              "SELECT public.reserve_owned_observation_analysis_source($1,$2::jsonb,11) value",
              [owner, JSON.stringify(request)],
            );
          const erase = (c: Client) =>
            c.queryArray("SELECT public.apply_user_tombstone($1)", [owner]);
          const pid = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() pid",
          )).rows[0].pid;
          await first.queryArray("BEGIN");
          await second.queryArray("BEGIN");
          await second.queryArray("SET LOCAL statement_timeout='5s'");
          if (scenario.startsWith("complete")) await complete(first);
          else if (scenario.startsWith("reserve")) {
            assertEquals((await reserve(first)).rows[0].value.state, "held");
          } else await erase(first);
          const pending = (scenario.endsWith("reserve")
            ? reserve(second)
            : scenario.endsWith("delete")
            ? erase(second)
            : complete(second)).then(
              (value) => ({ error: false, value }),
              (error) => ({ error: true, message: String(error) }),
            );
          let blocked = false;
          for (let n = 0; n < 100 && !blocked; n++) {
            blocked = (await first.queryObject<{ blocked: boolean }>(
              "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
              [pid],
            )).rows[0].blocked;
            if (!blocked) {
              await new Promise((r) =>
                setTimeout(r, 5)
              );
            }
          }
          assert(
            blocked,
            "second connection must actually wait on canonical locks",
          );
          await first.queryArray("COMMIT");
          const result = await pending;
          assertEquals(
            result.error,
            scenario === "delete-complete",
            JSON.stringify(result),
          );
          await second.queryArray(result.error ? "ROLLBACK" : "COMMIT");
          if (scenario.includes("delete")) {
            assertEquals(
              (await first.queryObject<{ n: string }>(
                "SELECT count(*)::text n FROM internal.observation_source_completion_receipts WHERE owner_id=$1",
                [owner],
              )).rows[0].n,
              "0",
            );
          } else {
            assertEquals(
              (await reserve(first)).rows[0].value.state,
              "reserved",
            );
            assertEquals(
              (await first.queryObject<{ n: string }>(
                "SELECT count(*)::text n FROM internal.observation_source_completion_receipts WHERE analysis_id=$1",
                [child],
              )).rows[0].n,
              "1",
            );
            const replay =
              (await first.queryObject<{ value: { state: string } }>(
                "SELECT public.begin_owned_observation_analysis($1,input_snapshot,encode(extensions.digest(($1::uuid)::text,'sha256'),'hex')) value FROM internal.observation_analysis_intents WHERE analysis_id=$2",
                [owner, child],
              )).rows[0].value;
            assertEquals(replay.state, "complete");
            assertEquals(
              (await first.queryObject<{ n: string }>(
                "SELECT count(*)::text n FROM internal.identification_invocations WHERE scan_id=$1",
                [child],
              )).rows[0].n,
              "1",
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
            const entries = Object.entries(rollout);
            await first.queryArray(
              `UPDATE internal.observation_history_rollout SET ${
                entries.map(([k], i) => `${k}=$${i + 1}`).join(",")
              }`,
              entries.map(([, v]) => v),
            );
          }
          if (entitlement) {
            await first.queryArray(
              "UPDATE internal.entitlement_rollout_config SET entitlement_mode=$1,required_client_protocol=$2 WHERE config_key='current'",
              [
                entitlement.entitlement_mode,
                entitlement.required_client_protocol,
              ],
            );
          }
          await first.end();
          await second.end();
        }
      },
    });
  }
}
