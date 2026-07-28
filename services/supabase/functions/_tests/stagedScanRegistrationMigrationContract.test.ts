import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationUrl = new URL(
  "../../migrations/20260728231000_make_staged_scan_media_registration_idempotent.sql",
  import.meta.url,
);

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

Deno.test("staged scan registration migration preserves audit state and enforces active uniqueness", async () => {
  const rawSql = await Deno.readTextFile(migrationUrl);
  const sql = normalized(rawSql);

  for (
    const fragment of [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '5min'",
      "WITH ranked_capture_rows AS",
      "PARTITION BY assets.user_id, assets.client_scan_id, assets.storage_key",
      "pg_catalog.ROW_NUMBER() OVER",
      "pg_catalog.COUNT(*) OVER",
      "UPDATE public.scan_media_assets AS assets SET status = 'failed'",
      "failure_reason = 'superseded_staging_registration'",
      "'supersededStagingRegistration'",
      "'priorStatus', ranked.prior_status",
      "'priorFailureReason', ranked.prior_failure_reason",
      "ranked.identity_count > 1",
      "ranked.lifecycle_rank > 1",
      "CREATE UNIQUE INDEX idx_scan_media_assets_active_staging_key_unique",
      "ON public.scan_media_assets(user_id, client_scan_id, storage_key)",
      "WHERE source = 'capture_upload' AND status = 'staged'",
      "CREATE OR REPLACE FUNCTION internal.enforce_staged_scan_media_budget()",
      "pg_catalog.PG_ADVISORY_XACT_LOCK",
      "'merian-staged-scan-media-owner:' || NEW.user_id::TEXT",
      "existing_staged_count >= 6",
      "RAISE EXCEPTION 'staged_scan_media_budget_exceeded'",
      "REVOKE ALL ON FUNCTION internal.enforce_staged_scan_media_budget() FROM PUBLIC, anon, authenticated, service_role",
      "CREATE TRIGGER enforce_staged_scan_media_budget BEFORE INSERT OR UPDATE ON public.scan_media_assets",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    sql.indexOf("UPDATE public.scan_media_assets AS assets") <
      sql.indexOf(
        "CREATE UNIQUE INDEX idx_scan_media_assets_active_staging_key_unique",
      ),
    "Existing duplicates must be superseded before uniqueness is installed.",
  );
  assertEquals(
    /\bCONCURRENTLY\b/i.test(
      rawSql.replaceAll(/--[^\n]*/g, ""),
    ),
    false,
    "Transactional migrations must not use CREATE INDEX CONCURRENTLY.",
  );
});
