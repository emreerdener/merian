import { assert, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260821030027_add_species_dictionary_field_chat.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("dictionary Field Chat tables are private, bound, indexed, and cascading", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "CREATE TABLE public.species_dictionary_chat_conversations",
      "UNIQUE (species_dictionary_id, user_id)",
      "UNIQUE (id, species_dictionary_id, user_id)",
      "CREATE TABLE public.species_dictionary_chat_messages",
      "UNIQUE (id, conversation_id, species_dictionary_id, user_id)",
      "FOREIGN KEY (conversation_id, species_dictionary_id, user_id)",
      "CREATE TABLE public.species_dictionary_chat_message_feedback",
      "FOREIGN KEY ( message_id, conversation_id, species_dictionary_id, user_id )",
      "DEFERRABLE INITIALLY DEFERRED",
      "ON DELETE CASCADE",
      "CREATE UNIQUE INDEX species_dictionary_chat_messages_client_id_idx",
      "WHERE client_message_id IS NOT NULL",
      "ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL PRIVILEGES ON TABLE public.species_dictionary_chat_conversations, public.species_dictionary_chat_messages, public.species_dictionary_chat_message_feedback FROM PUBLIC, anon, authenticated, service_role",
      "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.species_dictionary_chat_conversations TO service_role",
      "GRANT SELECT, INSERT ON TABLE public.species_dictionary_chat_messages TO service_role",
      "GRANT SELECT, INSERT, UPDATE ON TABLE public.species_dictionary_chat_message_feedback TO service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  assert(
    !sql.includes(
      "GRANT SELECT, INSERT ON TABLE public.species_dictionary_chat_messages TO authenticated",
    ),
  );
});

Deno.test("dictionary sends join the atomic three-family limits and stale recovery", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "p_subject_type NOT IN ( 'insight', 'explore', 'species_dictionary' )",
      "'merian:field-chat:user:' || p_user_id::TEXT",
      "'merian:field-chat:conversation:' || p_conversation_id::TEXT",
      "FROM public.insight_chat_messages AS insight_message",
      "FROM public.explore_post_chat_messages AS explore_message",
      "FROM public.species_dictionary_chat_messages AS dictionary_message",
      "INSERT INTO public.species_dictionary_chat_messages AS chat_message",
      "'species_dictionary_chat_reply'",
      "conversation.species_dictionary_id = p_subject_id",
      "user_message.species_dictionary_id = p_subject_id",
      "assistant_message.species_dictionary_id = p_subject_id",
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
  assert(userLock >= 0 && conversationLock > userLock);
});

Deno.test("dictionary chat quota and anonymous-account merge cover every plan and row", async () => {
  const sql = normalized(await Deno.readTextFile(migrationUrl));
  for (
    const fragment of [
      "'species_dictionary_chat_reply', 'free'",
      "'species_dictionary_chat_reply', 'pro_trial'",
      "'species_dictionary_chat_reply', 'pro_complimentary'",
      "'species_dictionary_chat_reply', 'pro_paid'",
      "CREATE OR REPLACE FUNCTION internal.merge_ghost_chat_conversations",
      "FROM public.species_dictionary_chat_conversations AS ghost_conversation",
      "UPDATE public.species_dictionary_chat_message_feedback AS feedback",
      "UPDATE public.species_dictionary_chat_messages AS message",
      "'species_dictionary_chat_conversations'",
      "'species_dictionary_chat_message_feedback'",
      "'species_dictionary_chat_messages'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
