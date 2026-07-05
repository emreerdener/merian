-- Extend scan ingestion jobs with a deterministic media manifest checksum.
--
-- The checksum lets clients and operators distinguish "same client_scan_id,
-- same requested media" retries from accidental request-shape drift without
-- storing raw media bytes.

ALTER TABLE public.scan_ingestion_jobs
    ADD COLUMN IF NOT EXISTS manifest_checksum TEXT;

CREATE INDEX IF NOT EXISTS idx_scan_ingestion_jobs_manifest_checksum
    ON public.scan_ingestion_jobs(user_id, manifest_checksum)
    WHERE manifest_checksum IS NOT NULL;

COMMENT ON COLUMN public.scan_ingestion_jobs.manifest_checksum IS
  'SHA-256 checksum of the normalized ingestion media manifest: counts, staged object keys, and upload session ids.';

DROP FUNCTION IF EXISTS public.claim_scan_ingestion_job(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    UUID[],
    INTEGER
);

CREATE OR REPLACE FUNCTION public.claim_scan_ingestion_job(
    p_scan_id TEXT,
    p_user_id UUID,
    p_endpoint TEXT,
    p_media_counts JSONB DEFAULT '{}'::JSONB,
    p_media_object_keys JSONB DEFAULT '{}'::JSONB,
    p_upload_session_ids UUID[] DEFAULT '{}'::UUID[],
    p_manifest_checksum TEXT DEFAULT NULL,
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
        manifest_checksum,
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
        NULLIF(BTRIM(COALESCE(p_manifest_checksum, '')), ''),
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
        manifest_checksum = COALESCE(EXCLUDED.manifest_checksum, public.scan_ingestion_jobs.manifest_checksum),
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
    TEXT,
    INTEGER
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_scan_ingestion_job(
    TEXT,
    UUID,
    TEXT,
    JSONB,
    JSONB,
    UUID[],
    TEXT,
    INTEGER
) TO service_role;

NOTIFY pgrst, 'reload schema';
