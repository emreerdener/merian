import { assert, assertEquals } from "@std/assert";
import schema from "../_shared/initialAnalysis/preparation-execution-schema-v1.json" with {
  type: "json",
};
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011205141_prepare_initial_preparation_execution.sql",
    import.meta.url,
  ),
);
Deno.test("preparation execution SQL shares exact closed receipt and reply schemas", () => {
  assertEquals(JSON.parse(sql.split("$json$")[1]), schema);
  for (
    const kind of [
      "held",
      "status",
      "verified",
      "granted",
      "registered",
      "outcome_ready",
    ]
  ) assert(Object.hasOwn(schema, `reply_${kind}`));
  assertEquals(
    (sql.match(
      /RETURN internal.checked_initial_preparation_reply\(internal.initial_preparation_execution_action/g,
    ) ?? []).length,
    5,
  );
});
Deno.test("preparation extension installs no production selection or caller privilege", () => {
  for (
    const relation of [
      "initial_preparation_profiles",
      "initial_preparation_installations",
      "initial_preparation_source_backends",
      "initial_preparation_current_selection",
    ]
  ) assert(!sql.includes(`INSERT INTO internal.${relation}`));
  assert(!sql.includes("SET initial_analysis_lifecycle_enabled=TRUE"));
  assert(sql.includes("ENABLE ROW LEVEL SECURITY"));
  assert(sql.includes("FROM PUBLIC,anon,authenticated,service_role"));
});
Deno.test("preparation authority separates status, fresh grant and original settlement", () => {
  const status = sql.split("IF p_action='status' THEN")[1].split("END IF;")[0];
  assert(status.includes("'execution_reference'"));
  assert(!status.includes("'grant',grant_value"));
  assert(!status.includes("deadline_ms"));
  assert(sql.includes("pg_try_advisory_xact_lock"));
  assert(
    sql.includes("internal.can_cancel_initial_preparation(p_owner,p_scan)"),
  );
  assert(
    sql.includes(
      "internal.initial_preparation_cohort_wall(saved.canonical_assignment::JSONB,profile)",
    ),
  );
});

Deno.test("preparation barrier precedes historical blocking trigger names", () => {
  assert(
    sql.includes("CREATE TRIGGER a0_initial_preparation_provider_barrier"),
  );
  for (
    const previous of [
      "a_guard_history_child_scan_identity",
      "a_guard_source_bound_analysis_intent",
    ]
  ) {
    assert("a0_initial_preparation_provider_barrier" < previous);
  }
});
