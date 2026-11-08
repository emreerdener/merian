import { assert, assertEquals } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008194407_prepare_source_linked_evidence_cohorts.sql",
    import.meta.url,
  ),
);
Deno.test("source cohort links remain additive with no API or admission cutover", () => {
  assertEquals(
    (sql.match(/ADD COLUMN binding_analysis_id UUID/g) ?? []).length,
    2,
  );
  assertEquals((sql.match(/ON DELETE CASCADE/g) ?? []).length, 2);
  assert(sql.includes("IF NEW.binding_analysis_id IS NULL THEN RETURN NEW;"));
  assert(sql.includes("jsonb_agg(item-'kind' ORDER BY ordinal)"));
  assert(
    !/CREATE (?:OR REPLACE )?FUNCTION public\.|GRANT |UPDATE internal\.|pg_advisory/
      .test(sql),
  );
});
