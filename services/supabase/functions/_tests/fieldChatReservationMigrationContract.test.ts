import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260729163616_reserve_field_chat_sends_atomically.sql",
  import.meta.url,
);
const bindingMigrationUrl = new URL(
  "../../migrations/20260730180000_bind_field_chat_rows_to_subjects.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("Field Chat admission migration serializes exact user and conversation resources", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "CREATE OR REPLACE FUNCTION public.reserve_field_chat_send",
      "SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s'",
      "PERFORM internal.require_service_role()",
      "p_subject_type NOT IN ('insight', 'explore')",
      "max_user_message_chars CONSTANT INTEGER := 600",
      "max_messages_per_conversation CONSTANT INTEGER := 30",
      "daily_send_limit CONSTANT INTEGER := 20",
      "'merian:field-chat:user:' || p_user_id::TEXT",
      "'merian:field-chat:conversation:' || p_conversation_id::TEXT",
      "FROM public.insight_chat_conversations AS conversation",
      "FROM public.explore_post_chat_conversations AS conversation",
      "FOR UPDATE",
      "FROM public.insight_chat_messages AS insight_message",
      "FROM public.explore_post_chat_messages AS explore_message",
      "pg_catalog.DATE_TRUNC('day', reservation_now, 'UTC')",
      "IF existing_message IS NOT NULL THEN",
      "RAISE EXCEPTION 'field_chat_idempotency_conflict'",
      "RAISE EXCEPTION 'field_chat_send_in_progress'",
      "message_count + 2 > max_messages_per_conversation",
      "RAISE EXCEPTION 'field_chat_conversation_limit_reached'",
      "daily_count >= daily_send_limit",
      "RAISE EXCEPTION 'field_chat_daily_limit_reached'",
      "INSERT INTO public.insight_chat_messages AS chat_message",
      "INSERT INTO public.explore_post_chat_messages AS chat_message",
      "SELECT inserted_message, FALSE, daily_count + 1",
      "GRANT EXECUTE ON FUNCTION public.reserve_field_chat_send( UUID, UUID, TEXT, UUID, TEXT, UUID ) TO service_role",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const userLock = sql.indexOf(
    "'merian:field-chat:user:' || p_user_id::TEXT",
  );
  const conversationLock = sql.indexOf(
    "'merian:field-chat:conversation:' || p_conversation_id::TEXT",
  );
  assert(
    userLock >= 0 && conversationLock > userLock,
    "Field Chat admissions must acquire the user lock before the conversation lock.",
  );
});

Deno.test("Field Chat admission migration closes direct-client bypasses", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "REVOKE ALL ON FUNCTION public.reserve_field_chat_send( UUID, UUID, TEXT, UUID, TEXT, UUID ) FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE ALL PRIVILEGES ON TABLE public.insight_chat_conversations, public.insight_chat_messages FROM PUBLIC, anon, authenticated, service_role",
      "REVOKE ALL PRIVILEGES ON TABLE public.explore_post_chat_conversations, public.explore_post_chat_messages FROM PUBLIC, anon, authenticated, service_role",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.insight_chat_conversations, public.explore_post_chat_conversations TO service_role",
      "GRANT SELECT, INSERT ON TABLE public.insight_chat_messages, public.explore_post_chat_messages TO service_role",
      "'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.reserve_field_chat_send( UUID, UUID, TEXT, UUID, TEXT, UUID ) TO authenticated",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.reserve_field_chat_send( UUID, UUID, TEXT, UUID, TEXT, UUID ) TO anon",
    ),
  );
});

Deno.test("Field Chat quota rescue is stale, exact-row-bound, and service-only", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.recover_stale_field_chat_quota",
      "p_operation NOT IN ( 'insight_chat_reply', 'explore_post_chat_reply' )",
      "p_user_id::TEXT || ':' || p_operation || ':' || p_request_id::TEXT",
      "FROM internal.ai_quota_reservations AS reservations",
      "reservation_row.state <> 'committed'",
      "stale_after CONSTANT INTERVAL := INTERVAL '10 minutes'",
      "conversation.scan_id = p_subject_id",
      "user_message.client_message_id = p_request_id",
      "assistant_message.safety_metadata ->> 'request_id'",
      "conversation.post_id = p_subject_id",
      "IF NOT exact_user_message_exists OR exact_assistant_message_exists THEN RETURN FALSE",
      "state = 'failed'",
      "reservations.committed_at <= recovery_now - stale_after",
      "GRANT EXECUTE ON FUNCTION public.recover_stale_field_chat_quota( UUID, TEXT, UUID, UUID, UUID ) TO service_role",
      "'public.recover_stale_field_chat_quota(uuid,text,uuid,uuid,uuid)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.recover_stale_field_chat_quota( UUID, TEXT, UUID, UUID, UUID ) TO authenticated",
    ),
  );
  assert(
    !sql.includes(
      "GRANT EXECUTE ON FUNCTION public.recover_stale_field_chat_quota( UUID, TEXT, UUID, UUID, UUID ) TO anon",
    ),
  );
});

Deno.test("both Field Chat routes use atomic admission and stale quota rescue", async () => {
  const shared = await Deno.readTextFile(
    new URL("../_shared/fieldChatReservation.ts", import.meta.url),
  );
  assertStringIncludes(shared, 'rpc("reserve_field_chat_send"');
  assertStringIncludes(shared, 'rpc("recover_stale_field_chat_quota"');
  assertStringIncludes(shared, "isBoundUserMessage(");

  for (
    const path of [
      "../insight-chat/db.ts",
      "../explore-post-chat/db.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, "reserveFieldChatSend<");
  }

  for (
    const path of [
      "../insight-chat/index.ts",
      "../explore-post-chat/index.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, "recoverStaleFieldChatQuota(");
    assertStringIncludes(source, "admission.sendsToday");
    assertStringIncludes(source, "admission.isReplay");
  }
});

Deno.test("Field Chat binding migration removes untrusted drift before structural validation", async () => {
  const sql = normalized(await Deno.readTextFile(bindingMigrationUrl));

  for (
    const fragment of [
      "DELETE FROM public.insight_chat_conversations AS conversation WHERE NOT EXISTS",
      "scan.id = conversation.scan_id AND scan.user_id = conversation.user_id",
      "DELETE FROM public.insight_chat_messages AS message WHERE NOT EXISTS",
      "conversation.id = message.conversation_id AND conversation.scan_id = message.scan_id AND conversation.user_id = message.user_id",
      "DELETE FROM public.explore_post_chat_messages AS message WHERE NOT EXISTS",
      "conversation.post_id = message.post_id",
      "DELETE FROM public.insight_chat_message_feedback AS feedback WHERE NOT EXISTS",
      "DELETE FROM public.explore_post_chat_message_feedback AS feedback WHERE NOT EXISTS",
      "message.role = 'assistant'",
      "DELETE FROM public.insight_chat_feature_feedback AS feedback WHERE NOT EXISTS",
      "scan.id = feedback.scan_id AND scan.user_id = feedback.user_id",
      "UPDATE public.insight_chat_feature_feedback AS feedback SET conversation_id = NULL",
      "ADD CONSTRAINT scans_bound_owner_identity_key UNIQUE (id, user_id)",
      "ADD CONSTRAINT insight_chat_conversations_bound_scan_owner_fk FOREIGN KEY (scan_id, user_id)",
      "ADD CONSTRAINT insight_chat_feature_feedback_bound_scan_owner_fk FOREIGN KEY (scan_id, user_id)",
      "REFERENCES public.scans (id, user_id)",
      "ADD CONSTRAINT insight_chat_messages_bound_conversation_fk FOREIGN KEY (conversation_id, scan_id, user_id)",
      "ADD CONSTRAINT explore_post_chat_messages_bound_conversation_fk FOREIGN KEY (conversation_id, post_id, user_id)",
      "ADD CONSTRAINT insight_chat_message_feedback_bound_message_fk FOREIGN KEY (message_id, conversation_id, scan_id, user_id)",
      "ADD CONSTRAINT explore_post_chat_message_feedback_bound_message_fk FOREIGN KEY (message_id, conversation_id, post_id, user_id)",
      "ADD CONSTRAINT insight_chat_feature_feedback_bound_conversation_fk FOREIGN KEY (conversation_id, scan_id, user_id)",
      "DEFERRABLE INITIALLY DEFERRED",
      "NOTIFY pgrst, 'reload schema'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  const firstCleanup = sql.indexOf(
    "DELETE FROM public.insight_chat_conversations AS conversation",
  );
  const firstConstraint = sql.indexOf(
    "ADD CONSTRAINT insight_chat_conversations_bound_identity_key",
  );
  assert(
    firstCleanup >= 0 && firstConstraint > firstCleanup,
    "Untrusted historical bindings must be removed before constraints validate.",
  );
});

Deno.test("Field Chat binding migration closes feedback Data API writes with exact RLS defense", async () => {
  const sql = normalized(await Deno.readTextFile(bindingMigrationUrl));

  for (
    const fragment of [
      "REVOKE ALL PRIVILEGES ON TABLE public.insight_chat_message_feedback, public.insight_chat_feature_feedback, public.explore_post_chat_message_feedback FROM PUBLIC, anon, authenticated, service_role",
      "GRANT SELECT, INSERT, UPDATE ON TABLE public.insight_chat_message_feedback, public.explore_post_chat_message_feedback TO service_role",
      "GRANT SELECT, INSERT ON TABLE public.insight_chat_feature_feedback TO service_role",
      'CREATE POLICY "Users can insert their own insight chat conversations"',
      "scan.id = insight_chat_conversations.scan_id",
      'CREATE POLICY "Users can insert their own insight chat messages"',
      "conversation.id = insight_chat_messages.conversation_id",
      'CREATE POLICY "Users access exact insight chat feedback"',
      "message.id = insight_chat_message_feedback.message_id",
      'CREATE POLICY "Users access exact insight chat feature feedback"',
      "conversation.id = insight_chat_feature_feedback.conversation_id",
      'CREATE POLICY "Viewers manage their Explore chat feedback"',
      "message.id = explore_post_chat_message_feedback.message_id",
      "message.role = 'assistant'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes(
      "GRANT SELECT, INSERT, UPDATE ON TABLE public.insight_chat_message_feedback, public.explore_post_chat_message_feedback TO authenticated",
    ),
  );
  assert(
    !sql.includes(
      "GRANT SELECT, INSERT ON TABLE public.insight_chat_feature_feedback TO authenticated",
    ),
  );
});
