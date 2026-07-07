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

Deno.test("scan media staged upload repair allows scanless pre-persistence rows", async () => {
  const sql = normalized(
    await migrationSql(
      "20260706100000_allow_staged_scan_media_without_scan_id.sql",
    ),
  );

  assertStringIncludes(
    sql,
    "ALTER TABLE IF EXISTS public.scan_media_assets ALTER COLUMN scan_id DROP NOT NULL",
  );
  assertStringIncludes(
    sql,
    "NULL is valid for staged capture_upload rows before scan persistence",
  );
});

Deno.test("scan media staged upload repair allows rows before public URLs exist", async () => {
  const sql = normalized(
    await migrationSql(
      "20260707020956_allow_staged_scan_media_without_url.sql",
    ),
  );

  assertStringIncludes(
    sql,
    "ALTER TABLE IF EXISTS public.scan_media_assets ALTER COLUMN url DROP NOT NULL",
  );
  assertStringIncludes(
    sql,
    "Required for ready display/playback and promoted capture_upload assets",
  );
  assertStringIncludes(sql, "NOTIFY pgrst, 'reload schema'");
});

Deno.test("scan media refresh ambiguity repair qualifies legacy array aliases", async () => {
  const sql = normalized(
    await migrationSql(
      "20260706193954_fix_scan_media_refresh_image_url_ambiguity.sql",
    ),
  );

  for (
    const fragment of [
      "CREATE OR REPLACE FUNCTION public.refresh_scan_media_assets(target_scan_id UUID)",
      "asset_image_url TEXT",
      "asset_video_url TEXT",
      "BTRIM(media_images.raw_image_url)",
      "WITH ORDINALITY AS media_images(raw_image_url, ordinality)",
      "BTRIM(media_videos.raw_video_url)",
      "WITH ORDINALITY AS media_videos(raw_video_url, ordinality)",
      "REVOKE ALL ON FUNCTION public.refresh_scan_media_assets(UUID) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.refresh_scan_media_assets(UUID) TO service_role",
      "video_storage_urls",
      "LIMIT 250",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assert(
    !sql.includes("BTRIM(image_url)"),
    "legacy fallback must not use ambiguous image_url identifiers",
  );
  assert(
    !sql.includes("BTRIM(video_url)"),
    "legacy fallback must not use ambiguous video_url identifiers",
  );
});

Deno.test("scan media refresh derives video audio metadata from captured media", async () => {
  const sql = normalized(
    await migrationSql(
      "20260707041259_fix_video_has_audio_metadata.sql",
    ),
  );

  for (
    const fragment of [
      "asset_audio_url TEXT",
      "asset_audio_url := public.scan_media_reference_path(media_item #> '{video,_0,audio}')",
      "asset_audio_url IS NOT NULL",
      "Video has_audio is true only when a captured_media video includes an audio reference.",
      "REVOKE ALL ON FUNCTION public.refresh_scan_media_assets(UUID) FROM PUBLIC, anon, authenticated",
      "GRANT EXECUTE ON FUNCTION public.refresh_scan_media_assets(UUID) TO service_role",
      "PERFORM public.refresh_scan_media_assets(repair_scan.id)",
      "LIMIT 500",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  assertStringIncludes(
    sql,
    "JSONB_BUILD_OBJECT('manifest_source', 'legacy_arrays')",
  );
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

Deno.test("scan_ingestion_jobs manifest migration extends claim contract", async () => {
  const sql = normalized(
    await migrationSql(
      "20260705130000_extend_scan_ingestion_jobs_media_manifest.sql",
    ),
  );

  for (
    const fragment of [
      "ADD COLUMN IF NOT EXISTS manifest_checksum TEXT",
      "CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_manifest_checksum",
      "DROP FUNCTION IF EXISTS public.claim_scan_ingestion_job",
      "p_manifest_checksum TEXT DEFAULT NULL",
      "manifest_checksum = COALESCE(EXCLUDED.manifest_checksum, public.scan_ingestion_jobs.manifest_checksum)",
      "GRANT EXECUTE ON FUNCTION public.claim_scan_ingestion_job",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("scan_ingestion_intents migration declares the replay intent contract", async () => {
  const sql = normalized(
    await migrationSql("20260705140000_add_scan_ingestion_intents.sql"),
  );

  for (
    const fragment of [
      "CREATE TABLE IF NOT EXISTS public.scan_ingestion_intents",
      "UNIQUE (user_id, scan_id)",
      "request_payload JSONB NOT NULL DEFAULT '{}'::JSONB",
      "media_counts JSONB NOT NULL DEFAULT '{}'::JSONB",
      "media_object_keys JSONB NOT NULL DEFAULT '{}'::JSONB",
      "upload_session_ids UUID[] NOT NULL DEFAULT '{}'::UUID[]",
      "manifest_checksum TEXT",
      "payload_checksum TEXT",
      "resumable BOOLEAN NOT NULL DEFAULT TRUE",
      "inline_media_redacted BOOLEAN NOT NULL DEFAULT FALSE",
      "redacted_media_counts JSONB NOT NULL DEFAULT '{}'::JSONB",
      "CREATE INDEX IF NOT EXISTS idx_scan_ingestion_intents_resumable_updated",
      "ALTER TABLE public.scan_ingestion_intents ENABLE ROW LEVEL SECURITY",
      "CREATE OR REPLACE FUNCTION public.record_scan_ingestion_intent",
      "ON CONFLICT (user_id, scan_id) DO UPDATE",
      "REVOKE ALL ON FUNCTION public.record_scan_ingestion_intent",
      "GRANT EXECUTE ON FUNCTION public.record_scan_ingestion_intent",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("scan ingestion replay migration claims resumable jobs and schedules the worker", async () => {
  const sql = normalized(
    await migrationSql("20260705150000_schedule_scan_ingestion_replay.sql"),
  );

  assertBefore(
    sql,
    "PERFORM cron.unschedule('replay_scan_ingestion_every_five_minutes')",
    "SELECT cron.schedule( 'replay_scan_ingestion_every_five_minutes'",
    "replay cron schedule must unschedule the old job before re-scheduling",
  );

  for (
    const fragment of [
      "CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_replay_claim",
      "CREATE OR REPLACE FUNCTION public.claim_replayable_scan_ingestion_jobs",
      "j.status IN ('processing', 'finalizing', 'retrying', 'failed_retryable')",
      "i.resumable = TRUE",
      "i.inline_media_redacted = FALSE",
      "FOR UPDATE OF j SKIP LOCKED",
      "status = 'retrying'",
      "stage = 'server_replay_claimed'",
      "replay_attempt_count = i.replay_attempt_count + 1",
      "REVOKE ALL ON FUNCTION public.claim_replayable_scan_ingestion_jobs",
      "GRANT EXECUTE ON FUNCTION public.claim_replayable_scan_ingestion_jobs",
      "CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog",
      "CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public",
      "edge_endpoint := project_url || '/functions/v1/replay-scan-ingestion'",
      "'Authorization', 'Bearer ' || service_role_key",
      "'leaseSeconds', 300",
      "NOTIFY pgrst, 'reload schema'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});
