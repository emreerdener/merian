import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261007193516_prepare_audio_history_action_readers.sql",
    import.meta.url,
  ),
);
Deno.test("audio action compatibility is private, lock-preconditioned and never a rollout", () => {
  assertStringIncludes(
    sql,
    "REVOKE ALL ON FUNCTION internal.require_observation_action_reader(UUID,INTEGER,UUID)",
  );
  assertStringIncludes(sql, "FROM PUBLIC,anon,authenticated,service_role");
  assertStringIncludes(sql, "p_reader IS NULL OR p_reader NOT IN (9,10)");
  assertStringIncludes(
    sql,
    "internal.is_audio_analysis_manifest(evidence_manifest)",
  );
  assertStringIncludes(
    sql,
    "observation_id=p_observation AND analysis_id=p_analysis",
  );
  assertStringIncludes(sql, "input_snapshot->'schema_version'='3'::JSONB");
  assert(
    !/GRANT EXECUTE|UPDATE internal\.observation_history_rollout/.test(sql),
  );
});
Deno.test("audio action patch changes only seven closed owners and rejects source drift", () => {
  for (
    const name of [
      "select_owned_observation_analysis",
      "review_owned_observation_analysis",
      "get_owned_observation_confirmation_undo",
      "get_owned_observation_rejection_undo",
      "confirm_observation_analysis",
      "get_owned_observation_analysis_execution",
      "retire_owned_observation_analysis_execution",
    ]
  ) {
    assertStringIncludes(sql, name);
  }
  assertStringIncludes(sql, "audio_action_reader_source_drift");
  assertStringIncludes(
    sql,
    "pg_catalog.replace(definition,anchor,replacement)",
  );
  for (
    const name of [
      "enroll_owned_observation_history",
      "observation_candidate_name",
      "dispatch_observation_analysis",
      "reserve_owned_observation_evidence",
    ]
  ) assert(!sql.includes(name));
});
