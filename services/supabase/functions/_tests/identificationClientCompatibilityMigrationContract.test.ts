import { assert, assertStringIncludes } from "@std/assert";

Deno.test("identification compatibility is dormant and preserves old RPC and recovery contracts", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260926200227_add_identification_client_compatibility.sql",
      import.meta.url,
    ),
  )).replace(/\s+/g, " ");
  for (
    const fragment of [
      "ADD COLUMN minimum_client_protocol INTEGER NOT NULL DEFAULT 0",
      "ADD COLUMN minimum_client_protocol INTEGER CHECK",
      "ADD COLUMN accepted_client_protocol INTEGER CHECK (accepted_client_protocol BETWEEN 1 AND 3)",
      "SECURITY INVOKER SET search_path = ''",
      "FROM PUBLIC, anon, authenticated, service_role",
      "public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)",
      "public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)",
      "source.user_id = p_user_id",
      "source.operation = p_operation",
      "source.request_id = p_original_analysis_id",
      "source.original_analysis_id = p_original_analysis_id",
      "saved.attempt_count = source.attempt_count",
      "saved.input_profile IS NOT DISTINCT FROM p_input_profile",
      "ELSIF p_client_protocol BETWEEN 1 AND 3 THEN",
      "IF p_minimum_client_protocol > 0",
      "RAISE EXCEPTION 'client_update_required'",
      "attempt.minimum_client_protocol IS DISTINCT FROM assignment.minimum_client_protocol",
      "attempt.accepted_client_protocol IS DISTINCT FROM accepted_protocol",
      "identification compatibility source drift",
    ]
  ) assertStringIncludes(sql, fragment);
  for (
    const forbidden of [
      "UPDATE internal.identification_provider_attempts",
      "UPDATE internal.entitlement_rollout_config",
      "UPDATE internal.ai_quota_policies",
      "UPDATE public.user_ai_consent_events",
      "GRANT EXECUTE",
      "CREATE OR REPLACE FUNCTION public.reserve_ai_quota",
      "openai_photo_text",
    ]
  ) assert(!sql.includes(forbidden), `Unexpected activation: ${forbidden}`);
});
