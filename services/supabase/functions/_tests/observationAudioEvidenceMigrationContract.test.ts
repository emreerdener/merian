import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261007154709_prepare_private_audio_evidence_cohorts.sql",
    import.meta.url,
  ),
);
Deno.test("audio cohorts retain a separate immutable identity and default-off gate", () => {
  assertStringIncludes(
    sql,
    "prepared_audio_evidence_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assertStringIncludes(
    sql,
    "BEFORE UPDATE ON internal.observation_audio_evidence_upload_cohorts",
  );
  assertStringIncludes(sql, "object_id UUID NOT NULL UNIQUE");
  assertStringIncludes(sql, "CHECK(byte_count BETWEEN 46 AND 2700000)");
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION internal.assert_protected_analysis_evidence",
    ),
  );
});
Deno.test("audio expiry retains identity and excludes legacy cleanup rediscovery", () => {
  const cleanup = sql.slice(
    sql.indexOf(
      "CREATE OR REPLACE FUNCTION public.retire_expired_observation_evidence",
    ),
  );
  assert(
    !/DELETE FROM internal\.observation_audio_evidence_upload_cohorts/.test(
      cleanup,
    ),
  );
  assertStringIncludes(cleanup, "a.analysis_id=e.analysis_id");
  assertStringIncludes(cleanup, "e.object_id<>audio.object_id");
  assert(
    cleanup.indexOf("lock_owned_observation_evidence") <
      cleanup.indexOf("FOR UPDATE"),
  );
});
Deno.test("audio service RPCs are exact allowlisted caller-checked operations", () => {
  for (
    const name of [
      "reserve_owned_observation_audio_evidence_cohort",
      "complete_owned_observation_audio_evidence_upload",
    ]
  ) {
    const body =
      sql.slice(sql.indexOf(`CREATE FUNCTION public.${name}`)).split("$$;")[0];
    assertStringIncludes(body, "internal.require_service_role()");
    assertStringIncludes(body, "lock_owned_observation_evidence");
    assertStringIncludes(sql, `'service_role','public.${name}(`);
  }
});
