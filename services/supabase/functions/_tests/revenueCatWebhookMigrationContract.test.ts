import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260723201500_secure_revenuecat_webhook_delivery.sql",
  import.meta.url,
);
const reconciliationMigrationUrl = new URL(
  "../../migrations/20260725052338_reconcile_revenuecat_subscribers.sql",
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
