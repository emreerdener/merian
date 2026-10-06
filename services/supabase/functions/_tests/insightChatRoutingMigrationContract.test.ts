import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006121418_fence_legacy_insight_chat_admission.sql",
    import.meta.url,
  ),
);
Deno.test("legacy chat cores are private and wrappers preserve public signatures without caller flags", () => {
  for (
    const owner of [
      "reserve_field_chat_send",
      "finalize_ai_quota_reservation",
      "recover_stale_field_chat_quota",
    ]
  ) {
    assertStringIncludes(sql, `ALTER FUNCTION public.${owner}(`);
    assertStringIncludes(sql, `RENAME TO ${owner}_core`);
    assertStringIncludes(sql, `REVOKE ALL ON FUNCTION internal.${owner}_core(`);
    assertStringIncludes(sql, `CREATE FUNCTION public.${owner}(`);
  }
  assert(!sql.includes("SET chat_execution_enabled=TRUE"));
  assert(!sql.includes("current_setting("));
});
Deno.test("routing is sticky and immutable admission has exactly two trusted core replacements", () => {
  for (
    const marker of [
      "FROM internal.observation_histories",
      "FROM internal.insight_chat_execution_fences",
      "JOIN internal.insight_chat_turn_contexts",
      "chat_execution_enabled",
      "<>2 THEN",
      "protected_chat_admission_source_drift",
      "internal.privileged_routine_grants",
    ]
  ) assertStringIncludes(sql, marker);
});
Deno.test("finalizer locks subject before private quota core and enrollment waits for exact legacy assistant", () => {
  const body =
    sql.split("CREATE FUNCTION public.finalize_ai_quota_reservation")[1].split(
      "ALTER FUNCTION public.recover_stale_field_chat_quota",
    )[0];
  assert(
    body.indexOf("internal.lock_insight_chat_execution_subject") <
      body.indexOf("RETURN internal.finalize_ai_quota_reservation_core"),
  );
  for (
    const marker of [
      "analysis_history_chat_in_progress",
      "internal.insight_chat_assistant_id(m.conversation_id,q.request_id)",
      "q.state='committed'",
      "protected_chat_enrollment_source_drift",
    ]
  ) assertStringIncludes(sql, marker);
});
