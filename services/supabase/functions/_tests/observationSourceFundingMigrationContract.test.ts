import { assert, assertEquals } from "@std/assert";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008184228_fence_source_bound_analysis_funding.sql",
    import.meta.url,
  ),
);
Deno.test("source funding fences preserve exact dispatch replay and scoped original identity", () => {
  assertEquals((source.match(/anchor:=/g) ?? []).length, 2);
  assertEquals((source.match(/INTO STRICT definition/g) ?? []).length, 2);
  assert(source.includes("analysis_id=p_original_analysis_id"));
  assert(source.includes("analysis_id=reserved.original_analysis_id"));
  assert(!source.includes("analysis_id=p_request_id"));
  assert(source.includes("reserved.state <> ''reserved''"));
  assert(source.includes("analysis_history_current_snapshot_required"));
  assert(
    !/GRANT |CREATE TABLE|CREATE (?:OR REPLACE )?FUNCTION public\./.test(
      source,
    ),
  );
});
