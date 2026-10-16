import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006114355_prepare_protected_chat_dispatch.sql",
    import.meta.url,
  ),
);
Deno.test("protected dispatch is permanent, service only and never activates rollout", () => {
  for (
    const text of [
      "ADD COLUMN dispatch_grant_id UUID",
      "ADD COLUMN dispatch_granted_at TIMESTAMPTZ",
      "OLD.dispatch_grant_id IS NOT NULL",
      "fence.dispatch_grant_id IS NULL",
      "internal.require_service_role()",
      "internal.privileged_routine_grants",
      "FROM PUBLIC,anon,authenticated,service_role",
    ]
  ) assertStringIncludes(sql, text);
  assert(!sql.includes("SET chat_execution_enabled=TRUE"));
});
Deno.test("dispatch serializes quota before fence, saved context before marker, and commit before permission", () => {
  const body = sql.split(
    "CREATE FUNCTION public.grant_protected_insight_chat_dispatch",
  )[1];
  const order = [
    "internal.lock_insight_chat_execution_subject",
    "FROM internal.ai_quota_reservations",
    "FROM internal.insight_chat_execution_fences",
    "IF fence.dispatch_grant_id IS NOT NULL",
    "SELECT chat_execution_enabled",
    "FROM public.insight_chat_messages",
    "FROM internal.insight_chat_turn_contexts",
    "internal.require_current_ai_consent",
    "SET dispatch_grant_id=",
    "public.finalize_ai_quota_reservation",
    "'status','dispatch_granted'",
  ];
  for (let n = 1; n < order.length; n++) {
    assert(body.indexOf(order[n - 1]) < body.indexOf(order[n]), order[n]);
  }
  assert(!body.includes("prepare_current_insight_chat_context"));
  assert(!body.includes("active_projection"));
});
Deno.test("quota receipt is a fixed private projection rather than raw core row", () => {
  assert(!sql.includes("pg_catalog.to_jsonb(admitted)"));
  for (
    const text of [
      "'reservation_id',admitted.reservation_id",
      "'lease_token',admitted.lease_token",
      "'lease_expires_at',admitted.lease_expires_at",
      "'model',admitted.model",
    ]
  ) assertStringIncludes(sql, text);
});
