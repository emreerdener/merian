import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const settle = <T>(p: Promise<T>) =>
  p.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    const row = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (row.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected canonical admission lock was not observed");
}
for (
  const scenario of [
    "duplicate admission",
    "deletion before admission",
    "materialization before deletion",
  ]
) {
  Deno.test({
    name: `Audio admission DB concurrency - ${scenario}`,
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
      let original: Record<string, boolean> | undefined;
      let entitlement: { mode: string; protocol: number } | undefined;
      try {
        for (const c of clients) await c.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_audio_analysis_admission.sql",
            import.meta.url,
          ),
        );
        await observer.queryArray(
          source.slice(
            source.indexOf("CREATE FUNCTION pg_temp.history_append_request"),
            source.indexOf("SELECT extensions.ok"),
          ),
        );
        original =
          (await observer.queryObject<{ value: Record<string, boolean> }>(
            "SELECT to_jsonb(r) AS value FROM internal.observation_history_rollout r WHERE singleton",
          )).rows[0].value;
        entitlement =
          (await observer.queryObject<{ mode: string; protocol: number }>(
            "SELECT entitlement_mode AS mode,required_client_protocol AS protocol FROM internal.entitlement_rollout_config WHERE config_key='current'",
          )).rows[0];
        await observer.queryArray("SELECT pg_temp.seed_funded_history($1,$2)", [
          owner,
          observation,
        ]);
        await observer.queryArray(
          "UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current'",
        );
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET orchestration_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,audio_analysis_enabled=TRUE",
        );
        const receipt =
          (await observer.queryObject<{ value: { object_id: string } }>(
            "SELECT public.reserve_owned_observation_audio_evidence_cohort($1,$2,$3,$4,46,repeat('b',64)) AS value",
            [owner, observation, analysis, media],
          )).rows[0].value;
        await observer.queryArray(
          "SELECT public.complete_owned_observation_audio_evidence_upload($1,$2,$3,$4,$5)",
          [owner, observation, analysis, media, receipt.object_id],
        );
        const input = {
          schema_version: 3,
          observation_id: observation,
          analysis_id: analysis,
          source_analysis_id: null,
          request_digest: "a".repeat(64),
          evidence_manifest: {
            schema_version: 3,
            items: [{
              kind: "audio",
              media_id: media,
              content_type: "audio/wav",
              byte_count: 46,
              sha256: "b".repeat(64),
            }],
          },
          entitlement_protocol: 3,
          identification_protocol: 6,
          history_protocol: 9,
          expected_processor_permission: "google_gemini",
        };
        const begin = (c: Client) =>
          c.queryObject<{ value: { claimed: boolean; work_token: string } }>(
            "SELECT public.begin_owned_observation_analysis($1,$2::jsonb,repeat('a',64)) AS value",
            [owner, JSON.stringify(input)],
          );
        const deletion = (c: Client) =>
          c.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        const pids = await Promise.all(
          [first, second].map(async (c) =>
            (await c.queryObject<{ pid: number }>(
              "SELECT pg_backend_pid() pid",
            ))
              .rows[0].pid
          ),
        );
        let work: string | undefined;
        if (scenario === "materialization before deletion") {
          work = (await begin(observer)).rows[0].value.work_token;
        }
        await first.queryArray("BEGIN");
        await second.queryArray("BEGIN");
        if (scenario === "deletion before admission") {
          await deletion(first);
        } else if (work) {
          await first.queryArray(
            "SELECT public.advance_owned_observation_analysis($1,$2,$3,$4,'materialize','{}')",
            [owner, observation, analysis, work],
          );
        } else assertEquals((await begin(first)).rows[0].value.claimed, true);
        const waiting = settle<unknown>(
          work ? deletion(second) : begin(second),
        );
        await blocked(observer, pids[1], pids[0]);
        await first.queryArray("COMMIT");
        const result = await waiting;
        assertEquals(result.ok, scenario !== "deletion before admission");
        if (result.ok) {
          await second.queryArray("COMMIT");
        } else await second.queryArray("ROLLBACK");
        if (scenario === "duplicate admission") {
          assertEquals((await begin(observer)).rows[0].value.claimed, false);
          const counts = await observer.queryObject<{ n: number }>(
            "SELECT count(*)::int n FROM internal.complimentary_scan_usage WHERE client_scan_id=$1",
            [analysis],
          );
          assertEquals(counts.rows[0].n, 1);
        } else {
          assertEquals((await settle(begin(observer))).ok, false);
          assertEquals(
            (await observer.queryObject<{ n: number }>(
              "SELECT count(*)::int n FROM internal.observation_analysis_intents WHERE analysis_id=$1",
              [analysis],
            )).rows[0].n,
            0,
          );
        }
      } finally {
        for (const c of clients) {
          try {
            await c.queryArray("ROLLBACK");
          } catch { /* disconnected */ }
        }
        try {
          if (original) {
            for (
              const key of [
                "enrollment_enabled",
                "orchestration_enabled",
                "admission_enabled",
                "dispatch_enabled",
                "append_enabled",
                "protected_analysis_enabled",
                "media_enabled",
                "prepared_audio_evidence_enabled",
                "audio_analysis_enabled",
              ]
            ) {
              await observer.queryArray(
                `UPDATE internal.observation_history_rollout SET ${key}=$1`,
                [original[key]],
              );
            }
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
          await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
            owner,
          ]);
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            owner,
          ]);
        } finally {
          for (const c of clients) await c.end();
        }
      }
    },
  });
}
