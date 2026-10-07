import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261007171421_prepare_audio_analysis_admission.sql",
    import.meta.url,
  ),
);
Deno.test("audio execution migration preserves independent closed gate and private SQL owners", () => {
  assertStringIncludes(
    sql,
    "audio_analysis_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assert(!/SET\s+audio_analysis_enabled\s*=\s*TRUE/i.test(sql));
  for (
    const signature of [
      "internal.assert_audio_analysis_evidence(UUID,UUID,UUID,JSONB,BOOLEAN)",
      "internal.admit_audio_observation_analysis(UUID,JSONB,TEXT)",
      "internal.append_audio_observation_analysis(UUID,JSONB)",
    ]
  ) {
    assert(
      sql.split(";").some((statement) =>
        statement.includes("REVOKE ALL ON FUNCTION") &&
        statement.includes(signature) &&
        statement.includes("FROM PUBLIC,anon,authenticated,service_role")
      ),
    );
  }
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION internal.admit_protected_observation_analysis",
    ),
  );
  assert(
    !sql.includes(
      "CREATE OR REPLACE FUNCTION internal.append_protected_observation_analysis",
    ),
  );
});
Deno.test("audio forward patches fail closed on source drift and separate imported manifest3 from audio result4", () => {
  assertStringIncludes(sql, "audio_analysis_source_drift");
  assertStringIncludes(sql, "audio_reader_source_drift");
  assertStringIncludes(
    sql,
    "CASE WHEN internal.is_audio_analysis_manifest(evidence) THEN 4",
  );
  assertStringIncludes(
    sql,
    "evidence_manifest->>'origin'='saved_identification'",
  );
  assertStringIncludes(sql, "p_reader NOT IN (9,10)");
  assertStringIncludes(
    sql,
    "IF p_reader<10 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE observation_id=observation AND internal.is_audio_analysis_manifest(evidence_manifest))",
  );
  assertStringIncludes(sql, "analysis_history_reader_upgrade_required");
});
Deno.test("audio initial expiry cannot renew bound evidence or choose a caller funding profile", () => {
  assertStringIncludes(
    sql,
    "p_initial AND cohort.expires_at<=clock_timestamp()",
  );
  assertStringIncludes(sql, "saved.expires_at<>cohort.expires_at");
  assertStringIncludes(sql, "saved.object_id<>cohort.object_id");
  assertStringIncludes(sql, "'multimodal_audio_v1'");
  assert(
    !/UPDATE internal\.observation_audio_evidence_upload_cohorts/.test(sql),
  );
  assert(
    !/DELETE FROM internal\.observation_audio_evidence_upload_cohorts/.test(
      sql,
    ),
  );
});
