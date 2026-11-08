import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/handoff-catalog-schema-v1.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/handoff-catalog-v1.json" with {
  type: "json",
};
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011231025_prepare_initial_handoff_catalogs.sql",
    import.meta.url,
  ),
);
const tests = await Deno.readTextFile(
  new URL("../../tests/initial_handoff_catalogs.sql", import.meta.url),
);
Deno.test("handoff catalog closed schema and vectors match SQL", () => {
  assertEquals(JSON.parse(sql.match(/\$json\$(.*?)\$json\$/s)![1]), schema);
  assertEquals(
    JSON.parse(tests.match(/\$vectors\$(.*?)\$vectors\$/s)![1]),
    vectors,
  );
});
Deno.test("catalog is empty private installation metadata with no resolver adoption", () => {
  assertEquals([...sql.matchAll(/CREATE TABLE /g)].length, 4);
  assertEquals([...sql.matchAll(/CREATE FUNCTION /g)].length, 7);
  assert(
    !/SECURITY DEFINER|GRANT EXECUTE|CREATE OR REPLACE|INSERT INTO internal\.|UPDATE internal\./
      .test(sql),
  );
  assert(sql.includes("ADD COLUMN handoff_installation_digest TEXT;"));
  assert(
    sql.includes(
      "FOREIGN KEY(handoff_installation_digest,profile_digest,backend_generation)",
    ),
  );
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
});
