import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migrationsDir = new URL("../../migrations/", import.meta.url);

async function migrationSql(fileName: string): Promise<string> {
  return await Deno.readTextFile(new URL(fileName, migrationsDir));
}

function normalized(sql: string): string {
  return sql.replaceAll(/\s+/g, " ").trim();
}

function assertBefore(
  sql: string,
  earlier: string,
  later: string,
  message: string,
) {
  const earlierIndex = sql.indexOf(earlier);
  const laterIndex = sql.indexOf(later);
  assert(
    earlierIndex >= 0,
    `Missing expected earlier SQL fragment: ${earlier}`,
  );
  assert(laterIndex >= 0, `Missing expected later SQL fragment: ${later}`);
  assert(
    earlierIndex < laterIndex,
    `${message}: expected "${earlier}" before "${later}"`,
  );
}

Deno.test("scan_media_assets migration declares the durable media lifecycle contract", async () => {
  const sql = normalized(
    await migrationSql("20260705100000_add_scan_media_assets.sql"),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.scan_media_assets",
      "client_scan_id UUID",
      "upload_session_id UUID",
      "kind TEXT NOT NULL CHECK (kind IN ('image', 'video', 'audio'))",
      "role TEXT NOT NULL DEFAULT 'display' CHECK ( role IN ('display', 'playback', 'thumbnail', 'inference_frame', 'audio') )",
      "status TEXT NOT NULL DEFAULT 'ready' CHECK ( status IN ('staged', 'promoted', 'processing', 'ready', 'failed', 'deleted') )",
      "source TEXT NOT NULL DEFAULT 'scan_refresh' CHECK ( source IN ('scan_refresh', 'capture_upload', 'repair', 'backfill', 'manual') )",
      "storage_key TEXT",
      "thumbnail_url TEXT",
      "metadata JSONB NOT NULL DEFAULT '{}'::JSONB",
      "CONSTRAINT scan_media_assets_upload_session CHECK",
      "CONSTRAINT scan_media_assets_capture_upload_identity CHECK",
      "CREATE INDEX IF NOT EXISTS idx_scan_media_assets_client_scan",
      "CREATE INDEX IF NOT EXISTS idx_scan_media_assets_upload_session",
      "CREATE INDEX IF NOT EXISTS idx_scan_media_assets_scan_ready_order",
      "CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets",
      "CREATE TRIGGER trg_refresh_scan_media_assets",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("scan media reconciliation migration repairs older asset-table shapes before indexing source", async () => {
  const sql = normalized(
    await migrationSql(
      "20260705110000_schedule_scan_media_asset_reconciliation.sql",
    ),
  );

  const repairStart = "ALTER TABLE public.scan_media_assets";
  const sourceBackfill = "UPDATE public.scan_media_assets SET source = CASE";
  const sourceNotNull =
    "ALTER TABLE public.scan_media_assets ALTER COLUMN source SET DEFAULT 'scan_refresh', ALTER COLUMN source SET NOT NULL";
  const sourceConstraint =
    "ADD CONSTRAINT scan_media_assets_source_check CHECK";
  const stagedIndex =
    "CREATE INDEX IF NOT EXISTS idx_scan_media_assets_staged_capture_upload_age";

  assertBefore(
    sql,
    repairStart,
    sourceBackfill,
    "older table repair must add columns before backfilling source",
  );
  assertBefore(
    sql,
    sourceBackfill,
    sourceNotNull,
    "source must be backfilled before it is made non-null",
  );
  assertBefore(
    sql,
    sourceNotNull,
    sourceConstraint,
    "source default/not-null should be restored before its check constraint",
  );
  assertBefore(
    sql,
    sourceConstraint,
    stagedIndex,
    "source must exist and be constrained before the partial index references it",
  );

  for (
    const fragment of [
      "ADD COLUMN IF NOT EXISTS client_scan_id UUID",
      "ADD COLUMN IF NOT EXISTS upload_session_id UUID",
      "ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'image'",
      "ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'display'",
      "ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'ready'",
      "ADD COLUMN IF NOT EXISTS source TEXT",
      "ADD COLUMN IF NOT EXISTS url TEXT",
      "ADD COLUMN IF NOT EXISTS storage_key TEXT",
      "ADD COLUMN IF NOT EXISTS thumbnail_url TEXT",
      "ADD COLUMN IF NOT EXISTS order_index INTEGER NOT NULL DEFAULT 0",
      "ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::JSONB",
      "WHEN status = 'staged' THEN 'capture_upload'",
      "WHERE source = 'capture_upload' AND status = 'staged'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("scan media reconciliation migration keeps the scheduled worker idempotent and service-role-only", async () => {
  const sql = normalized(
    await migrationSql(
      "20260705110000_schedule_scan_media_asset_reconciliation.sql",
    ),
  );

  assertBefore(
    sql,
    "PERFORM cron.unschedule('reconcile_scan_media_assets_hourly')",
    "SELECT cron.schedule( 'reconcile_scan_media_assets_hourly'",
    "cron schedule must unschedule the old job before re-scheduling",
  );

  for (
    const fragment of [
      "CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog",
      "CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public",
      "edge_endpoint := project_url || '/functions/v1/reconcile-scan-media-assets'",
      "'Authorization', 'Bearer ' || service_role_key",
      "'repairAfterMinutes', 15",
      "'abandonAfterHours', 36",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("scan_ingestion_jobs migration declares the status ledger used by client recovery", async () => {
  const sql = normalized(
    await migrationSql("20260705120000_add_scan_ingestion_jobs.sql"),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.scan_ingestion_jobs",
      "UNIQUE (user_id, scan_id)",
      "status TEXT NOT NULL DEFAULT 'processing' CHECK",
      "'processing'",
      "'finalizing'",
      "'retrying'",
      "'failed_retryable'",
      "'failed_terminal'",
      "'complete'",
      "media_counts JSONB NOT NULL DEFAULT '{}'::JSONB",
      "media_object_keys JSONB NOT NULL DEFAULT '{}'::JSONB",
      "upload_session_ids UUID[] NOT NULL DEFAULT '{}'::UUID[]",
      "CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_scan_user",
      "CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_status_updated",
      "CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_retryable",
      "ALTER TABLE public.scan_ingestion_jobs ENABLE ROW LEVEL SECURITY",
      'CREATE POLICY "Users can read their own scan ingestion jobs"',
      "CREATE OR REPLACE FUNCTION public.claim_scan_ingestion_job",
      "ON CONFLICT (user_id, scan_id) DO UPDATE",
      "GRANT EXECUTE ON FUNCTION public.claim_scan_ingestion_job",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
