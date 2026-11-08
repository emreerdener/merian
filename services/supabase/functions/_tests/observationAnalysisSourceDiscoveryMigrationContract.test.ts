import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261008153538_prepare_analysis_source_discovery.sql",
    import.meta.url,
  ),
);
const body = sql.split("AS $$")[1].split("$$;")[0];
Deno.test("source discovery is service-only gated read-only metadata, never vacancy or execution", () => {
  assertStringIncludes(
    sql,
    "source_discovery_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assertStringIncludes(body, "PERFORM internal.require_service_role()");
  assertStringIncludes(body, "p_reader IS DISTINCT FROM 10");
  assertStringIncludes(
    sql,
    "GRANT EXECUTE ON FUNCTION public.get_owned_observation_analysis_source(UUID,JSONB,INTEGER) TO service_role",
  );
  assert(!/\b(INSERT INTO|UPDATE|DELETE FROM)\b/i.test(body));
  assert(
    !/advisory_absence|reserve_identification|dispatch_observation|claim_observation/
      .test(body),
  );
  assertStringIncludes(sql, "FROM PUBLIC,anon,authenticated,service_role");
  assert(!/CREATE UNIQUE INDEX/.test(sql));
});
Deno.test("source discovery locks before sentinel scans and retains canonical terminal proof", () => {
  assert(
    body.indexOf("lock_owned_observation_evidence") < body.indexOf("LIMIT 65"),
  );
  assertEqualsCount(body, "LIMIT 65", 2);
  for (
    const proof of [
      "saved.draft-'result_snapshot'",
      "saved.provider_usage",
      "internal.observation_analysis_snapshot(",
      "retired.request_identity",
      "ambiguous_occupancy",
      "coverage_incomplete",
      "terminal_unproven",
    ]
  ) assertStringIncludes(body, proof);
  assert(
    !/FROM internal\.(ai_quota_reservations|identification_invocations)/.test(
      body,
    ),
  );
});
Deno.test("source discovery preserves historical photo providers and audio-specific protocol", () => {
  assertEqualsCount(body, "IN ('google_gemini','openai')", 2);
  for (
    const protocol of [
      "input->'history_protocol'='7'",
      "input->'history_protocol'='8'",
      "input->'history_protocol'='9'",
    ]
  ) assertStringIncludes(body, protocol);
  assertStringIncludes(
    body,
    "input->>'expected_processor_permission'='google_gemini'",
  );
});
function assertEqualsCount(text: string, part: string, count: number) {
  assert(text.split(part).length - 1 === count);
}
