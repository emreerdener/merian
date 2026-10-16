import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/media-source-candidate-schema-v2.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/media-source-v2.json" with {
  type: "json",
};
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011192015_prepare_initial_media_source_contract.sql",
    import.meta.url,
  ),
);
const sqlTests = await Deno.readTextFile(
  new URL("../../tests/initial_media_source_contract.sql", import.meta.url),
);
Deno.test("source schema and test vectors agree across SQL and TypeScript", () => {
  assertEquals(
    JSON.parse(migration.match(/SELECT '(.*?)'::JSONB;/s)![1]),
    schema,
  );
  assertEquals(
    JSON.parse(
      sqlTests.match(/SELECT '(.*?)'::JSONB v;/s)![1].replaceAll("''", "'"),
    ),
    vectors,
  );
});
Deno.test("source contract adds only revoked private pure functions", () => {
  assertEquals([...migration.matchAll(/CREATE FUNCTION /g)].length, 3);
  assert(
    !/CREATE (?:TABLE|TRIGGER)|CREATE OR REPLACE|SECURITY DEFINER|GRANT EXECUTE|INSERT INTO|UPDATE internal|DELETE FROM/
      .test(migration),
  );
  for (
    const name of [
      "initial_media_source_candidate_schema_v2()",
      "initial_media_source_semantics(JSONB)",
      "parse_initial_media_source_candidate(TEXT)",
    ]
  ) {
    assert(migration.includes(`internal.${name}`));
  }
  assert(migration.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(!migration.includes("initial_analysis_rollout"));
});
