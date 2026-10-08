import { assert } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008210355_prepare_source_bound_initial_admission.sql",
    import.meta.url,
  ),
);
Deno.test("source admission funds only a fresh exact intent and preserves saved replay", () => {
  assert(sql.includes("saved.quota IS NOT NULL"));
  assert(sql.includes("p_request IS DISTINCT FROM p_analysis"));
  assert(sql.includes("internal.assert_observation_source_input_chain"));
  assert(
    sql.indexOf("RETURN to_jsonb(saved)-'draft'") <
      sql.indexOf("PERFORM internal.lock_observation_evidence_source"),
  );
  assert(sql.includes("p_input_profile=CASE b.input_snapshot"));
  assert(
    sql.includes(
      "public.reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)",
    ),
  );
  assert(
    !/GRANT |commit_identification_invocation|CREATE (?:OR REPLACE )?FUNCTION public\./
      .test(sql),
  );
});
