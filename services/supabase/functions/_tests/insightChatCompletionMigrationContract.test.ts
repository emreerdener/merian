import { assert, assertEquals } from "@std/assert";
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006124159_prepare_insight_chat_exact_completion.sql",
    import.meta.url,
  ),
);
Deno.test("exact chat completion delegates recovery before assistant lookup and excludes private output", () => {
  assert(migration.includes("context:=public.get_insight_chat_turn_context("));
  assert(
    migration.includes(
      "id=internal.insight_chat_assistant_id(p_conversation_id,p_request_id) FOR SHARE",
    ),
  );
  const projection =
    migration.split("response:=pg_catalog.jsonb_build_object")[1].split(
      "IF pg_catalog.octet_length",
    )[0];
  for (
    const privateKey of [
      "context_snapshot",
      "safety_metadata",
      "lease_token",
      "llm_prompt_tokens",
    ]
  ) assert(!projection.includes("'" + privateKey + "'"));
  assert(migration.includes("'field_chat_completion_held'"));
});
Deno.test("atomic local refusal locks before recovery and never creates quota", () => {
  const refusal = migration.split(
    "CREATE FUNCTION public.admit_insight_chat_local_refusal",
  )[1];
  assert(
    refusal.indexOf("internal.lock_insight_chat_execution_subject") <
      refusal.indexOf("public.get_insight_chat_turn_context"),
  );
  assert(
    refusal.indexOf("IF (context->>'found')::BOOLEAN") <
      refusal.indexOf("chat_execution_enabled"),
  );
  assert(
    refusal.includes(
      "FROM public.insight_chat_messages WHERE user_id=p_user_id AND role='user' AND client_message_id=p_client_message_id",
    ),
  );
  assert(
    refusal.includes(
      "FROM internal.insight_chat_execution_fences f JOIN public.scans s",
    ),
  );
  for (
    const forbidden of [
      "reserve_protected_insight_chat_quota",
      "finalize_ai_quota",
      "grant_protected_insight_chat_dispatch",
      "ON CONFLICT",
      "UPDATE internal.observation_history_rollout",
    ]
  ) assert(!refusal.includes(forbidden));
  assert(
    refusal.indexOf("public.reserve_insight_chat_send_with_context") <
      refusal.indexOf("INSERT INTO public.insight_chat_messages"),
  );
});
Deno.test("completion helpers are ungranted and both public routines service guarded", () => {
  assertEquals(
    (migration.match(/PERFORM internal.require_service_role\(\)/g) ?? [])
      .length,
    2,
  );
  assertEquals(
    (migration.match(/GRANT EXECUTE ON FUNCTION public\./g) ?? []).length,
    2,
  );
  assert(!migration.includes("TO authenticated"));
  assert(!migration.includes("TO anon"));
  assert(
    migration.includes(
      "REVOKE ALL ON FUNCTION internal.insight_chat_refusal_text(TEXT) FROM PUBLIC,anon,authenticated,service_role",
    ),
  );
});
