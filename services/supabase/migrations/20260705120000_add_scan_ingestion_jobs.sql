-- Durable scan-ingestion job ledger.
--
-- This table records the server-side lifecycle for accepted identify requests
-- keyed by the client scan id. It does not store raw image/audio/video bytes.
-- Media references are limited to staging object keys and count metadata so
-- check-scan-status and ops can distinguish "not started", "finalizing",
-- "retryable failure", and "complete" without scraping logs.

CREATE TABLE IF NOT EXISTS public.scan_ingestion_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id TEXT NOT NULL CHECK (NULLIF(BTRIM(scan_id), '') IS NOT NULL),
    user_id UUID NOT NULL,
    endpoint TEXT NOT NULL DEFAULT 'identify-multimodal' CHECK (NULLIF(BTRIM(endpoint), '') IS NOT NULL),
    status TEXT NOT NULL DEFAULT 'processing' CHECK (
        status IN (
            'processing',
            'finalizing',
            'retrying',
            'failed_retryable',
            'failed_terminal',
            'complete'
        )
    ),
    stage TEXT NOT NULL DEFAULT 'request_received' CHECK (NULLIF(BTRIM(stage), '') IS NOT NULL),
    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    media_counts JSONB NOT NULL DEFAULT '{}'::JSONB,
    media_object_keys JSONB NOT NULL DEFAULT '{}'::JSONB,
    upload_session_ids UUID[] NOT NULL DEFAULT '{}'::UUID[],
    locked_at TIMESTAMPTZ,
    lock_expires_at TIMESTAMPTZ,
    retry_after TIMESTAMPTZ,
    last_error TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, scan_id)
);

CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_scan_user
    ON public.scan_ingestion_jobs(user_id, scan_id);

CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_status_updated
    ON public.scan_ingestion_jobs(status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_retryable
    ON public.scan_ingestion_jobs(retry_after, updated_at)
    WHERE status IN ('failed_retryable', 'retrying');

ALTER TABLE public.scan_ingestion_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own scan ingestion jobs" ON public.scan_ingestion_jobs;
CREATE POLICY "Users can read their own scan ingestion jobs"
    ON public.scan_ingestion_jobs
    FOR SELECT
    USING (auth.uid() = user_id);

COMMENT ON TABLE public.scan_ingestion_jobs IS
  'Durable server-side lifecycle rows for accepted scan ingestion requests. Stores state and staged object references, not raw media bytes.';

COMMENT ON COLUMN public.scan_ingestion_jobs.scan_id IS
  'Client-generated scan id used for idempotent scan insertion and status polling.';

COMMENT ON COLUMN public.scan_ingestion_jobs.status IS
  'Current job status used by check-scan-status and ops: processing, finalizing, retrying, failed_retryable, failed_terminal, or complete.';

COMMENT ON COLUMN public.scan_ingestion_jobs.media_counts IS
  'Structured counts such as image_count, audio_count, video_count, required_video_count, and video_frame_count.';

COMMENT ON COLUMN public.scan_ingestion_jobs.media_object_keys IS
  'Staged R2 object keys used by the ingestion request. Raw inline media bytes are never stored here.';

CREATE OR REPLACE FUNCTION public.claim_scan_ingestion_job(
    p_scan_id TEXT,
    p_user_id UUID,
    p_endpoint TEXT,
    p_media_counts JSONB DEFAULT '{}'::JSONB,
    p_media_object_keys JSONB DEFAULT '{}'::JSONB,
    p_upload_session_ids UUID[] DEFAULT '{}'::UUID[],
    p_lease_seconds INTEGER DEFAULT 300
)
RETURNS public.scan_ingestion_jobs
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    claimed public.scan_ingestion_jobs;
    lease_seconds INTEGER := GREATEST(COALESCE(p_lease_seconds, 300), 30);
BEGIN
    IF NULLIF(BTRIM(COALESCE(p_scan_id, '')), '') IS NULL THEN
        RAISE EXCEPTION 'scan_id is required';
    END IF;

    INSERT INTO public.scan_ingestion_jobs (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        attempt_count,
        media_counts,
        media_object_keys,
        upload_session_ids,
        locked_at,
        lock_expires_at,
        retry_after,
        last_error,
        completed_at,
        updated_at
    )
    VALUES (
        p_scan_id,
        p_user_id,
        COALESCE(NULLIF(BTRIM(p_endpoint), ''), 'identify-multimodal'),
        'processing',
        'request_received',
        1,
        COALESCE(p_media_counts, '{}'::JSONB),
        COALESCE(p_media_object_keys, '{}'::JSONB),
        COALESCE(p_upload_session_ids, '{}'::UUID[]),
        NOW(),
        NOW() + MAKE_INTERVAL(secs => lease_seconds),
        NULL,
        NULL,
        NULL,
        NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE
    SET
        endpoint = EXCLUDED.endpoint,
        status = CASE
            WHEN public.scan_ingestion_jobs.status = 'complete' THEN 'complete'
            ELSE 'processing'
        END,
        stage = CASE
            WHEN public.scan_ingestion_jobs.status = 'complete' THEN public.scan_ingestion_jobs.stage
            ELSE 'request_received'
        END,
        attempt_count = CASE
            WHEN public.scan_ingestion_jobs.status = 'complete' THEN public.scan_ingestion_jobs.attempt_count
            ELSE public.scan_ingestion_jobs.attempt_count + 1
        END,
        media_counts = EXCLUDED.media_counts,
        media_object_keys = EXCLUDED.media_object_keys,
        upload_session_ids = EXCLUDED.upload_session_ids,
        locked_at = CASE
            WHEN public.scan_ingestion_jobs.status = 'complete' THEN public.scan_ingestion_jobs.locked_at
            ELSE EXCLUDED.locked_at
        END,
        lock_expires_at = CASE
            WHEN public.scan_ingestion_jobs.status = 'complete' THEN public.scan_ingestion_jobs.lock_expires_at
            ELSE EXCLUDED.lock_expires_at
        END,
        retry_after = CASE
            WHEN public.scan_ingestion_jobs.status = 'complete' THEN public.scan_ingestion_jobs.retry_after
            ELSE NULL
        END,
        last_error = CASE
            WHEN public.scan_ingestion_jobs.status = 'complete' THEN public.scan_ingestion_jobs.last_error
            ELSE NULL
        END,
        updated_at = NOW()
    RETURNING * INTO claimed;

    RETURN claimed;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_scan_ingestion_job(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    UUID[],
    INTEGER
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_scan_ingestion_job(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    UUID[],
    INTEGER
) TO service_role;
