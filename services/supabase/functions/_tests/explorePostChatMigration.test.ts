import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migrationUrl = new URL(
  "../../migrations/20260721141655_add_explore_post_chat.sql",
  import.meta.url,
);

Deno.test("Explore post chat migration keeps conversations private", async () => {
  const sql = (await Deno.readTextFile(migrationUrl)).replaceAll(/\s+/g, " ");

  for (const fragment of [
    "ALTER TABLE public.explore_post_chat_conversations ENABLE ROW LEVEL SECURITY",
    "ALTER TABLE public.explore_post_chat_messages ENABLE ROW LEVEL SECURITY",
    "ALTER TABLE public.explore_post_chat_message_feedback ENABLE ROW LEVEL SECURITY",
    "TO authenticated USING ((SELECT auth.uid()) = user_id)",
    "conversation.user_id = (SELECT auth.uid())",
    "message.user_id = (SELECT auth.uid())",
    "REVOKE ALL ON public.explore_post_chat_conversations FROM anon, authenticated",
    "REVOKE ALL ON public.explore_post_chat_messages FROM anon, authenticated",
    "REVOKE ALL ON public.explore_post_chat_message_feedback FROM anon, authenticated",
  ]) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("SECURITY DEFINER"),
    "Explore chat triggers must not bypass RLS.",
  );
});

Deno.test("unpublishing an Explore post removes its chats", async () => {
  const sql = (await Deno.readTextFile(migrationUrl)).replaceAll(/\s+/g, " ");
  assertStringIncludes(
    sql,
    "IF OLD.unshared_at IS NULL AND NEW.unshared_at IS NOT NULL",
  );
  assertStringIncludes(
    sql,
    "DELETE FROM public.explore_post_chat_conversations WHERE post_id = NEW.id",
  );
});
