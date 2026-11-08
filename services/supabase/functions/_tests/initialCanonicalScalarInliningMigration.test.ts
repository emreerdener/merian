import { assert, assertEquals } from "@std/assert";

const read = (path: string) =>
  Deno.readTextFile(new URL(`../../${path}`, import.meta.url));
const sql = await read(
  "migrations/20261029042120_optimize_initial_canonical_scalar_children.sql",
);
const original = await read(
  "migrations/20261011070945_prepare_initial_analysis_admission.sql",
);
const catalog = await read("tests/initial_canonical_scalar_inlining.sql");

Deno.test("canonical differential oracle retains original recursive implementation", () => {
  const routine = original.slice(
    original.indexOf("CREATE FUNCTION internal.initial_canonical_parts("),
  ).split("\n$$;")[0] + "\n$$;";
  assert(
    routine.startsWith("CREATE FUNCTION internal.initial_canonical_parts("),
  );
  const oracle = catalog.split("-- BEGIN ORIGINAL CANONICAL ORACLE\n")[1]
    .split("\n-- END ORIGINAL CANONICAL ORACLE")[0];
  assertEquals(
    oracle,
    routine.replaceAll(
      "internal.initial_canonical_parts",
      "pg_temp.original_canonical_parts",
    ),
  );
  assertEquals(
    (oracle.match(/pg_temp.original_canonical_parts\(/g) ?? []).length,
    3,
  );
});

Deno.test("canonical optimization changes only the private encoder owner", () => {
  assertEquals(
    sql.match(/CREATE OR REPLACE FUNCTION\s+([^\s(]+)/g),
    ["CREATE OR REPLACE FUNCTION internal.initial_canonical_parts"],
  );
  assert(
    !/\b(?:GRANT|REVOKE|SECURITY DEFINER|CREATE TRIGGER|ALTER TABLE)\b/i.test(
      sql,
    ),
  );
  assert(
    !/\b(?:clock_timestamp|admission_expires_at|SET CONSTRAINTS)\b/.test(sql),
  );
  assert(sql.includes("LANGUAGE PLPGSQL STABLE SET search_path=''"));
  assertEquals(
    (sql.match(
      /FROM internal.initial_canonical_parts\(item.v,child_depth\) child/g,
    ) ?? []).length,
    2,
  );
});
