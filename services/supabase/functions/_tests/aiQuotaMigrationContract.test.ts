import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260723160229_enforce_server_ai_quotas.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("AI quota migration keeps entitlement and counters server-owned", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "ADD COLUMN IF NOT EXISTS entitlement_version BIGINT NOT NULL DEFAULT 1",
      "CREATE TRIGGER bump_user_entitlement_version",
      "REVOKE INSERT, DELETE ON TABLE public.users FROM PUBLIC, anon, authenticated",
      "REVOKE UPDATE ON TABLE public.users FROM PUBLIC, anon, authenticated",
      "REVOKE INSERT (%1$s), UPDATE (%1$s) ON TABLE public.users FROM PUBLIC, anon, authenticated",
      "GRANT UPDATE (default_geoprivacy, marketing_opt_in) ON TABLE public.users TO authenticated",
      "CREATE TABLE internal.ai_quota_policies",
      "AND model IN ('gemini-2.5-flash', 'gemini-2.5-pro')",
      "CREATE TABLE internal.ai_quota_counters",
      "CREATE TABLE internal.ai_quota_reservations",
      "CREATE TABLE internal.ai_quota_reservation_counters",
      "CREATE INDEX ai_quota_reservations_cleanup_idx ON internal.ai_quota_reservations (updated_at, id)",
      "CREATE INDEX ai_quota_counters_cleanup_idx ON internal.ai_quota_counters ( window_start, scope_type, scope_key, bucket )",
      "REVOKE ALL ON TABLE internal.ai_quota_policies, internal.ai_quota_counters, internal.ai_quota_reservations, internal.ai_quota_reservation_counters FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("AI quota reservation is atomic, idempotent, and fail-closed", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.reserve_ai_quota",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'",
      "PERFORM internal.require_service_role()",
      "RAISE EXCEPTION 'ai_entitlement_unavailable'",
      "RAISE EXCEPTION 'ai_quota_policy_missing'",
      "RAISE EXCEPTION 'ai_quota_policy_disabled'",
      "RAISE EXCEPTION 'ai_entitlement_required'",
      "WHERE users.id = p_user_id FOR SHARE",
      "PG_ADVISORY_XACT_LOCK",
      "ON CONFLICT (scope_type, scope_key, bucket, window_start) DO UPDATE",
      "WHERE internal.ai_quota_counters.request_count < p_limit",
      "UNIQUE (user_id, operation, request_id)",
      "CREATE OR REPLACE FUNCTION public.finalize_ai_quota_reservation",
      "p_final_state IS NULL",
      "CASE links.scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END",
      "request_count = GREATEST(counters.request_count - 1, 0)",
      "GRANT EXECUTE ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.finalize_ai_quota_reservation( UUID, UUID, TEXT ) TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT) TO anon",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT) TO authenticated",
    ),
  );
});

Deno.test("AI quota policy matrix covers every public paid-model operation", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  const operations = [
    "scan_identification",
    "scan_audio_identification",
    "scan_overview_enrichment",
    "scan_lookalike_enrichment",
    "explore_audio_moderation",
    "insight_chat_reply",
    "insight_chat_prompt_suggestions",
    "insight_chat_summary",
    "explore_post_chat_reply",
  ];

  for (const operation of operations) {
    for (const plan of ["free", "pro_trial", "pro_paid"]) {
      assertStringIncludes(sql, `('${operation}', '${plan}'`);
    }
  }
});
