import { assert, assertEquals } from "@std/assert";
import {
  INITIAL_CANONICAL_LIMIT,
  initialCanonicalText,
} from "../_shared/initialAnalysis/canonical.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261013030931_align_initial_submission_storage_bounds.sql",
    import.meta.url,
  ),
);
const catalog = await Deno.readTextFile(
  new URL("../../tests/initial_submission_storage_bounds.sql", import.meta.url),
);
const runner = await Deno.readTextFile(
  new URL("../../scripts/test_database_catalogs.sh", import.meta.url),
);

Deno.test("submission storage repair preserves canonical limits and derives renderer allowance", () => {
  const renderingAllowance = 2 * (4096 - 1);
  assertEquals(INITIAL_CANONICAL_LIMIT, 1048576);
  assert(
    migration.includes(
      `octet_length(input_snapshot::TEXT) <= ${
        INITIAL_CANONICAL_LIMIT + renderingAllowance
      }`,
    ),
  );
  assert(
    migration.includes(
      `octet_length(ordered_descriptions::TEXT) <= ${
        INITIAL_CANONICAL_LIMIT + renderingAllowance
      }`,
    ),
  );
  const assignment = { payload: "a".repeat(65536 - 14) };
  assertEquals(
    new TextEncoder().encode(initialCanonicalText(assignment)).length,
    65536,
  );
  const configuration = { version: 2, assignment };
  assertEquals(
    new TextEncoder().encode(initialCanonicalText(configuration)).length,
    65563,
  );
  assert(
    migration.includes(
      `octet_length(configuration_snapshot::TEXT) <= ${
        65563 + renderingAllowance
      }`,
    ),
  );
  assertEquals([...migration.matchAll(/DROP CONSTRAINT /g)].length, 3);
  assertEquals([...migration.matchAll(/ADD CONSTRAINT /g)].length, 3);
  assert(
    !/CREATE (?:OR REPLACE )?FUNCTION|CREATE TRIGGER|GRANT |UPDATE |DELETE FROM |INSERT INTO /
      .test(migration),
  );
  assert(
    !/DROP CONSTRAINT .*funding|ALTER TABLE internal.initial_analysis_(results|completions)/
      .test(migration),
  );
});

Deno.test("effective catalog regression is discovered and covers renderer and canonical rejection separately", () => {
  assert(runner.includes("catalog_tests=(services/supabase/tests/*.sql)"));
  for (
    const witness of [
      "chr(1)",
      "chr(128998)",
      "4096",
      "8190",
      "canonical cap+one still denied",
      "raw storage cap+one denied",
      "LIKE internal.initial_analysis_submissions INCLUDING CONSTRAINTS",
    ]
  ) {
    assert(catalog.includes(witness));
  }
});
