import { validateInitialAdmissionMetadata } from "../_shared/initialAnalysis/admissionMetadata.ts";
import { assert, assertEquals, assertRejects } from "@std/assert";
import schema from "../_shared/initialAnalysis/admission-metadata-schema-v1.json" with {
  type: "json",
};
import vectors from "../_shared/initialAnalysis/fixtures/admission-metadata-v1.json" with {
  type: "json",
};
import originals from "../_shared/initialAnalysis/fixtures/qualified-preparation-v3.json" with {
  type: "json",
};
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261012010113_prepare_initial_admission_metadata.sql",
    import.meta.url,
  ),
);
const tests = await Deno.readTextFile(
  new URL("../../tests/initial_admission_metadata.sql", import.meta.url),
);
Deno.test("admission metadata SQL schema and both shared vector sets match Deno", () => {
  assertEquals(JSON.parse(sql.match(/\$json\$(.*?)\$json\$/s)![1]), schema);
  assertEquals(
    JSON.parse(tests.match(/\$vectors\$(.*?)\$vectors\$/s)![1]),
    vectors,
  );
  assertEquals(
    JSON.parse(tests.match(/\$originals\$(.*?)\$originals\$/s)![1]),
    originals,
  );
});
Deno.test("admission metadata SQL remains four revoked pure helpers", () => {
  assertEquals([...sql.matchAll(/CREATE FUNCTION /g)].length, 4);
  assert(
    !/SECURITY DEFINER|GRANT EXECUTE|CREATE OR REPLACE|CREATE TABLE|CREATE TRIGGER|INSERT INTO |UPDATE internal\./
      .test(sql),
  );
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
  assert(sql.includes("internal.assert_initial_qualified_outcome"));
  assert(sql.includes("internal.initial_handoff_phase_cutoffs"));
  assert(sql.includes("internal.parse_initial_input"));
});

Deno.test("SQL repeated-frame aggregate controls also exercise Deno profile limits", async () => {
  const cases = JSON.parse(tests.match(/\$resources\$(.*?)\$resources\$/s)![1]);
  for (const [name, item] of Object.entries(cases)) {
    const { o, v } = item as {
      o: typeof vectors.extra_originals[0];
      v: typeof vectors.valid[0];
    };
    const run = () =>
      validateInitialAdmissionMetadata(
        {
          candidate: o.candidate,
          assignment: o.assignment,
          catalog: o.catalog,
          outcome: o.outcome,
          originalExpiresAtMs: o.original_expires_at_ms,
        },
        v.scope,
        v.metadata,
      );
    if (name === "wide") await run();
    else await assertRejects(run, Error, "initial_analysis_input_invalid");
  }
});
