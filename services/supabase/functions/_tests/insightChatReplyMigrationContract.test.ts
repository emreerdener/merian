import { assert, assertEquals } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006131107_persist_protected_insight_chat_reply.sql",
    import.meta.url,
  ),
);
Deno.test("protected reply completion checks subject before payload and quota before fence", () => {
  const write = sql.split(
    "CREATE FUNCTION public.complete_protected_insight_chat_reply",
  )[1];
  assert(
    write.indexOf("lock_insight_chat_execution_subject") <
      write.indexOf("validate_protected_insight_chat_reply"),
  );
  assert(
    write.indexOf("FROM internal.ai_quota_reservations") <
      write.indexOf("internal.protected_insight_chat_reply_receipt"),
  );
  assert(
    write.indexOf("IF (receipt->>'completed')") <
      write.indexOf("IF quota.id IS NULL"),
  );
  for (
    const term of [
      "quota.attempt_count<>1",
      "quota.state<>'committed'",
      "quota.model IS DISTINCT FROM p_reply->>'model'",
    ]
  ) assert(write.includes(term));
  assertEquals(
    (write.match(/INSERT INTO public.insight_chat_messages/g) || []).length,
    1,
  );
  assert(!write.includes("ON CONFLICT"));
  assert(!write.includes("refund_ai"));
});
Deno.test("protected recovery compares full payload without mutation or quota authority", () => {
  const helper = sql.split(
    "CREATE FUNCTION internal.protected_insight_chat_reply_receipt",
  )[1].split("CREATE FUNCTION public.get_")[0];
  for (
    const term of [
      "fence.dispatch_grant_id IS NULL",
      "fence.lease_token IS DISTINCT FROM p_lease_token",
      "saved.llm_usage_metadata,saved.safety_metadata",
      "field_chat_reply_conflict",
    ]
  ) assert(helper.includes(term));
  assert(!helper.includes("INSERT INTO"));
  assert(!helper.includes("ai_quota_reservations"));
  const read =
    sql.split("CREATE FUNCTION public.get_protected_insight_chat_reply")[1]
      .split("CREATE FUNCTION public.complete_")[0];
  assert(
    read.indexOf("lock_insight_chat_execution_subject") <
      read.indexOf("validate_protected_insight_chat_reply"),
  );
  assert(!read.includes("INSERT INTO public.insight_chat_messages"));
  assert(!read.includes("GRANT EXECUTE ON FUNCTION internal."));
});
