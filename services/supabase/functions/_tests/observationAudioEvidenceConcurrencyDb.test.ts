import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
const audio =
  "SELECT public.reserve_owned_observation_audio_evidence_cohort($1,$2,$3,$4,46,repeat('a',64)) AS receipt";
const photo =
  "SELECT public.reserve_owned_observation_evidence_cohort($1,$2,$3,jsonb_build_array(jsonb_build_object('media_id',$4::uuid,'content_type','image/jpeg','byte_count',3,'sha256',repeat('b',64)))) AS receipt";
const settle = <T>(promise: Promise<T>) =>
  promise.then(
    (value) => ({ ok: true as const, value }),
    () => ({ ok: false as const }),
  );
async function blocked(observer: Client, waiter: number, blocker: number) {
  for (let n = 0; n < 100; n++) {
    const state = await observer.queryObject<{ blocked: boolean }>(
      "SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked",
      [blocker, waiter],
    );
    if (state.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("Expected canonical audio lock was not observed");
}
for (
  const scenario of [
    "duplicate audio",
    "audio before photo",
    "photo before audio",
    "deletion before audio",
    "expiry before replay",
    "cross-owner audio before photo",
  ]
) {
  Deno.test({
    name: `Audio evidence DB concurrency - ${scenario}`,
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
      const otherOwner = crypto.randomUUID(),
        otherObservation = crypto.randomUUID();
      let gates:
        | { media: boolean; audio: boolean; erasure: boolean }
        | undefined;
      try {
        for (const client of clients) await client.connect();
        const source = await Deno.readTextFile(
          new URL(
            "../../tests/observation_analysis_append.sql",
            import.meta.url,
          ),
        );
        const helpers = source.split(
          "-- BEGIN HISTORY APPEND SYNTHETIC HELPERS\n",
        )[1]?.split("-- END HISTORY APPEND SYNTHETIC HELPERS")[0];
        assert(helpers);
        await observer.queryArray(helpers);
        gates = (await observer.queryObject<
          { media: boolean; audio: boolean; erasure: boolean }
        >("SELECT media_enabled AS media,prepared_audio_evidence_enabled AS audio,private_evidence_erasure_enabled AS erasure FROM internal.observation_history_rollout WHERE singleton"))
          .rows[0];
        for (
          const pair of [[owner, observation], [otherOwner, otherObservation]]
        ) {
          await observer.queryArray(
            "SELECT pg_temp.seed_history_append($1,$2)",
            pair,
          );
        }
        await observer.queryArray(
          "UPDATE internal.observation_history_rollout SET media_enabled=TRUE,prepared_audio_evidence_enabled=TRUE,private_evidence_erasure_enabled=TRUE",
        );
        const args = [owner, observation, analysis, media];
        if (scenario === "expiry before replay") {
          await observer.queryArray("SET ROLE service_role");
          await observer.queryArray(audio, args);
          await observer.queryArray("RESET ROLE");
          await observer.queryArray("BEGIN");
          await observer.queryArray(
            "ALTER TABLE internal.observation_audio_evidence_upload_cohorts DISABLE TRIGGER guard_observation_audio_upload_cohort",
          );
          await observer.queryArray(
            "ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update",
          );
          await observer.queryArray(
            "UPDATE internal.observation_audio_evidence_upload_cohorts SET expires_at=transaction_timestamp()-interval '1 minute' WHERE analysis_id=$1",
            [analysis],
          );
          await observer.queryArray(
            "UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-interval '1 minute' WHERE analysis_id=$1",
            [analysis],
          );
          await observer.queryArray(
            "ALTER TABLE internal.observation_audio_evidence_upload_cohorts ENABLE TRIGGER guard_observation_audio_upload_cohort",
          );
          await observer.queryArray(
            "ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update",
          );
          await observer.queryArray("COMMIT");
        }
        for (const client of [first, second]) {
          await client.queryArray("BEGIN");
          await client.queryArray("SET LOCAL statement_timeout='10s'");
        }
        const blocker = (await first.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        const waiter = (await second.queryObject<{ pid: number }>(
          "SELECT pg_backend_pid() AS pid",
        )).rows[0].pid;
        let saved: unknown;
        if (scenario === "deletion before audio") {
          await first.queryArray(
            "SELECT id FROM public.users WHERE id=$1 FOR UPDATE",
            [owner],
          );
          await first.queryArray(
            "SELECT pg_advisory_xact_lock(hashtextextended('merian-scan-ingestion:'||$1::text,0::bigint))",
            [observation],
          );
          await first.queryArray(
            "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
            [observation, owner],
          );
        } else {
          await first.queryArray("SET LOCAL ROLE service_role");
          if (scenario === "expiry before replay") {
            const result = await first.queryObject<{ count: number }>(
              "SELECT public.retire_expired_observation_evidence() AS count",
            );
            assertEquals(result.rows[0].count, 1);
          } else {saved = (await first.queryObject<{ receipt: unknown }>(
              scenario === "photo before audio" ? photo : audio,
              args,
            )).rows[0].receipt;}
        }
        await second.queryArray("SET LOCAL ROLE service_role");
        const nextArgs = scenario === "cross-owner audio before photo"
          ? [otherOwner, otherObservation, analysis, crypto.randomUUID()]
          : args;
        const pending = settle(
          second.queryObject<{ receipt: unknown }>(
            scenario.endsWith("before photo") ? photo : audio,
            nextArgs,
          ),
        );
        await blocked(observer, waiter, blocker);
        await first.queryArray("COMMIT");
        const result = await pending;
        assertEquals(result.ok, scenario === "duplicate audio");
        if (result.ok) {
          assertEquals(result.value.rows[0].receipt, saved);
          await second.queryArray("COMMIT");
        } else await second.queryArray("ROLLBACK");
        const state = (await observer.queryObject<
          { audio: number; photos: number; receipts: number }
        >(
          "SELECT (SELECT count(*)::int FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=$1) AS audio,(SELECT count(*)::int FROM internal.observation_evidence_upload_cohorts WHERE analysis_id=$1) AS photos,(SELECT count(*)::int FROM internal.observation_evidence_objects WHERE analysis_id=$1) AS receipts",
          [analysis],
        )).rows[0];
        assertEquals(
          state,
          scenario === "deletion before audio"
            ? { audio: 0, photos: 0, receipts: 0 }
            : scenario === "photo before audio"
            ? { audio: 0, photos: 1, receipts: 1 }
            : {
              audio: 1,
              photos: 0,
              receipts: scenario === "expiry before replay" ? 0 : 1,
            },
        );
      } finally {
        for (const client of clients) {
          await client.queryArray("ROLLBACK").catch(() => {});
          await client.queryArray("RESET ROLE").catch(() => {});
        }
        if (gates) {
          await observer.queryArray(
            "UPDATE internal.observation_history_rollout SET media_enabled=$1,prepared_audio_evidence_enabled=$2,private_evidence_erasure_enabled=$3",
            [gates.media, gates.audio, gates.erasure],
          );
        }
        const objects = (await observer.queryObject<{ object_id: string }>(
          "SELECT object_id FROM internal.observation_audio_evidence_upload_cohorts WHERE analysis_id=$1 UNION SELECT object_id FROM internal.observation_evidence_objects WHERE analysis_id=$1",
          [analysis],
        )).rows;
        for (
          const pair of [[owner, observation], [otherOwner, otherObservation]]
        ) {
          await observer.queryArray("DELETE FROM public.scans WHERE id=$1", [
            pair[1],
          ]);
          await observer.queryArray(
            "DELETE FROM internal.scan_deletion_tombstones WHERE scan_id=$1",
            [pair[1]],
          );
          await observer.queryArray("DELETE FROM public.users WHERE id=$1", [
            pair[0],
          ]);
          await observer.queryArray("DELETE FROM auth.users WHERE id=$1", [
            pair[0],
          ]);
        }
        for (const object of objects) {
          await observer.queryArray(
            "DELETE FROM internal.observation_evidence_erasure WHERE object_id=$1",
            [object.object_id],
          );
        }
        await Promise.all(clients.map((client) => client.end()));
      }
    },
  });
}
