import { assert, assertStringIncludes } from "@std/assert";

Deno.test("library transition migration fences retirement and every supported source admission", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261003074542_protect_guest_library_transition_boundary.sql",
      import.meta.url,
    ),
  );
  for (
    const name of [
      "begin_scan_ingestion",
      "claim_scan_ingestion_job",
      "record_scan_ingestion_intent",
      "recover_missing_owned_scan",
      "recover_inline_scan_ingestion_completion",
      "recover_stranded_scan_ingestion_attempt",
    ]
  ) {
    assertStringIncludes(sql, `public.${name}(`);
  }
  assertStringIncludes(sql, "WHERE id = p_user_id FOR UPDATE");
  assertStringIncludes(sql, "IF NOT FOUND THEN");
  assertStringIncludes(sql, "scan_ingestion_owner_unavailable");
  assertStringIncludes(sql, "intent.resumable");
  assertStringIncludes(sql, "ghost_merge_source_history_requires_attention");
  assert(
    !sql.includes("GRANT "),
    "Admission changes must preserve the reviewed RPC ACLs",
  );
});

Deno.test("private library receipts preserve owner checks, bounds, and tombstone refusal", async () => {
  const sql = await Deno.readTextFile(
    new URL(
      "../../migrations/20261003080444_persist_private_library_details.sql",
      import.meta.url,
    ),
  );
  for (
    const fragment of [
      "REFERENCES public.scans(id) ON DELETE CASCADE",
      "ENABLE ROW LEVEL SECURITY",
      "auth.uid()",
      "NOT is_tombstoned",
      "internal.scan_deletion_tombstones",
      "receipt.payload_hash <> payload_hash",
      "library_operation_conflict",
      "pg_catalog.cardinality(p_scan_ids) > 100",
      "pg_catalog.char_length(p_field_notes) > 10000",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
  const ownerCheck = sql.indexOf("AND user_id = caller AND NOT is_tombstoned");
  const receiptRead = sql.indexOf("SELECT * INTO receipt");
  assert(
    ownerCheck > 0 && receiptRead > ownerCheck,
    "Even an acknowledged operation requires current live ownership",
  );
});
