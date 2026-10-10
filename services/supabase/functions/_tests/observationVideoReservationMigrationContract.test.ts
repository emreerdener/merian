import { assert, assertEquals } from "@std/assert";
Deno.test("video source RPCs are separately gated reader12 metadata-only authority", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261010040600_prepare_video_source_reservation.sql",
      import.meta.url,
    ),
  );
  assertEquals(
    (sql.match(/PERFORM internal.require_service_role\(\)/g) ?? []).length,
    2,
  );
  assertEquals((sql.match(/p_reader IS DISTINCT FROM 12/g) ?? []).length, 2);
  assertEquals((sql.match(/GRANT EXECUTE/g) ?? []).length, 2);
  assertEquals((sql.match(/LIMIT 65/g) ?? []).length, 8);
  for (
    const gate of [
      "video_source_reservation_enabled",
      "video_source_recovery_enabled",
    ]
  ) assert(sql.includes(`${gate} BOOLEAN NOT NULL DEFAULT FALSE`));
  assert(
    !/CREATE OR REPLACE|pg_get_functiondef|TO authenticated|TO anon|cron\.|finalize_ai_quota|INSERT INTO internal.observation_video_evidence_upload_cohorts/
      .test(sql),
  );
  const recovery = sql.slice(
    sql.indexOf("CREATE FUNCTION public.get_owned_observation_video_source"),
    sql.indexOf(
      "REVOKE ALL ON FUNCTION public.get_owned_observation_video_source",
    ),
  );
  assert(!/\bINSERT\b|\bUPDATE\b|\bDELETE\b/.test(recovery));
  assert(
    recovery.includes("internal.lock_owned_observation_video_source_binding"),
  );
  assert(
    recovery.includes(
      "internal.observation_video_source_fingerprint(binding.input_snapshot)",
    ),
  );
  assert(
    sql.indexOf("IF FOUND THEN") <
      sql.indexOf("SELECT video_source_reservation_enabled"),
  );
  for (
    const namespace of [
      "observation_evidence_upload_cohorts",
      "observation_audio_evidence_upload_cohorts",
      "observation_video_evidence_upload_cohorts",
      "observation_evidence_objects",
    ]
  ) {
    assert(
      sql.includes(
        `FROM internal.${namespace} WHERE observation_id=observation LIMIT 65`,
      ),
    );
  }
});
