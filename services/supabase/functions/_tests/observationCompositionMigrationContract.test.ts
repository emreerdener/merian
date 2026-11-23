import { assert, assertEquals } from "@std/assert";
const source = await Deno.readTextFile(
  new URL(
    "../../migrations/20261114192749_prepare_composition_source_contract.sql",
    import.meta.url,
  ),
);
Deno.test("composition metadata SQL is private and cannot install admission or execution", () => {
  assertEquals(
    (source.match(/STABLE SECURITY INVOKER SET search_path=''/g) ?? []).length,
    3,
  );
  assertEquals(
    (source.match(
      /REVOKE ALL ON FUNCTION internal\.observation_composition_source_\w+\(JSONB\) FROM PUBLIC,anon,authenticated,service_role/g,
    ) ?? []).length,
    3,
  );
  assert(
    !/\b(?:INSERT|UPDATE|DELETE|GRANT|SECURITY DEFINER|CREATE TABLE)\b/.test(
      source,
    ),
  );
  assert(source.includes("merian.analysis-composition-source-binding"));
  assert(source.includes("octet_length(framed)>262144"));
  assert(source.includes("'node_index',node_index"));
  assert(source.includes("item->>'media_id'=ANY(seen)"));
});

Deno.test("composition readiness prerequisite has no funding or execution grant", async () => {
  const guard = await Deno.readTextFile(
    new URL(
      "../../migrations/20261114221256_prepare_composition_execution_evidence_guard.sql",
      import.meta.url,
    ),
  );
  assert(
    !/\b(?:INSERT|UPDATE|DELETE|GRANT)\b/.test(
      guard.replace(/FOR UPDATE/g, ""),
    ),
  );
  assert(guard.includes("allocation.expires_at<=clock_timestamp()"));
  assert(guard.includes("internal.composition_evidence_receipt(binding)"));
  assert(guard.includes("ORDER BY media_id FOR UPDATE"));
  assert(guard.includes("'analysis_history_current_snapshot_required'"));
  assert(
    guard.includes("internal.observation_composition_source_contract(p_input)"),
  );
});
