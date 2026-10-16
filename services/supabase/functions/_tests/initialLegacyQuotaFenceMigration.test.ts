import { assert, assertEquals } from "@std/assert";

const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261016055839_fence_legacy_quota_initial_operation.sql",
    import.meta.url,
  ),
);

Deno.test("legacy quota repair changes only the public four-argument boundary", () => {
  assertEquals(
    [...sql.matchAll(/CREATE OR REPLACE FUNCTION\s+([\w.]+)/g)].map((m) =>
      m[1]
    ),
    ["public.reserve_ai_quota"],
  );
  assert(!/CREATE\s+(?:TABLE|TRIGGER)|ALTER TABLE|UPDATE internal\./.test(sql));
  assert(sql.includes("SET search_path = ''"));
  assert(sql.includes("SET statement_timeout = '5s'"));
  assert(sql.includes(
    "REVOKE ALL ON FUNCTION public.reserve_ai_quota(UUID,TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role",
  ));
  assert(sql.includes(
    "GRANT EXECUTE ON FUNCTION public.reserve_ai_quota(UUID,TEXT,UUID,TEXT) TO service_role",
  ));
});

Deno.test("legacy quota validates and serializes before observing the permanent fence", () => {
  const order = [
    "PERFORM internal.require_service_role()",
    "PERFORM internal.require_current_ai_consent(p_user_id)",
    "RAISE EXCEPTION 'ai_quota_invalid_request'",
    "current_setting('transaction_isolation') <> 'read committed'",
    "WHERE users.id = p_user_id FOR UPDATE",
    "pg_catalog.pg_advisory_xact_lock(",
    "'merian-scan-ingestion:' || p_request_id::TEXT",
    "FROM internal.initial_analysis_operation_fences",
    "RAISE EXCEPTION 'initial_analysis_admission_required'",
    "FROM internal.reserve_ai_quota_core(p_user_id, p_operation, p_request_id, p_ip_hash)",
  ].map((fragment) => sql.indexOf(fragment));
  assert(order.every((position) => position >= 0));
  assertEquals(order, [...order].sort((a, b) => a - b));
  assert(!sql.includes("lock_initial_preparation_scope"));
  assert(!sql.includes("EXCEPTION WHEN"));
});
