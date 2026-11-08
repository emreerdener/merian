import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/admitted-proof-schema-v1.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/admitted-proof-v1.json" with {
  type: "json",
};
import {
  ADMITTED_COMPONENT_LIMITS,
  ADMITTED_MANIFEST_LIMIT,
  validAdmittedTimestamp,
} from "../_shared/initialAnalysis/admittedProof.ts";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261012031316_prepare_initial_admitted_proof.sql",
    import.meta.url,
  ),
);
const tests = await Deno.readTextFile(
  new URL("../../tests/initial_admitted_proof.sql", import.meta.url),
);
Deno.test("complete admitted SQL embeds the same closed schema and complete golden/negative vectors", () => {
  assertEquals(JSON.parse(sql.match(/\$json\$(.*?)\$json\$/s)![1]), schema);
  assertEquals(
    JSON.parse(tests.match(/\$vectors\$(.*?)\$vectors\$/s)![1]),
    vectors,
  );
});
Deno.test("complete admitted SQL stays private pure fixed-text validation without runtime authority", () => {
  assertEquals([...sql.matchAll(/CREATE FUNCTION /g)].length, 4);
  assert(
    !/SECURITY DEFINER|GRANT EXECUTE|CREATE OR REPLACE|CREATE TABLE|CREATE TRIGGER|INSERT INTO |UPDATE internal\./
      .test(sql),
  );
  assertEquals([...sql.matchAll(/SET search_path=''/g)].length, 4);
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(sql.includes("internal.validate_initial_admission_metadata("));
  const signature = sql.match(
    /CREATE FUNCTION internal.validate_initial_admitted_proof\(([\s\S]*?)\) RETURNS TEXT/,
  )![1];
  assertEquals([...signature.matchAll(/\bTEXT\b/g)].length, 12);
  for (
    const [key, cap] of Object.entries({
      ...ADMITTED_COMPONENT_LIMITS,
      manifest: ADMITTED_MANIFEST_LIMIT,
    })
  ) {
    assert(sql.includes(`WHEN '${key}' THEN ${cap}`));
  }
  assert(
    sql.indexOf("octet_length(p_text)>cap") < sql.indexOf("p_text::JSONB"),
  );
  assert(sql.includes("total>2469915"));
});
Deno.test("complete admitted SQL timestamp corpus matches exact Deno Gregorian validation", () => {
  const corpus = JSON.parse(
    tests.match(/\$timestamps\$(.*?)\$timestamps\$/s)![1],
  );
  for (const value of corpus.valid) assert(validAdmittedTimestamp(value));
  for (const value of corpus.invalid) assert(!validAdmittedTimestamp(value));
});
