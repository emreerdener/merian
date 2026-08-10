import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260810034953_guard_empty_ghost_account_cleanup.sql",
  import.meta.url,
);
const cleanupScriptUrl = new URL(
  "../../scripts/cleanup_ghost_users.ts",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("empty Ghost cleanup is fail-closed over identity and activity evidence", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.empty_ghost_account_deletion_receipts",
      "ALTER TABLE internal.empty_ghost_account_deletion_receipts ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.empty_ghost_account_deletion_receipts FROM PUBLIC, anon, authenticated, service_role",
      "CREATE OR REPLACE FUNCTION internal.empty_ghost_cleanup_blockers",
      "PERFORM internal.assert_ghost_profile_merge_reference_policy_coverage()",
      "auth_user.is_anonymous IS NOT TRUE",
      "auth_user.last_sign_in_at > cutoff",
      "identity.provider <> 'anonymous'",
      "auth_session.updated_at > cutoff",
      "paid_projection_present",
      "subscription_expiry_present",
      "custom_public_username_present",
      "profile_activity_present",
      "field_trip_activity_present",
      "template.slug <> 'backyard_safari'",
      "policy.source_table = 'user_field_trips'",
      "policy.source_table = 'revenuecat_reconciliation_queue'",
      "policy.source_table = 'revenuecat_customer_state'",
      "reference:public.ai_usage_events.user_id",
      "account_storage_deletion_already_present",
      "account_deletion_already_active",
      "ghost_profile_merge_active",
      "CREATE OR REPLACE FUNCTION public.inspect_empty_ghost_cleanup_candidate",
      "PERFORM internal.require_service_role()",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("supabaseAdmin.auth.admin.deleteUser") &&
      !sql.includes("DELETE FROM auth.users"),
    "The database guard must never reintroduce Auth-first deletion.",
  );
});

Deno.test("empty Ghost operator script is provider-read-only and never deletes Auth directly", async () => {
  const source = normalized(await Deno.readTextFile(cleanupScriptUrl));
  for (
    const fragment of [
      "revalidateRevenueCatShell",
      "inspect_empty_ghost_cleanup_candidate",
      "reserve_ghost_user_bulk_cleanup",
      "request_empty_ghost_account_deletion",
      "candidate_sha256",
      "approvedPlanSHA256 !== result.candidate_sha256",
      "direct_auth_deletions: 0",
      "direct_public_user_deletions: 0",
    ]
  ) {
    assertStringIncludes(source, fragment);
  }
  assert(
    !source.includes("auth.admin.deleteUser") &&
      !source.includes('.from("users").delete()') &&
      !source.includes('method: "DELETE"'),
    "The coordinated Supabase intake must not delete Auth, profiles, or RevenueCat customers directly.",
  );
});

Deno.test("empty Ghost intake atomically enters durable account deletion", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.request_empty_ghost_account_deletion",
      "p_candidate_plan_sha256 !~ '^[0-9a-f]{64}$'",
      "p_revenuecat_verified_at < pg_catalog.STATEMENT_TIMESTAMP() - INTERVAL '10 minutes'",
      "p_revenuecat_checked_customer_count NOT BETWEEN 1 AND 50",
      "pg_catalog.PG_ADVISORY_XACT_LOCK",
      "'ghost-profile-merge:' || p_user_id::TEXT",
      "FOR UPDATE",
      "empty_ghost_cleanup_live_evidence_present",
      "FROM public.request_account_deletion(p_user_id)",
      "INSERT INTO internal.empty_ghost_account_deletion_receipts",
      "FROM public.claim_account_deletion_jobs(1, p_user_id)",
      "SELECT public.complete_account_deletion_cleanup",
      "cleanup_status <> 'storage_pending'",
      "SET completed_at = pg_catalog.NOW()",
      "CREATE OR REPLACE FUNCTION internal.reject_ghost_merge_during_account_deletion",
      "CREATE TRIGGER reject_ghost_merge_during_account_deletion",
      "ghost_merge_source_deletion_in_progress",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const intakeStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.request_empty_ghost_account_deletion",
  );
  const intakeEnd = sql.indexOf(
    "COMMENT ON FUNCTION public.request_empty_ghost_account_deletion",
    intakeStart,
  );
  const intake = sql.slice(intakeStart, intakeEnd);
  const liveProof = intake.indexOf(
    "live_blockers := internal.empty_ghost_cleanup_blockers",
  );
  const durableReceipt = intake.indexOf(
    "FROM public.request_account_deletion(p_user_id)",
  );
  const relationalCleanup = intake.indexOf(
    "SELECT public.complete_account_deletion_cleanup",
  );
  const reservationCompletion = intake.indexOf(
    "UPDATE internal.ghost_user_cleanup_reservations",
  );
  assert(
    liveProof >= 0 &&
      durableReceipt > liveProof &&
      relationalCleanup > durableReceipt &&
      reservationCompletion > relationalCleanup,
    "Live evidence must precede the durable receipt, relational cleanup, and reservation completion.",
  );
});

Deno.test("empty Ghost cleanup RPCs remain service-only and cataloged", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "REVOKE ALL ON FUNCTION public.inspect_empty_ghost_cleanup_candidate( UUID, INTEGER ) FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE ALL ON FUNCTION public.request_empty_ghost_account_deletion( UUID, UUID, INTEGER, TEXT, TEXT, TIMESTAMPTZ, INTEGER ) FROM PUBLIC, anon, authenticated, service_role",
      "'public.inspect_empty_ghost_cleanup_candidate(uuid,integer)'",
      "'public.request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamp with time zone,integer)'",
      "GRANT EXECUTE ON FUNCTION public.inspect_empty_ghost_cleanup_candidate( UUID, INTEGER ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.request_empty_ghost_account_deletion( UUID, UUID, INTEGER, TEXT, TEXT, TIMESTAMPTZ, INTEGER ) TO service_role",
      "empty_ghost_cleanup_rpc_acl_invalid",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !/pg_catalog\.(?:COALESCE|NULLIF|GREATEST|LEAST)\s*\(/i.test(sql),
    "PostgreSQL conditional expressions must not be schema-qualified.",
  );
});
