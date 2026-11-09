import { assertEquals, assertMatch } from "@std/assert";

const base = new URL("../../", import.meta.url);
const original = await Deno.readTextFile(
  new URL(
    "migrations/20261012010113_prepare_initial_admission_metadata.sql",
    base,
  ),
);
const repair = await Deno.readTextFile(
  new URL(
    "migrations/20261109071913_deduplicate_initial_metadata_digest_validation.sql",
    base,
  ),
);
const catalog = await Deno.readTextFile(
  new URL("tests/initial_admission_metadata.sql", base),
);
function routine(sql: string, name: string): string {
  const start = sql.indexOf(name + "(");
  return sql.slice(start, sql.indexOf("END; $$;", start) + "END; $$;".length);
}
const name = "internal.validate_initial_admission_metadata";
const substitutions = [
  [
    "internal.initial_qualified_outcome_digest(p_outcome)",
    "preparation-execution.outcome.v2",
    "p_outcome",
  ],
  [
    "internal.initial_admission_metadata_digest('phase_window',p_window)",
    "handoff.phase_window.v1",
    "p_window",
  ],
  [
    "internal.initial_admission_metadata_digest('mapping',p_mapping)",
    "handoff.mapping.v2",
    "p_mapping",
  ],
  [
    "internal.initial_admission_metadata_digest('media_binding',p_binding)",
    "handoff.media_binding.v2",
    "p_binding",
  ],
];
Deno.test("metadata repair changes only four digest reparses within the original invocation", () => {
  let expected = routine(original, name);
  for (const [call, domain, argument] of substitutions) {
    assertEquals(expected.split(call).length, 2);
    expected = expected.replace(
      call,
      `encode(extensions.digest(convert_to('merian.initial-analysis.${domain}'||chr(10)||${argument},'UTF8'),'sha256'),'hex')`,
    );
  }
  assertEquals(routine(repair, name), expected);
  assertEquals(
    [...repair.matchAll(/CREATE OR REPLACE FUNCTION (\S+)\(/g)].map((m) =>
      m[1]
    ),
    [name],
  );
  assertEquals(
    /\b(?:GRANT|REVOKE|ALTER|DROP|SECURITY DEFINER)\b/.test(repair),
    false,
  );
});
Deno.test("metadata differential oracle is the unchanged historical validator", () => {
  assertEquals(
    routine(catalog, "pg_temp.metadata_original").replace(
      "pg_temp.metadata_original",
      name,
    ),
    routine(original, name),
  );
  assertMatch(catalog, /previous IS DISTINCT FROM current_value/);
  assertMatch(catalog, /previous_state IS DISTINCT FROM current_state/);
  assertMatch(catalog, /previous_message IS DISTINCT FROM current_message/);
});
