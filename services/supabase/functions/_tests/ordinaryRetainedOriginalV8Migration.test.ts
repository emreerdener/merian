import { assert } from "@std/assert";
import {
  INITIAL_ORIGINAL_COHORT_MAX_BYTES,
  INITIAL_ORIGINAL_MAX_BYTES,
  INITIAL_V8_MAX_BYTES,
} from "../_shared/analysisHistory/initialEvidenceManifest.ts";
import { MEDIA_BUDGETS } from "../_shared/mediaBudgets.ts";

const path = new URL(
  "../../migrations/20261120181001_prepare_ordinary_retained_original_v8.sql",
  import.meta.url,
);
Deno.test("ordinary original successor keeps provider budgets and grants separate", async () => {
  const sql = await Deno.readTextFile(path);
  assert(sql.includes(`maximum:=${INITIAL_ORIGINAL_MAX_BYTES}`));
  assert(sql.includes(`original_bytes>${INITIAL_ORIGINAL_COHORT_MAX_BYTES}`));
  assert(sql.includes(`version=8 THEN ${INITIAL_V8_MAX_BYTES} ELSE 33554432`));
  assert(sql.includes(`image_bytes>${MEDIA_BUDGETS.maxImageRawBytes}`));
  assert(sql.includes("p_scan,p_generation,version::TEXT"));
  assert(
    !/GRANT\s|UPDATE\s+internal\.observation_history_rollout|cron\.schedule/i
      .test(sql),
  );
});

Deno.test("original reader migration gates new evidence and preserves completed proof boundaries", async () => {
  const sql = await Deno.readTextFile(path);
  assert(sql.includes("p_reader<>17 AND EXISTS"));
  assert(
    sql.includes(
      "p_reader=17 AND result_row.evidence_manifest->'schema_version'='8'::JSONB",
    ),
  );
  assert(
    sql.includes(
      "IF p_protocol<>4 THEN RAISE EXCEPTION 'analysis_history_reader_upgrade_required'",
    ),
  );
  assert(sql.includes("jsonb_build_object('artifact_role',object.role)"));
  assert(sql.includes("internal.guard_initial_history_baseline()"));
  assert(sql.includes("internal.fence_imported_observation_result()"));
  assert(sql.includes("ordinary_original_v8_constraint_drift"));
  assert(sql.includes("ordinary_original_v8_source_drift"));
});
