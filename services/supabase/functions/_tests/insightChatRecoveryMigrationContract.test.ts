import { assert, assertStringIncludes } from "@std/assert";
const sql = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006091111_prepare_insight_chat_context_recovery.sql",
    import.meta.url,
  ),
);
Deno.test("Insight context resolver preserves owner-first recovery and explicit absence", () => {
  const body = sql.split("CREATE FUNCTION")[1].split("REVOKE ALL")[0];
  let position = -1;
  for (
    const marker of [
      "internal.require_service_role()",
      "FROM public.users",
      "merian:field-chat:user:",
      "merian:field-chat:subject:",
      "merian-scan-ingestion:",
      "internal.scan_deletion_tombstones",
      "SELECT m.* INTO original",
      "'found',FALSE",
      "original.message_text IS DISTINCT FROM normalized_text",
      "SELECT * INTO saved",
      "field_chat_context_missing",
      "saved.displayed_ticket IS DISTINCT FROM p_displayed_ticket",
      "saved.context_snapshot",
    ]
  ) {
    const next = body.indexOf(marker);
    assert(next > position, marker);
    position = next;
  }
  for (
    const forbidden of [
      "reserve_field_chat_send",
      "reserve_insight_chat_send",
      "observation_histories",
      "observation_history_rollout",
      "species_dictionary",
      "INSERT INTO",
      "UPDATE ",
      "DELETE FROM",
      "quota",
    ]
  ) assert(!body.includes(forbidden), forbidden);
  assertStringIncludes(body, "FOR SHARE OF c,m");
  assertStringIncludes(sql, "TO service_role");
});
