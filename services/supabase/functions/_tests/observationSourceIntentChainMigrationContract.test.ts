import { assert } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008200418_fence_source_bound_analysis_intents.sql",
    import.meta.url,
  ),
);
Deno.test("source-bound intent backstop requires a linked chain without changing funding grants", () => {
  assert(
    sql.includes("cohort.binding_analysis_id IS DISTINCT FROM p_analysis"),
  );
  assert(sql.includes("audio.binding_analysis_id IS DISTINCT FROM p_analysis"));
  assert(sql.includes("binding.input_snapshot IS DISTINCT FROM p_input"));
  assert(sql.includes("a_guard_source_bound_analysis_intent BEFORE INSERT"));
  assert(
    !/GRANT |CREATE (?:OR REPLACE )?FUNCTION public\.|set_config\(/.test(sql),
  );
  assert(
    sql.indexOf("merian-scan-ingestion:") <
      sql.indexOf("merian-history-evidence:"),
  );
});
