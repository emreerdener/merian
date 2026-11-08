import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006111319_prepare_protected_chat_quota_fence.sql",
    import.meta.url,
  ),
);
Deno.test("protected chat fence is scan-owned, private and independent of quota retention", () => {
  const table =
    sql.split("CREATE TABLE internal.insight_chat_execution_fences")[1].split(
      "CREATE FUNCTION",
    )[0];
  for (
    const marker of [
      "PRIMARY KEY (scan_id,client_message_id)",
      "REFERENCES public.scans(id) ON DELETE CASCADE",
      "ON DELETE SET NULL",
      "message_bound BOOLEAN NOT NULL DEFAULT FALSE",
      "ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL",
    ]
  ) assertStringIncludes(table, marker);
  assert(!table.includes("REFERENCES internal.ai_quota_reservations"));
  assert(!table.includes("user_id"));
  assertStringIncludes(
    sql,
    "chat_execution_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  assert(!sql.includes("SET chat_execution_enabled=TRUE"));
});
Deno.test("protected replay never reaches fresh quota core or transparent successor", () => {
  const body =
    sql.split("CREATE FUNCTION public.reserve_protected_insight_chat_quota")[1]
      .split(
        "CREATE FUNCTION public.reserve_protected_insight_chat_send_with_context",
      )[0];
  assert(
    body.indexOf("'status','held'") <
      body.indexOf("SELECT chat_execution_enabled"),
  );
  assert(
    body.indexOf("INSERT INTO internal.insight_chat_execution_fences") <
      body.indexOf("internal.reserve_ai_quota_core"),
  );
  assert(!body.includes("recover_stale_field_chat_quota"));
  for (
    const marker of [
      "NEW.lease_token IS DISTINCT FROM fence.lease_token",
      "NEW.attempt_count<>1",
      "TG_OP='INSERT' OR NEW.id IS DISTINCT FROM fence.reservation_id",
      "OLD.state<>'reserved'",
    ]
  ) assertStringIncludes(sql, marker);
});
Deno.test("protected binding requires original quota and preserves recovery before fresh gates", () => {
  const body = sql.split(
    "CREATE FUNCTION public.reserve_protected_insight_chat_send_with_context",
  )[1];
  assert(
    body.indexOf("FROM internal.ai_quota_reservations") <
      body.indexOf("FROM internal.insight_chat_execution_fences"),
  );
  assert(
    body.indexOf("IF fence.message_bound") <
      body.indexOf("SELECT chat_execution_enabled"),
  );
  for (
    const marker of [
      "fence.request_sha256<>fingerprint",
      "quota.state<>'reserved'",
      "message_bound=TRUE",
      "internal.privileged_routine_grants",
    ]
  ) assertStringIncludes(body, marker);
});
