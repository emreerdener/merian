-- Prevent an orphaned storage-erasure outbox row from deleting a live account's
-- R2 prefixes. A deletion row is actionable only after the matching durable
-- account-deletion job has completed relational tombstoning.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

CREATE OR REPLACE FUNCTION public.claim_pending_storage_deletions(
    p_limit INTEGER DEFAULT 25
)
RETURNS TABLE (
    deletion_id UUID,
    target_user_id UUID,
    object_prefix TEXT,
    start_after_key TEXT,
    deletion_phase TEXT,
    claim_token UUID,
    claim_expires_at TIMESTAMPTZ
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH candidates AS (
        SELECT deletion.id
        FROM public.pending_storage_deletions AS deletion
        INNER JOIN internal.account_deletion_jobs AS deletion_job
            ON deletion_job.user_id = deletion.target_user_id
           AND deletion_job.status = 'storage_pending'
           AND deletion_job.cleanup_completed_at IS NOT NULL
           AND deletion_job.storage_completed_at IS NULL
        WHERE deletion.status IN ('pending', 'processing')
          AND deletion.next_attempt_at <= pg_catalog.NOW()
          AND (
              deletion.claim_token IS NULL
              OR deletion.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP()
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.users AS live_user
              WHERE live_user.id = deletion.target_user_id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.scans AS owned_scan
              WHERE owned_scan.user_id = deletion.target_user_id
          )
        ORDER BY deletion.next_attempt_at, deletion.created_at, deletion.id
        FOR UPDATE OF deletion SKIP LOCKED
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100)
    ),
    claimed AS (
        UPDATE public.pending_storage_deletions AS deletion
        SET status = 'processing',
            claim_token = pg_catalog.GEN_RANDOM_UUID(),
            claimed_at = pg_catalog.CLOCK_TIMESTAMP(),
            claim_expires_at =
                pg_catalog.CLOCK_TIMESTAMP() + INTERVAL '5 minutes',
            attempt_count = deletion.attempt_count + 1,
            updated_at = pg_catalog.NOW()
        FROM candidates
        WHERE deletion.id = candidates.id
        RETURNING deletion.*
    )
    SELECT
        claimed.id,
        claimed.target_user_id,
        claimed.prefixes[claimed.prefix_index],
        claimed.start_after_key,
        claimed.phase,
        claimed.claim_token,
        claimed.claim_expires_at
    FROM claimed
    ORDER BY claimed.id;
END;
$$;

COMMENT ON FUNCTION public.claim_pending_storage_deletions(INTEGER) IS
    'Service-only R2 erasure lease claim, fenced to a tombstoned storage_pending account-deletion job.';

REVOKE ALL ON FUNCTION public.claim_pending_storage_deletions(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_pending_storage_deletions(INTEGER)
    TO service_role;

COMMIT;
