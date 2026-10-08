import { assert } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008213302_prepare_source_execution_lock_order.sql",
    import.meta.url,
  ),
);
Deno.test("source execution entry orders source and child before intent without opening dispatch", () => {
  assert(
    sql.indexOf("current_setting('transaction_isolation')") <
      sql.indexOf("SELECT * INTO binding"),
  );
  assert(
    sql.indexOf("PERFORM internal.lock_owned_observation_source(") <
      sql.indexOf("SELECT * INTO saved"),
  );
  assert(!sql.includes("internal.assert_observation_source_input_chain"));
  for (const name of ["claim", "dispatch", "complete", "fail"]) {
    assert(sql.includes(`internal.${name}_observation_analysis`));
  }
  assert(sql.includes("internal.record_observation_analysis_draft"));
  assert(sql.includes("public.advance_owned_observation_analysis"));
  assert(!sql.includes("GRANT "));
  assert(!sql.includes("commit_identification_invocation"));
});
