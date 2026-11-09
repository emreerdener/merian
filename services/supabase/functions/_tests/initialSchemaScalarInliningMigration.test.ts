import { assert, assertEquals, assertMatch } from "@std/assert";
const base = new URL("../../", import.meta.url);
const original = await Deno.readTextFile(
  new URL(
    "migrations/20261011070945_prepare_initial_analysis_admission.sql",
    base,
  ),
);
const repair = await Deno.readTextFile(
  new URL(
    "migrations/20261109072401_inline_initial_schema_scalar_children.sql",
    base,
  ),
);
const catalog = await Deno.readTextFile(
  new URL("tests/initial_schema_scalar_inlining.sql", base),
);
function routine(sql: string, name: string): string {
  const start = sql.indexOf(name + "(");
  return sql.slice(start, sql.indexOf("$$;", start) + 3);
}
Deno.test("schema scalar oracle is independently recursive historical code", () => {
  assertEquals(
    routine(catalog, "pg_temp.original_schema_matches").replaceAll(
      "pg_temp.original_schema_matches",
      "internal.initial_schema_matches",
    ),
    routine(original, "internal.initial_schema_matches"),
  );
  assertMatch(
    catalog,
    /GET STACKED DIAGNOSTICS code=RETURNED_SQLSTATE,message=MESSAGE_TEXT/,
  );
  assertMatch(catalog, /IS NOT DISTINCT FROM/);
});
Deno.test("scalar inlining retains root semantics, container recursion and privileges", () => {
  assertEquals(
    [...repair.matchAll(/CREATE OR REPLACE FUNCTION (\S+)\(/g)].map((m) =>
      m[1]
    ),
    ["internal.initial_schema_matches"],
  );
  assertEquals(
    /\b(?:GRANT|REVOKE|ALTER|DROP|SECURITY DEFINER)\b/.test(repair),
    false,
  );
  assertMatch(repair, /depth INTEGER DEFAULT 0/);
  assertMatch(repair, /LANGUAGE PLPGSQL STABLE SET search_path=''/);
  const root = original.slice(
    original.indexOf(" WHEN 'boolean' THEN RETURN"),
    original.indexOf("REVOKE ALL"),
  );
  assert(repair.includes(root.trim()));
  assertEquals(
    [...repair.matchAll(/child_depth:=depth\+1; child_result:=NULL;/g)].length,
    2,
  );
  assertEquals(
    [...repair.matchAll(
      /IF child_depth>12 OR child_value IS NULL THEN child_result:=FALSE;/g,
    )].length,
    2,
  );
  assertEquals(
    [...repair.matchAll(
      /child_result:=internal.initial_schema_matches\(child_value,child_rule,child_depth\);/g,
    )].length,
    2,
  );
  assertEquals(
    [...repair.matchAll(/IF NOT child_result THEN RETURN FALSE; END IF;/g)]
      .length,
    2,
  );
});
