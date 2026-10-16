import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
for (const version of [2, 3]) {
  for (
    const scenario of [
      "same-reservation",
      "different-reservation",
      "retire-upload",
      "upload-retire",
      "retire-duplicate",
      "retire-successor",
      "delete-retire",
      "retire-delete",
      "legacy-reserve",
      "reserve-legacy",
    ]
  ) {
    Deno.test({
      name: `Source reservation DB - V${version} ${scenario}`,
      ignore: !url,
      async fn() {
        assert(url);
        assert(
          ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
        );
        const first = new Client(url), second = new Client(url);
        const [owner, parent, source, child, media, next] = Array.from({
          length: 6,
        }, () => crypto.randomUUID());
        let rollout: Record<string, boolean> | undefined;
        try {
          await first.connect();
          await second.connect();
          const fixtures = await Deno.readTextFile(
            new URL(
              "../../tests/observation_source_reservation.sql",
              import.meta.url,
            ),
          );
          await first.queryArray(
            fixtures.slice(
              fixtures.indexOf(
                "CREATE FUNCTION pg_temp.history_append_request",
              ),
              fixtures.indexOf(
                "SELECT extensions.ok(NOT source_reservation_enabled",
              ),
            ),
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
            "source_reservation_enabled",
            "source_unfunded_retirement_enabled",
          ];
          rollout = (await first.queryObject<Record<string, boolean>>(
            `SELECT ${
              columns.join(",")
            } FROM internal.observation_history_rollout WHERE singleton`,
          )).rows[0];
          await first.queryArray(
            `UPDATE internal.observation_history_rollout SET ${
              columns.map((c) => `${c}=true`).join(",")
            }`,
          );
          await first.queryArray("SELECT pg_temp.seed_history_append($1,$2)", [
            owner,
            parent,
          ]);
          await first.queryArray(
            "SELECT internal.append_observation_analysis($1,pg_temp.history_append_request($2,$3))",
            [owner, parent, source],
          );
          const input =
            (await first.queryObject<{ input: Record<string, unknown> }>(
              "SELECT pg_temp.admission_input($1,$2,$3,$4,$5) input",
              [parent, source, child, media, version],
            )).rows[0].input;
          const candidate = async (id: string) => {
            const value = { ...input, analysis_id: id };
            const fp = (await first.queryObject<{ fp: string }>(
              "SELECT internal.observation_source_fingerprint($1::jsonb) fp",
              [JSON.stringify(value)],
            )).rows[0].fp;
            return {
              schema_version: 1,
              input: value,
              fingerprint_version: 1,
              fingerprint: fp,
            };
          };
          const original = await candidate(child),
            successor = await candidate(next);
          const request = {
            schema_version: 1,
            observation_id: parent,
            source_analysis_id: source,
            analysis_id: child,
            request_digest: input.request_digest,
            fingerprint_version: 1,
            fingerprint: original.fingerprint,
            operation_id: crypto.randomUUID(),
          };
          const reserve = (c: Client, value = original) =>
            c.queryObject<{ value: { state: string } }>(
              "SELECT public.reserve_owned_observation_analysis_source($1,$2::jsonb,11) value",
              [owner, JSON.stringify(value)],
            );
          const retire = (c: Client) =>
            c.queryObject<{ value: { state: string } }>(
              "SELECT public.retire_owned_observation_analysis_source($1,$2::jsonb,11) value",
              [owner, JSON.stringify(request)],
            );
          const erase = (c: Client) =>
            c.queryArray("SELECT public.apply_user_tombstone($1)", [owner]);
          const legacy = (c: Client) =>
            c.queryArray(
              "INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code) VALUES($1,$2,'failed_terminal','server_replay_limit_reached','replay_exhausted')",
              [child.toUpperCase(), owner],
            );
          const upload = (c: Client) =>
            version === 3
              ? c.queryArray(
                "SELECT public.reserve_owned_observation_audio_evidence_cohort($1,$2,$3,$4,46,$5)",
                [owner, parent, child, media, "b".repeat(64)],
              )
              : c.queryArray(
                "SELECT public.reserve_owned_observation_evidence_cohort($1,$2,$3,$4::jsonb)",
                [
                  owner,
                  parent,
                  child,
                  JSON.stringify([{
                    media_id: media,
                    content_type: "image/jpeg",
                    byte_count: 46,
                    sha256: "b".repeat(64),
                  }]),
                ],
              );
          if (
            ![
              "same-reservation",
              "different-reservation",
              "legacy-reserve",
              "reserve-legacy",
            ].includes(scenario)
          ) await reserve(first);
          const pid = (await second.queryObject<{ pid: number }>(
            "SELECT pg_backend_pid() pid",
          )).rows[0].pid;
          await first.queryArray("BEGIN");
          await second.queryArray("BEGIN");
          await second.queryArray("SET LOCAL statement_timeout='5s'");
          if (scenario === "delete-retire") await erase(first);
          else if (scenario === "upload-retire") await upload(first);
          else if (scenario === "legacy-reserve") await legacy(first);
          else if (
            ["same-reservation", "different-reservation", "reserve-legacy"]
              .includes(scenario)
          ) await reserve(first);
          else await retire(first);
          const pending = (scenario === "retire-upload"
            ? upload(second)
            : scenario === "retire-delete"
            ? erase(second)
            : scenario === "reserve-legacy"
            ? legacy(second)
            : scenario === "same-reservation" || scenario === "legacy-reserve"
            ? reserve(second)
            : scenario === "different-reservation" ||
                scenario === "retire-successor"
            ? reserve(second, successor)
            : retire(second)).then(
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
          assert(blocked, "second connection must really wait");
          await first.queryArray("COMMIT");
          const result = await pending;
          const denied = [
            "retire-upload",
            "upload-retire",
            "delete-retire",
            "legacy-reserve",
            "reserve-legacy",
          ].includes(scenario);
          assertEquals(result.error, denied, JSON.stringify(result));
          await second.queryArray(denied ? "ROLLBACK" : "COMMIT");
          if (scenario === "different-reservation") {
            assertEquals(
              (await reserve(first, successor)).rows[0].value.state,
              "held",
            );
          }
          if (scenario === "retire-duplicate") {
            assertEquals(
              (await retire(first)).rows[0].value.state,
              "retired_unfunded",
            );
          }
          if (scenario === "retire-successor") {
            assertEquals(
              (await reserve(first, successor)).rows[0].value.state,
              "reserved",
            );
          }
          if (scenario === "retire-delete" || scenario === "delete-retire") {
            assertEquals(
              (await first.queryObject<{ n: string }>(
                "SELECT count(*)::text n FROM internal.observation_source_unfunded_retirements WHERE owner_id=$1",
                [owner],
              )).rows[0].n,
              "0",
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
          await first.end();
          await second.end();
        }
      },
    });
  }
}
