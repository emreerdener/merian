import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261109002827_repair_initial_history_routine_lint.sql",
    import.meta.url,
  ),
);

Deno.test("History lint repair preserves routine exposure and migration boundaries", () => {
  assertEquals(
    [...sql.matchAll(/CREATE OR REPLACE FUNCTION internal\./g)].length,
    17,
  );
  assertEquals([...sql.matchAll(/ALTER FUNCTION internal\./g)].length, 22);
  assert(
    !/\b(?:GRANT|REVOKE|SECURITY DEFINER|CREATE TABLE|ALTER TABLE)\b/i.test(
      sql,
    ),
  );
  assert(!/^\s*(?:BEGIN|COMMIT|ROLLBACK)\s*;/im.test(sql));
  assertStringIncludes(sql, "SET lock_timeout = '5s';");
  assertStringIncludes(sql, "RESET lock_timeout;");
  assertStringIncludes(sql, "RESET statement_timeout;");
  const definitions = sql.split("CREATE OR REPLACE FUNCTION ").slice(1);
  for (const definition of definitions) {
    assert(
      /SET search_path\s*(?:=|TO)\s*''/i.test(definition.split(/AS \$/)[0]),
    );
  }
});

Deno.test("History lint repair retains exact validation and consumed-context denial", () => {
  const normalized = sql.replaceAll(/\s+/g, " ");
  assertStringIncludes(
    normalized,
    "PERFORM internal.assert_initial_admitted_accounting(a,input_value->'admission',funding,accounting,manifest);",
  );
  assertStringIncludes(
    normalized,
    "PERFORM internal.parse_initial_cpm_photo_assignment(p_candidate,value->>'assignment_canonical');",
  );
  assertStringIncludes(
    normalized,
    "AND old_digest=internal.initial_cpm_verification_intent_digest(p_old) AND new_digest=internal.initial_cpm_verification_intent_digest(p_new) ; IF NOT FOUND THEN RAISE EXCEPTION 'initial_analysis_storage_immutable'",
  );
  assertStringIncludes(
    normalized,
    "FROM internal.lock_initial_dispatched_original(p_owner,p_scan,p_submission_digest,p_invocation,p_lease_token,'report');",
  );
  assertStringIncludes(
    normalized,
    "ALTER FUNCTION internal.assert_initial_cancellation_erasure_boundary(internal.initial_admitted_cancellation_staging,jsonb) VOLATILE;",
  );
  assertStringIncludes(
    normalized,
    "ALTER FUNCTION internal.capture_initial_cancellation_accounting_images(internal.initial_admitted_cancellation_staging) VOLATILE;",
  );
});
