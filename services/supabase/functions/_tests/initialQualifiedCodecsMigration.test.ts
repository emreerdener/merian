import { assert, assertEquals } from "@std/assert";
import assignment from "../_shared/initialAnalysis/media-assignment-schema-v3.json" with {
  type: "json",
};
import response from "../_shared/initialAnalysis/media-preparation-response-schema-v3.json" with {
  type: "json",
};
import execution from "../_shared/initialAnalysis/preparation-execution-schema-v2.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/qualified-preparation-v3.json" with {
  type: "json",
};
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011233227_prepare_initial_qualified_codecs.sql",
    import.meta.url,
  ),
);
const tests = await Deno.readTextFile(
  new URL("../../tests/initial_qualified_codecs.sql", import.meta.url),
);
Deno.test("qualified schemas and vectors are byte-protocol peers in SQL and Deno", () => {
  assertEquals(JSON.parse(sql.match(/\$json\$(.*?)\$json\$/s)![1]), {
    ...execution,
    assignment,
    ...response,
  });
  assertEquals(
    JSON.parse(tests.match(/\$vectors\$(.*?)\$vectors\$/s)![1]),
    vectors,
  );
});
Deno.test("qualified codec migration creates only revoked invoker validators with no owner replacement", () => {
  assertEquals([...sql.matchAll(/CREATE FUNCTION /g)].length, 9);
  assert(
    !/CREATE OR REPLACE|SECURITY DEFINER|GRANT EXECUTE|CREATE TABLE|INSERT INTO internal\.|UPDATE internal\./
      .test(sql),
  );
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
});
