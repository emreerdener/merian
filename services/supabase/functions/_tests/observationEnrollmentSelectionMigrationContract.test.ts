import { assert, assertStringIncludes } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261104211256_recover_observation_enrollment_selection.sql",
    import.meta.url,
  ),
);
const body = sql.split("AS $$")[1].split("$$;")[0];
Deno.test("enrollment selection composes existing locked readers without creation or lock upgrade", () => {
  assertStringIncludes(body, "p_reader IS DISTINCT FROM 11");
  assertStringIncludes(
    body,
    "public.get_owned_observation_enrollment_baseline(p_request,9)",
  );
  assertEqualsCalls(2);
  assert(
    body.indexOf("get_owned_observation_enrollment_baseline") <
      body.indexOf("get_owned_observation_analysis_state"),
  );
  assert(
    !/\b(INSERT|UPDATE|DELETE|MERGE|COMMIT|enroll_owned_observation_history)\b/i
      .test(body),
  );
  for (
    const field of [
      "owner_id",
      "observation_id",
      "state_revision",
      "selected_analysis_id",
    ]
  ) {
    assertStringIncludes(
      body,
      `baseline->'${field}' IS DISTINCT FROM selected->'${field}'`,
    );
  }
  assertStringIncludes(
    body,
    "baseline#>>'{analysis,snapshot}' IS DISTINCT FROM association->>'snapshot'",
  );
});
function assertEqualsCalls(count: number) {
  assert(
    (body.match(/public\.get_owned_observation_analysis_state\(/g) ?? [])
      .length === count,
  );
}
Deno.test("enrollment selection is authenticated-only with one combined byte limit", () => {
  assertStringIncludes(sql, "SECURITY DEFINER SET search_path = ''");
  assertStringIncludes(sql, "FROM PUBLIC,anon,authenticated,service_role;");
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.get_owned_observation_enrollment_selection(JSONB,INTEGER) TO authenticated;",
  );
  assertStringIncludes(body, "pg_catalog.octet_length(response::TEXT)>4194304");
  assertStringIncludes(
    body,
    "'baseline_sha256',association->'snapshot_sha256'",
  );
  assert(!/SET\s+(reader_enabled|state_reader_enabled)\s*=\s*TRUE/i.test(sql));
});
