import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/handoff-profile-schema-v1.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/handoff-profile-v1.json" with {
  type: "json",
};
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011224842_prepare_initial_handoff_contract.sql",
    import.meta.url,
  ),
);
const tests = await Deno.readTextFile(
  new URL("../../tests/initial_handoff_contract.sql", import.meta.url),
);
Deno.test("handoff SQL schema and vectors match accepted Deno source", () => {
  assertEquals(
    JSON.parse(migration.match(/\$json\$(.*?)\$json\$/s)![1]),
    schema,
  );
  assertEquals(
    JSON.parse(tests.match(/\$vectors\$(.*?)\$vectors\$/s)![1]),
    vectors,
  );
});
Deno.test("handoff SQL adds private pure invoker helpers without authority", () => {
  assertEquals([...migration.matchAll(/CREATE FUNCTION /g)].length, 7);
  assert(
    !/CREATE (?:TABLE|TRIGGER)|CREATE OR REPLACE|SECURITY DEFINER|GRANT EXECUTE|INSERT INTO|UPDATE internal|DELETE FROM/
      .test(migration),
  );
  assert(migration.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(!migration.includes("initial_analysis_rollout"));
  assertEquals([...migration.matchAll(/SET search_path=''/g)].length, 7);
});
