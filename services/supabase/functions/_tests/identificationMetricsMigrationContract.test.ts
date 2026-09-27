import { assert, assertStringIncludes } from "@std/assert";
Deno.test("metric qualification migration retains legacy absence and all durable consumers", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20260927004054_qualify_identification_metrics_by_provenance.sql",
      import.meta.url,
    ),
  );
  for (
    const expected of [
      "IF p_value IS NULL THEN RETURN TRUE",
      "internal.identification_provenance_is_valid(p_value) IS NOT TRUE",
      "IMMUTABLE",
      "PARALLEL SAFE",
      "SECURITY INVOKER",
      "SET search_path = ''",
      "ai_confidence_qualified BOOLEAN",
      "WHEN metrics.compatible AND",
      "CASE WHEN metrics.compatible THEN s.ai_confidence_score ELSE NULL END",
      "OR candidate.user_confirmed_identification IS TRUE",
      "'ai_confidence_qualified', internal.identification_metrics_are_gemini_compatible",
      "OLD.identification_provenance IS DISTINCT FROM NEW.identification_provenance",
      "public.apply_field_trip_scan_progress_atomic",
      "DO $repair$",
      "Ineligible subject credit remains",
      "Unexpected routine shape for metric compatibility",
      "WHERE ai_confidence_qualified AND ai_confidence_score >= 0.98",
      "AND internal.identification_metrics_are_gemini_compatible(s.identification_provenance, s.inference_tier)",
    ]
  ) assertStringIncludes(sql, expected);
  assertEqualsCount(
    sql,
    "ORDER BY source_rank, confidence_score DESC NULLS LAST, candidate_ordinality",
    3,
  );
  assert(!sql.includes("UPDATE internal.ai_quota_policies"));
  assert(!sql.includes("UPDATE public.scans"));
});
function assertEqualsCount(source: string, fragment: string, expected: number) {
  assert(source.split(fragment).length - 1 === expected);
}
