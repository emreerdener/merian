import { assert } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008203348_bind_source_evidence_writers.sql",
    import.meta.url,
  ),
);
Deno.test("source evidence writers retain closed funding and source-first ordering", () => {
  assert(
    sql.includes(
      "lock_owned_observation_source_binding(p_owner,p_observation,p_analysis,binding.input_snapshot)",
    ),
  );
  assert(
    sql.indexOf("merian-scan-ingestion:") <
      sql.indexOf("merian-history-evidence:"),
  );
  assert(
    sql.includes(
      "saved.binding_analysis_id IS DISTINCT FROM binding.analysis_id",
    ),
  );
  assert(
    sql.includes(
      "internal.complete_observation_evidence(uuid,uuid,uuid,uuid,uuid)",
    ),
  );
  assert(
    sql.includes(
      "public.complete_owned_observation_audio_evidence_upload(uuid,uuid,uuid,uuid,uuid)",
    ),
  );
  assert(
    !/GRANT |reserve_identification_quota|commit_identification_invocation/
      .test(sql),
  );
});
