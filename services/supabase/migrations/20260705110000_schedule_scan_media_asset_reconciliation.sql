-- Schedule server-side reconciliation for staged scan media upload sessions.
--
-- This worker closes the durability loop between R2 staging objects,
-- scan_media_assets lifecycle rows, and scans.captured_media/video_storage_urls.

CREATE TABLE IF NOT EXISTS public.scan_media_reconciliation_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at TIMESTAMPTZ,
    status TEXT NOT NULL CHECK (
        status IN ('success', 'partial_failure', 'failed', 'dry_run')
    ),
    scanned_count INTEGER NOT NULL DEFAULT 0 CHECK (scanned_count >= 0),
    promoted_count INTEGER NOT NULL DEFAULT 0 CHECK (promoted_count >= 0),
    repaired_video_scan_count INTEGER NOT NULL DEFAULT 0 CHECK (
        repaired_video_scan_count >= 0
    ),
    deleted_staging_object_count INTEGER NOT NULL DEFAULT 0 CHECK (
        deleted_staging_object_count >= 0
    ),
    failed_asset_count INTEGER NOT NULL DEFAULT 0 CHECK (
        failed_asset_count >= 0
    ),
    missing_object_count INTEGER NOT NULL DEFAULT 0 CHECK (
        missing_object_count >= 0
    ),
    still_pending_count INTEGER NOT NULL DEFAULT 0 CHECK (
        still_pending_count >= 0
    ),
    error_count INTEGER NOT NULL DEFAULT 0 CHECK (error_count >= 0),
    errors JSONB NOT NULL DEFAULT '[]'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scan_media_reconciliation_runs_started
    ON public.scan_media_reconciliation_runs(started_at DESC);

CREATE INDEX IF NOT EXISTS idx_scan_media_reconciliation_runs_status
    ON public.scan_media_reconciliation_runs(status, started_at DESC);

ALTER TABLE public.scan_media_reconciliation_runs ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.scan_media_reconciliation_runs IS
  'Service-role audit log for the scan media reconciliation worker. Tracks staged upload-session repair and cleanup counts.';

COMMENT ON COLUMN public.scan_media_reconciliation_runs.repaired_video_scan_count IS
  'Number of existing scan rows repaired by promoting a stranded staged playback video and rebuilding captured_media.';

CREATE INDEX IF NOT EXISTS idx_scan_media_assets_staged_capture_upload_age
    ON public.scan_media_assets(created_at, client_scan_id)
    WHERE source = 'capture_upload' AND status = 'staged';

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

DO $$
BEGIN
    PERFORM cron.unschedule('reconcile_scan_media_assets_hourly');
EXCEPTION WHEN OTHERS THEN
END;
$$;

SELECT cron.schedule(
    'reconcile_scan_media_assets_hourly',
    '17 * * * *',
    $$
    DO $job$
    DECLARE
        project_url text;
        service_role_key text;
        edge_endpoint text;
    BEGIN
        SELECT decrypted_secret INTO project_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
        SELECT decrypted_secret INTO service_role_key FROM vault.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;

        IF project_url IS NULL THEN
            project_url := current_setting('app.settings.supabase_url', true);
        END IF;

        IF service_role_key IS NULL THEN
            service_role_key := current_setting('app.settings.service_role_key', true);
        END IF;

        edge_endpoint := project_url || '/functions/v1/reconcile-scan-media-assets';

        PERFORM net.http_post(
            url := edge_endpoint,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || service_role_key
            ),
            body := jsonb_build_object(
                'limit', 100,
                'repairAfterMinutes', 15,
                'abandonAfterHours', 36
            )
        );
    END;
    $job$;
    $$
);
