import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260723201500_secure_revenuecat_webhook_delivery.sql",
  import.meta.url,
);
const reconciliationMigrationUrl = new URL(
  "../../migrations/20260725052338_reconcile_revenuecat_subscribers.sql",
  import.meta.url,
);
const reconciliationScaleMigrationUrl = new URL(
  "../../migrations/20260726031502_scale_revenuecat_reconciliation.sql",
  import.meta.url,
);
const reconciliationSeedRepairMigrationUrl = new URL(
  "../../migrations/20260802203802_fix_revenuecat_zero_subject_reconciliation_seed.sql",
  import.meta.url,
);
const canonicalIdentityMigrationUrl = new URL(
  "../../migrations/20260809055035_canonicalize_revenuecat_app_user_ids.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("RevenueCat migration owns event idempotency and ordering", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.revenuecat_webhook_events",
      "event_id TEXT PRIMARY KEY",
      "CREATE TABLE internal.revenuecat_webhook_event_subjects",
      "UNIQUE (event_id, subject_kind)",
      "CREATE TABLE internal.revenuecat_customer_state",
      "CREATE OR REPLACE FUNCTION public.get_revenuecat_webhook_event_result",
      "CREATE OR REPLACE FUNCTION public.apply_revenuecat_customer_state",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'",
      "PERFORM internal.require_service_role()",
      "pg_catalog.JSONB_ARRAY_LENGTH(p_subjects)",
      "p_event_type <> 'TRANSFER' AND input_subject_total > 1",
      "subject_kind = ANY(seen_subject_kinds)",
      "revenuecat_user_mapping_ambiguous",
      "ORDER BY users.id FOR UPDATE",
      "ON CONFLICT (event_id) DO NOTHING",
      "p_event_timestamp_ms > watermark.last_event_timestamp_ms",
      "snapshot_time > watermark.last_authoritative_snapshot_at_ms",
      "existing_event.payload_sha256 <> p_payload_sha256",
      "subscription_tier = target_tier",
      "subscription_expires_at = target_expiry",
      "GRANT EXECUTE ON FUNCTION public.apply_revenuecat_customer_state",
      "GRANT EXECUTE ON FUNCTION public.get_revenuecat_webhook_event_result",
      "'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)'",
      "'public.get_revenuecat_webhook_event_result(text,bigint,text,text)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.apply_revenuecat_customer_state",
    ) ||
      sql.includes("TO service_role"),
    "Only service_role may execute the RevenueCat state transaction.",
  );
});

Deno.test("RevenueCat internals are not directly available to API roles", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  assertStringIncludes(
    sql,
    "ALTER TABLE internal.revenuecat_webhook_events ENABLE ROW LEVEL SECURITY",
  );
  assertStringIncludes(
    sql,
    "ALTER TABLE internal.revenuecat_webhook_event_subjects ENABLE ROW LEVEL SECURITY",
  );
  assertStringIncludes(
    sql,
    "ALTER TABLE internal.revenuecat_customer_state ENABLE ROW LEVEL SECURITY",
  );
  assertStringIncludes(
    sql,
    "REVOKE ALL ON TABLE internal.revenuecat_webhook_events FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    sql,
    "REVOKE ALL ON TABLE internal.revenuecat_webhook_event_subjects FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    sql,
    "REVOKE ALL ON TABLE internal.revenuecat_customer_state FROM PUBLIC, anon, authenticated, service_role",
  );
});

Deno.test("RevenueCat snapshots outrank event time and reconcile periodically", async () => {
  const sql = normalized(
    await Deno.readTextFile(reconciliationMigrationUrl),
  );

  for (
    const fragment of [
      "CustomerInfo is the entitlement authority",
      "OR snapshot_time > watermark.last_authoritative_snapshot_at_ms",
      "snapshot_time = watermark.last_authoritative_snapshot_at_ms AND p_event_timestamp_ms > watermark.last_event_timestamp_ms",
      "revenuecat_ordering_source_drift",
      "CREATE TABLE internal.revenuecat_reconciliation_queue",
      "CREATE OR REPLACE FUNCTION public.schedule_revenuecat_reconciliation",
      "CREATE OR REPLACE FUNCTION public.claim_revenuecat_reconciliations",
      "FOR UPDATE SKIP LOCKED",
      "CREATE OR REPLACE FUNCTION public.apply_revenuecat_reconciliation",
      "p_authoritative_snapshot_at_ms > watermark.last_authoritative_snapshot_at_ms",
      "CREATE OR REPLACE FUNCTION public.fail_revenuecat_reconciliation",
      "attempt_count = LEAST(queue.attempt_count + 1, 100)",
      "PERFORM internal.require_service_role()",
      "SET search_path = ''",
      "reconcile_revenuecat_subscribers_every_fifteen_minutes",
      "/functions/v1/reconcile-revenuecat-subscribers",
      "REVOKE ALL ON TABLE internal.revenuecat_reconciliation_queue FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !/pg_catalog\.(?:COALESCE|NULLIF|GREATEST|LEAST)\s*\(/i.test(sql),
    "PostgreSQL conditional expressions cannot be schema-qualified.",
  );
});

Deno.test("RevenueCat reconciliation drains against a deadline and exposes indexed backlog health", async () => {
  const sql = normalized(
    await Deno.readTextFile(reconciliationScaleMigrationUrl),
  );

  for (
    const fragment of [
      "CREATE INDEX revenuecat_reconciliation_claim_expiry_idx ON internal.revenuecat_reconciliation_queue ( claim_expires_at, merian_user_id ) INCLUDE (next_reconcile_at) WHERE claim_token IS NOT NULL",
      "p_limit INTEGER DEFAULT 6",
      "WHERE queue.claim_token IS NOT NULL AND queue.claim_expires_at <= pg_catalog.NOW()",
      "FOR UPDATE SKIP LOCKED",
      "CREATE OR REPLACE FUNCTION public.get_revenuecat_reconciliation_health()",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'",
      "PERFORM internal.require_service_role()",
      "queue.claim_token IS NULL AND queue.next_reconcile_at <= clock.observed_at",
      "queue.claim_token IS NOT NULL AND queue.claim_expires_at <= clock.observed_at",
      "oldest_due_age_seconds BIGINT",
      "REVOKE ALL ON FUNCTION public.get_revenuecat_reconciliation_health() FROM PUBLIC, anon, authenticated, service_role",
      "GRANT EXECUTE ON FUNCTION public.get_revenuecat_reconciliation_health() TO service_role",
      "'public.get_revenuecat_reconciliation_health()'",
      "reconcile_revenuecat_subscribers_every_fifteen_minutes",
      "timeout_milliseconds := 120000",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !/pg_catalog\.(?:COALESCE|NULLIF|GREATEST|LEAST|EXTRACT)\s*\(/i.test(
      sql,
    ),
    "PostgreSQL conditional and extraction expressions cannot be schema-qualified.",
  );
});

Deno.test("RevenueCat reconciliation seed repair is forward-only and source-guarded", async () => {
  const historicalSql = normalized(
    await Deno.readTextFile(reconciliationMigrationUrl),
  );
  const repairSource = await Deno.readTextFile(
    reconciliationSeedRepairMigrationUrl,
  );
  const repairSql = normalized(repairSource);

  assertStringIncludes(historicalSql, "'applied', 0, 0, 0");
  for (
    const fragment of [
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "pg_catalog.PG_GET_FUNCTIONDEF",
      "public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)",
      "target_occurrences <> 1",
      "revenuecat_reconciliation_seed_source_drift",
      "pg_catalog.REPLACE( function_sql, old_seed_values, new_seed_values )",
      "EXECUTE patched_sql",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(repairSql, fragment);
  }

  assertStringIncludes(repairSource, "''applied''");
  assertStringIncludes(repairSource, "''ignored''");
  assert(
    !/^\s*(?:BEGIN|START\s+TRANSACTION|COMMIT)\s*;/im.test(
      repairSource,
    ),
    "The forward repair must leave transaction ownership to the Supabase CLI.",
  );
});

Deno.test("RevenueCat identities are canonical across iOS-facing database paths", async () => {
  const source = await Deno.readTextFile(canonicalIdentityMigrationUrl);
  const sql = normalized(source);

  for (
    const fragment of [
      "SET lock_timeout = '5s'",
      "SET statement_timeout = '30s'",
      "CREATE OR REPLACE FUNCTION internal.canonical_revenuecat_app_user_id",
      "SELECT pg_catalog.UPPER(p_user_id::TEXT)",
      "REVOKE ALL ON FUNCTION internal.canonical_revenuecat_app_user_id(UUID) FROM PUBLIC, anon, authenticated, service_role",
      "internal.canonical_revenuecat_app_user_id(NEW.id)",
      "PG_GET_FUNCTIONDEF",
      "internal.merge_ghost_revenuecat_state(uuid,uuid)",
      "target_occurrences <> 1",
      "revenuecat_ghost_merge_identity_source_drift",
      "internal.canonical_revenuecat_app_user_id(p_target_user_id)",
      "UPDATE internal.revenuecat_reconciliation_queue AS queue",
      "queue.lookup_app_user_id::UUID = queue.merian_user_id",
      "claim_token = NULL",
      "claim_expires_at = NULL",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertStringIncludes(
    source,
    "Preserve RevenueCat emails, aliases, $RCAnonymousID values",
  );
  assert(
    !/^\s*(?:BEGIN|START\s+TRANSACTION|COMMIT)\s*;/im.test(source),
    "The forward identity repair must leave transaction ownership to the Supabase CLI.",
  );
});
