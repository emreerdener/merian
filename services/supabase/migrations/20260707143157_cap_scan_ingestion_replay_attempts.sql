-- Cap automatic server-side scan ingestion replay so a stuck resumable intent
-- cannot be claimed forever by the scheduled replay worker.

CREATE OR REPLACE FUNCTION public.claim_replayable_scan_ingestion_jobs(
    p_limit INTEGER DEFAULT 5,
    p_lease_seconds INTEGER DEFAULT 300
)
RETURNS TABLE (
    scan_id TEXT,
    user_id UUID,
    endpoint TEXT,
    status TEXT,
    stage TEXT,
    attempt_count INTEGER,
    media_counts JSONB,
    media_object_keys JSONB,
    upload_session_ids UUID[],
    manifest_checksum TEXT,
    request_payload JSONB,
    payload_checksum TEXT,
    replay_attempt_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    claim_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 5), 1), 50);
    lease_seconds INTEGER := GREATEST(COALESCE(p_lease_seconds, 300), 30);
    max_replay_attempts INTEGER := 10;
BEGIN
    WITH over_budget AS (
        SELECT j.id AS job_id
        FROM public.scan_ingestion_jobs j
        JOIN public.scan_ingestion_intents i
          ON i.user_id = j.user_id
         AND i.scan_id = j.scan_id
         AND i.endpoint = j.endpoint
        WHERE j.endpoint = 'identify-multimodal'
          AND j.status IN ('processing', 'finalizing', 'retrying', 'failed_retryable')
          AND i.resumable = TRUE
          AND i.inline_media_redacted = FALSE
          AND jsonb_typeof(i.request_payload) = 'object'
          AND i.replay_attempt_count >= max_replay_attempts
          AND (
              (j.status IN ('failed_retryable', 'retrying')
               AND (j.retry_after IS NULL OR j.retry_after <= NOW()))
              OR
              (j.status IN ('processing', 'finalizing')
               AND j.lock_expires_at IS NOT NULL
               AND j.lock_expires_at <= NOW())
          )
        ORDER BY
            COALESCE(j.retry_after, j.lock_expires_at, j.updated_at) ASC,
            j.updated_at ASC
        LIMIT claim_limit
        FOR UPDATE OF j SKIP LOCKED
    )
    UPDATE public.scan_ingestion_jobs j
    SET
        status = 'failed_terminal',
        stage = 'server_replay_limit_reached',
        lock_expires_at = NULL,
        retry_after = NULL,
        last_error = 'Server replay retry limit reached after 10 attempts.',
        updated_at = NOW()
    FROM over_budget o
    WHERE j.id = o.job_id
      AND j.status <> 'complete';

    RETURN QUERY
    WITH candidates AS (
        SELECT
            j.id AS job_id,
            i.id AS intent_id
        FROM public.scan_ingestion_jobs j
        JOIN public.scan_ingestion_intents i
          ON i.user_id = j.user_id
         AND i.scan_id = j.scan_id
         AND i.endpoint = j.endpoint
        WHERE j.endpoint = 'identify-multimodal'
          AND j.status IN ('processing', 'finalizing', 'retrying', 'failed_retryable')
          AND i.resumable = TRUE
          AND i.inline_media_redacted = FALSE
          AND jsonb_typeof(i.request_payload) = 'object'
          AND i.replay_attempt_count < max_replay_attempts
          AND (
              (j.status IN ('failed_retryable', 'retrying')
               AND (j.retry_after IS NULL OR j.retry_after <= NOW()))
              OR
              (j.status IN ('processing', 'finalizing')
               AND j.lock_expires_at IS NOT NULL
               AND j.lock_expires_at <= NOW())
          )
        ORDER BY
            COALESCE(j.retry_after, j.lock_expires_at, j.updated_at) ASC,
            j.updated_at ASC
        LIMIT claim_limit
        FOR UPDATE OF j SKIP LOCKED
    ),
    updated_jobs AS (
        UPDATE public.scan_ingestion_jobs j
        SET
            status = 'retrying',
            stage = 'server_replay_claimed',
            locked_at = NOW(),
            lock_expires_at = NOW() + MAKE_INTERVAL(secs => lease_seconds),
            retry_after = NULL,
            last_error = NULL,
            updated_at = NOW()
        FROM candidates c
        WHERE j.id = c.job_id
          AND j.status <> 'complete'
        RETURNING j.*
    ),
    updated_intents AS (
        UPDATE public.scan_ingestion_intents i
        SET
            last_replayed_at = NOW(),
            replay_attempt_count = i.replay_attempt_count + 1,
            last_replay_error = NULL,
            updated_at = NOW()
        FROM candidates c
        WHERE i.id = c.intent_id
        RETURNING i.*
    )
    SELECT
        j.scan_id,
        j.user_id,
        j.endpoint,
        j.status,
        j.stage,
        j.attempt_count,
        j.media_counts,
        j.media_object_keys,
        j.upload_session_ids,
        j.manifest_checksum,
        i.request_payload,
        i.payload_checksum,
        i.replay_attempt_count
    FROM updated_jobs j
    JOIN updated_intents i
      ON i.user_id = j.user_id
     AND i.scan_id = j.scan_id
     AND i.endpoint = j.endpoint;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_replayable_scan_ingestion_jobs(
    INTEGER,
    INTEGER
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_replayable_scan_ingestion_jobs(
    INTEGER,
    INTEGER
) TO service_role;

COMMENT ON FUNCTION public.claim_replayable_scan_ingestion_jobs(INTEGER, INTEGER) IS
  'Claims resumable staged scan ingestion jobs for server-side replay, capped at 10 replay attempts per intent. Returns sanitized request_payload rows only; inline media requests are excluded.';
