import { assert, assertStringIncludes } from "@std/assert";

const migration = new URL(
  "../../migrations/20260926150509_add_independent_openai_consent_stream.sql",
  import.meta.url,
);
Deno.test("OpenAI consent is independent and cannot change production assignment", async () => {
  const sql = (await Deno.readTextFile(migration)).replace(/\s+/g, " ");
  for (
    const fragment of [
      "CHECK (provider IN ('google_gemini', 'openai'))",
      "existing_provider IS DISTINCT FROM 'google_gemini'",
      "existing_provider IS DISTINCT FROM 'openai'",
      "'merian:user-ai-consent:' || caller_user_id::TEXT",
      "events.provider = 'openai' ORDER BY events.consent_revision DESC",
      "stream_head_disclosure_version = '2026-09-26'",
      "receipts.policy_version = '2026-08-03'",
      "receipts.terms_version = '2026-08-03'",
      "PERFORM internal.require_current_ai_consent(p_user_id);",
      "GRANT EXECUTE ON FUNCTION public.append_user_openai_consent_event",
      "internal.privileged_routine_grants",
    ]
  ) assertStringIncludes(sql, fragment);
  for (
    const forbidden of [
      "UPDATE public.user_ai_consent_events",
      "ai_consent_rollout_config",
      "INSERT INTO internal.identification_provider_bindings",
      "UPDATE internal.ai_quota_policies",
      "CREATE OR REPLACE FUNCTION public.reserve_ai_quota",
      "GRANT INSERT",
    ]
  ) {
    assert(
      !sql.includes(forbidden),
      `Unexpected activation/mutation: ${forbidden}`,
    );
  }
  const policy = await Deno.readTextFile(
    new URL(
      "../../../../apps/ios/Merian/Core/Security/Consent/Models/ConsentPolicy.swift",
      import.meta.url,
    ),
  );
  assertStringIncludes(policy, "openAIConsentCollectionEnabled = false");
  assertStringIncludes(policy, 'openAIProvider = "openai"');
  assertStringIncludes(policy, 'openAIDisclosureVersion = "2026-09-26"');
});

Deno.test("beta identification defers OpenAI consent without changing receipt or assignment contracts", async () => {
  const sql = (await Deno.readTextFile(
    new URL(
      "../../migrations/20260928183305_defer_openai_consent_during_beta.sql",
      import.meta.url,
    ),
  )).replace(/\s+/g, " ");
  for (
    const fragment of [
      "STABLE SECURITY INVOKER SET search_path = ''",
      "p_processor_permission NOT IN ('google_gemini', 'openai')",
      "PERFORM internal.require_current_ai_consent(p_user_id);",
      "FROM PUBLIC, anon, authenticated, service_role;",
      "SET lock_timeout = '10s';",
      "RESET lock_timeout;",
      "RESET statement_timeout;",
    ]
  ) assertStringIncludes(sql, fragment);
  for (
    const forbidden of [
      "public.user_ai_consent_events",
      "ai_openai_consent_required",
      "UPDATE internal.identification_provider_bindings",
      "UPDATE internal.ai_quota",
      "CREATE OR REPLACE FUNCTION internal.require_current_ai_consent",
      "GRANT EXECUTE",
      "SECURITY DEFINER",
    ]
  ) {
    assert(
      !sql.includes(forbidden),
      `Unexpected beta policy change: ${forbidden}`,
    );
  }
});
