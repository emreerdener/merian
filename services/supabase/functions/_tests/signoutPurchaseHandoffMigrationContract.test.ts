import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260812011914_add_signout_purchase_handoffs.sql",
  import.meta.url,
);

function compact(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("sign-out purchase handoff keeps proofs private and purpose-bound", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE TABLE internal.signout_purchase_handoffs",
      "secret_hash TEXT NOT NULL UNIQUE",
      "destination_verified_snapshot_at_ms BIGINT",
      "destination_verified_store_tier TEXT",
      "destination_verified_store_expires_at TIMESTAMPTZ",
      "secret_hash ~ '^[0-9a-f]{64}$'",
      "status IN ( 'prepared', 'bound', 'completed', 'superseded', 'expired' )",
      "CREATE UNIQUE INDEX signout_purchase_handoff_one_active_source_idx",
      "CREATE UNIQUE INDEX signout_purchase_handoff_one_destination_idx",
      "CREATE INDEX signout_purchase_handoff_pending_age_idx",
      "ALTER TABLE internal.signout_purchase_handoffs ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL ON TABLE internal.signout_purchase_handoffs FROM PUBLIC, anon, authenticated, service_role",
      "SET search_path = ''",
      "SET statement_timeout = '5s'",
      "SET statement_timeout = '10s'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("GRANT SELECT") && !sql.includes("GRANT INSERT") &&
      !sql.includes("GRANT UPDATE") && !sql.includes("GRANT DELETE"),
    "no API role may receive direct handoff-table privileges",
  );
});

Deno.test("sign-out purchase issue is service-authenticated and bind derives its destination", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const issueStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.issue_signout_purchase_handoff",
  );
  const cancelStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.cancel_signout_purchase_handoff",
  );
  const bindStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.bind_signout_purchase_handoff",
  );
  const completeStart = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.complete_signout_purchase_handoff",
  );
  assert(
    issueStart >= 0 && cancelStart > issueStart && bindStart > cancelStart &&
      completeStart > bindStart,
    "all handoff state transitions must be defined",
  );

  const issue = sql.slice(issueStart, cancelStart);
  for (
    const fragment of [
      "PERFORM internal.require_service_role()",
      "source_id UUID := p_source_user_id",
      "auth_user.id = source_id AND auth_user.is_anonymous IS FALSE",
      "pg_catalog.pg_advisory_xact_lock",
      "handoff.status = 'prepared'",
      "signout_handoff_already_bound",
      "INTERVAL '30 days'",
    ]
  ) {
    assertStringIncludes(issue, fragment);
  }

  const bind = sql.slice(bindStart, completeStart);
  for (
    const fragment of [
      "caller_id UUID := auth.uid()",
      "handoff_record.destination_user_id <> caller_id",
      "auth_user.is_anonymous IS TRUE",
      "WHERE auth_user.id IN (handoff_record.source_user_id, caller_id) ORDER BY auth_user.id FOR UPDATE",
      "SET destination_user_id = caller_id, status = 'bound'",
    ]
  ) {
    assertStringIncludes(bind, fragment);
  }
  assert(
    !bind.includes("p_source_user_id") &&
      !bind.includes("p_destination_user_id"),
    "bind must not accept caller-selected identities",
  );
});

Deno.test("sign-out cancellation cannot abandon a bound destination", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const start = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.cancel_signout_purchase_handoff",
  );
  const end = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.bind_signout_purchase_handoff",
    start,
  );
  const cancel = sql.slice(start, end);

  for (
    const fragment of [
      "source_id IS NULL OR source_id <> caller_id",
      "handoff_record.secret_hash <> p_secret_hash",
      "handoff_record.status = 'superseded'",
      "handoff_record.status <> 'prepared'",
      "signout_handoff_not_cancelable",
      "SET status = CASE WHEN handoff.expires_at <= pg_catalog.NOW() THEN 'expired' ELSE 'superseded' END",
    ]
  ) {
    assertStringIncludes(cancel, fragment);
  }
});

Deno.test("sign-out completion locks identities and schedules canonical reconciliation only", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const start = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.complete_signout_purchase_handoff",
  );
  const end = sql.indexOf(
    "CREATE OR REPLACE FUNCTION public.claim_revenuecat_reconciliation_for_user",
    start,
  );
  const complete = sql.slice(start, end);

  for (
    const fragment of [
      "PERFORM internal.require_service_role()",
      "handoff_record.destination_user_id <> p_destination_user_id",
      "destination_verified_snapshot_at_ms = p_destination_snapshot_at_ms",
      "destination_verified_store_tier = p_destination_store_tier",
      "destination_verified_store_expires_at = p_destination_store_expires_at",
      "WHERE users.id IN ( handoff_record.source_user_id, handoff_record.destination_user_id ) ORDER BY users.id FOR UPDATE",
      "GET DIAGNOSTICS locked_user_count = ROW_COUNT",
      "IF locked_user_count <> 2",
      "ORDER BY queue.merian_user_id FOR UPDATE",
      "internal.canonical_revenuecat_app_user_id(users.id)",
      "ON CONFLICT (merian_user_id) DO UPDATE",
      "claim_token = NULL",
      "status = 'completed'",
    ]
  ) {
    assertStringIncludes(complete, fragment);
  }
  assert(
    !complete.includes("handoff_record.expires_at"),
    "a bound proof must remain retryable after its pre-bind expiry",
  );
  for (
    const forbidden of [
      "DELETE FROM auth.users",
      "DELETE FROM public.users",
      "UPDATE public.scans",
      "perform_ghost_profile_merge",
      "grantMatchingProHorizon",
    ]
  ) {
    assert(
      !complete.includes(forbidden),
      `completion must not contain ${forbidden}`,
    );
  }
});

Deno.test("sign-out purchase grants match the reviewed role allowlist", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "GRANT EXECUTE ON FUNCTION public.issue_signout_purchase_handoff( UUID, TEXT, BIGINT, TEXT, TIMESTAMPTZ ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT) TO authenticated",
      "GRANT EXECUTE ON FUNCTION public.cancel_signout_purchase_handoff(UUID, TEXT) TO authenticated",
      "GRANT EXECUTE ON FUNCTION public.complete_signout_purchase_handoff( UUID, TEXT, UUID, BIGINT, TEXT, TIMESTAMPTZ ) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.claim_revenuecat_reconciliation_for_user(UUID) TO service_role",
      "GRANT EXECUTE ON FUNCTION public.get_revenuecat_reconciliation_health() TO service_role",
      "'public.issue_signout_purchase_handoff(uuid,text,bigint,text,timestamp with time zone)'",
      "'public.bind_signout_purchase_handoff(uuid,text)'",
      "'public.cancel_signout_purchase_handoff(uuid,text)'",
      "'public.complete_signout_purchase_handoff(uuid,text,uuid,bigint,text,timestamp with time zone)'",
      "'public.claim_revenuecat_reconciliation_for_user(uuid)'",
      "'public.get_revenuecat_reconciliation_health()'",
      "signout_prepared_count BIGINT",
      "signout_bound_count BIGINT",
      "oldest_signout_pending_age_seconds BIGINT",
      "handoff.status = 'prepared' AND handoff.expires_at > clock.observed_at",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
