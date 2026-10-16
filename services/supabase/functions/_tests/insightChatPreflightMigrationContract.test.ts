import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006094103_prepare_insight_chat_context_preflight.sql",
    import.meta.url,
  ),
);
Deno.test("fresh context helper is private, read-only and contains no conversation or quota work", () => {
  const helper = sql.split(
    "CREATE FUNCTION internal.prepare_current_insight_chat_context",
  )[1].split("CREATE FUNCTION public.prepare_insight_chat_send_context")[0];
  for (
    const forbidden of [
      "insight_chat_messages",
      "insight_chat_conversations",
      "reserve_field_chat_send",
      "conversation_prefix",
      "INSERT INTO",
      "DELETE FROM",
      "UPDATE internal.",
      "UPDATE public.",
      "quota",
    ]
  ) assert(!helper.includes(forbidden), forbidden);
  assertStringIncludes(helper, "SECURITY INVOKER");
  assertStringIncludes(
    helper,
    "FROM PUBLIC, anon, authenticated, service_role",
  );
  assertStringIncludes(
    helper,
    "effective IS DISTINCT FROM history.active_projection",
  );
  assertStringIncludes(
    helper,
    "evidence.result_snapshot||authority.review_snapshot",
  );
  assert(!sql.includes("SET chat_context_enabled=TRUE"));
});
Deno.test("final admission replays first and shares fresh derivation before atomically freezing prefix", () => {
  const body = sql.split(
    "CREATE OR REPLACE FUNCTION public.reserve_insight_chat_send_with_context",
  )[1];
  let position = -1;
  for (
    const marker of [
      "COALESCE(p_displayed_ticket,'null'::JSONB)",
      "FROM public.users",
      "SELECT m.id INTO existing_id",
      "IF existing_id IS NOT NULL",
      "saved.context_snapshot",
      "prepared:=internal.prepare_current_insight_chat_context",
      "-- Existing admission owns",
      "SELECT * INTO admitted FROM public.reserve_field_chat_send",
      "INTO prefix",
      "snapshot:=prepared||",
      "pg_catalog.octet_length(snapshot::TEXT)>131072",
      "INSERT INTO internal.insight_chat_turn_contexts",
    ]
  ) {
    const next = body.indexOf(marker, position + 1);
    assert(next > position, marker);
    position = next;
  }
  assert(!body.includes("SELECT * INTO authority"));
  assert(!body.includes("SELECT * INTO evidence"));
});
