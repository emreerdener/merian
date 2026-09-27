import { assert, assertStringIncludes } from "@std/assert";

Deno.test("recipient preflight is caller-bound and cannot activate, select or authorize a provider", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260926213316_add_identification_recipient_preflight.sql",
      import.meta.url,
    ),
  )).replace(/\s+/g, " ");
  for (
    const fragment of [
      "caller_id UUID := (SELECT auth.uid())",
      "SECURITY DEFINER SET search_path = ''",
      "reservation.user_id = caller_id",
      "usage.user_id = caller_id AND usage.client_scan_id = p_original_analysis_id",
      "'recovery_only'::TEXT, NULL::TEXT, NULL::INTEGER",
      "FROM PUBLIC, anon, authenticated, service_role",
      "get_my_identification_preflight(TEXT, TEXT, BOOLEAN, UUID, INTEGER) TO authenticated",
      "p_expected_processor_permission IS DISTINCT FROM assignment.processor_permission",
      "ai_identification_preflight_changed",
      "identification preflight source drift",
      "public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text)",
    ]
  ) assertStringIncludes(sql, fragment);
  const preview = sql.split("$function$;")[0];
  assert(
    !/\b(INSERT|UPDATE|DELETE|reserve_ai_quota|reserve_identification_quota)\b/
      .test(preview),
  );
  for (
    const forbidden of [
      "UPDATE internal.identification_provider_bindings",
      "UPDATE internal.ai_quota_policies",
      "UPDATE internal.entitlement_rollout_config",
      "UPDATE public.user_ai_consent_events",
      "DROP CONSTRAINT",
      "openai_photo_text_v1",
    ]
  ) assert(!sql.includes(forbidden), `Unexpected activation: ${forbidden}`);
});
