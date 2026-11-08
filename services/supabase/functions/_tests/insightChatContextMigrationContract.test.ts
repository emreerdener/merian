import { assert, assertStringIncludes } from "@std/assert";
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261006084439_prepare_immutable_insight_chat_context.sql",
    import.meta.url,
  ),
);
Deno.test("immutable Insight context stays dormant and follows message ownership", () => {
  assertStringIncludes(
    migration,
    "chat_context_enabled BOOLEAN NOT NULL DEFAULT FALSE",
  );
  const table =
    migration.split("CREATE TABLE internal.insight_chat_turn_contexts")[1]
      .split("ALTER TABLE")[0];
  assertStringIncludes(
    table,
    "REFERENCES public.insight_chat_messages(id) ON DELETE CASCADE",
  );
  for (const duplicate of ["user_id", "scan_id", "conversation_id"]) {
    assert(!table.includes(duplicate));
  }
  assertStringIncludes(migration, "ENABLE ROW LEVEL SECURITY");
  assertStringIncludes(
    migration,
    "reject_insight_chat_context_update BEFORE UPDATE",
  );
  assert(!migration.includes("UPDATE internal.observation_history_rollout"));
});
Deno.test("immutable Insight admission replays before mutable selection and gates", () => {
  const body = migration.split(
    "CREATE FUNCTION public.reserve_insight_chat_send_with_context",
  )[1];
  let at = -1;
  for (
    const marker of [
      "internal.require_service_role()",
      "FROM public.users",
      "merian:field-chat:user:",
      "merian-scan-ingestion:",
      "internal.scan_deletion_tombstones",
      "IF existing_id IS NOT NULL",
      "saved.context_snapshot",
      "SELECT chat_context_enabled",
      "SELECT * INTO history",
      "p_displayed_ticket IS DISTINCT FROM expected_ticket",
      "INSERT INTO internal.insight_chat_turn_contexts",
    ]
  ) {
    const next = body.indexOf(marker);
    assert(next > at, marker);
    at = next;
  }
  assertStringIncludes(body, "field_chat_context_missing");
  assertStringIncludes(body, "LIMIT 12");
  assertStringIncludes(
    body,
    "pg_catalog.left(pg_catalog.btrim(m.message_text),900)",
  );
});
Deno.test("Insight snapshot uses explicit bounded projections and no raw library notes", () => {
  assertStringIncludes(
    migration,
    "pg_catalog.octet_length(context_snapshot::TEXT) <= 131072",
  );
  assertStringIncludes(
    migration,
    "internal.insight_chat_context_projection(source)",
  );
  assertStringIncludes(
    migration,
    "evidence.result_snapshot||authority.review_snapshot",
  );
  assert(!migration.includes("scan_library_details"));
  assert(!migration.includes("'field_notes'"));
  assert(!migration.includes("'image_storage_urls'"));
});
