import { assert, assertStringIncludes } from "@std/assert";

const migration = new URL(
  "../../migrations/20260926142824_bind_identification_quota_to_provider.sql",
  import.meta.url,
);
Deno.test("provider admission preserves legacy quota and enables only exact Gemini assignments", async () => {
  const sql = (await Deno.readTextFile(migration)).replace(/\s+/g, " ");
  for (
    const text of [
      "PRIMARY KEY (operation, effective_plan, model, policy_version)",
      "AND policies.allowed AND policies.enabled",
      "PRIMARY KEY (reservation_id, attempt_count)",
      "REFERENCES internal.ai_quota_reservations(id) ON DELETE CASCADE",
      "CHECK (provider = 'gemini')",
      "CHECK (binding = 'gemini_baseline_v1')",
      "CHECK (processor_permission = 'google_gemini')",
      "PERFORM internal.require_service_role();",
      "SECURITY DEFINER SET search_path = ''",
      "p_processor_permission IS DISTINCT FROM 'google_gemini'",
      "PERFORM internal.require_current_ai_consent(p_user_id);",
      "IF NOT FOUND AND NOT admitted.is_replay THEN",
      "ON CONFLICT ON CONSTRAINT identification_provider_attempts_pkey DO NOTHING",
      "attempt.policy_version IS DISTINCT FROM admitted.policy_version",
      "attempt.effective_plan IS DISTINCT FROM admitted.effective_plan",
      "public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)",
    ]
  ) assertStringIncludes(sql, text);
  assert(
    !/CREATE(?: OR REPLACE)? FUNCTION public.reserve_ai_quota\(/.test(sql),
  );
  assert(!sql.includes("UPDATE internal.ai_quota_policies"));
  assert(!sql.includes("UPDATE public.user_ai_consent_events"));
  assert(!sql.includes("GRANT SELECT"));
  assert(!sql.includes("gpt-6-sol"));
});
