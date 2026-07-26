BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- Queue-depth inspection must remain proportional to outstanding exports.
-- The work table already has an oldest-due partial index; this companion
-- partial index makes the canonical job-status join and oldest-job diagnosis
-- independent of completed export history.
CREATE INDEX IF NOT EXISTS idx_export_jobs_nonterminal_created
    ON public.export_jobs (created_at, id)
    WHERE status IN ('pending', 'processing');

COMMENT ON TABLE internal.export_job_work IS
    'Durable cursor, budget, retry, and phase state drained in fair deadline-bounded waves by the DwC-A Edge worker.';

-- The original compatibility query LEFT JOINed work and ordered by COALESCE.
-- The work-table install backfilled every nonterminal job and its insertion
-- trigger maintains that invariant, so use the partial due index directly.
CREATE OR REPLACE FUNCTION public.get_due_export_job_ids(
    p_limit INTEGER DEFAULT 1
)
RETURNS TABLE (job_id UUID)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 5 THEN
        RAISE EXCEPTION 'invalid_export_dispatch_limit'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH dispatch_clock AS MATERIALIZED (
        SELECT pg_catalog.STATEMENT_TIMESTAMP() AS observed_at
    )
    SELECT work.job_id
    FROM internal.export_job_work AS work
    CROSS JOIN dispatch_clock AS clock
    JOIN public.export_jobs AS jobs
      ON jobs.id = work.job_id
    LEFT JOIN internal.export_job_claims AS claims
      ON claims.job_id = work.job_id
    WHERE work.phase <> 'completed'
      AND work.next_step_at <= clock.observed_at
      AND jobs.status IN ('pending', 'processing')
      AND (
          claims.job_id IS NULL
          OR claims.lease_expires_at <= clock.observed_at
      )
    ORDER BY work.next_step_at, work.job_id
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION public.get_due_export_job_ids(INTEGER) IS
    'Returns at most five unleased export jobs in oldest-due order so each deadline-bounded dispatcher wave rotates work fairly.';

REVOKE ALL ON FUNCTION public.get_due_export_job_ids(INTEGER)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_due_export_job_ids(INTEGER)
TO service_role;

CREATE OR REPLACE FUNCTION public.get_dwca_export_queue_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    backlog_count BIGINT,
    due_count BIGINT,
    active_claim_count BIGINT,
    expired_claim_count BIGINT,
    oldest_due_at TIMESTAMPTZ,
    oldest_due_age_seconds BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH health_clock AS MATERIALIZED (
        SELECT pg_catalog.STATEMENT_TIMESTAMP() AS observed_at
    ),
    outstanding AS MATERIALIZED (
        SELECT
            work.job_id,
            work.next_step_at
        FROM internal.export_job_work AS work
        JOIN public.export_jobs AS jobs
          ON jobs.id = work.job_id
        WHERE work.phase <> 'completed'
          AND jobs.status IN ('pending', 'processing')
    ),
    backlog AS (
        SELECT pg_catalog.COUNT(*) AS backlog_count
        FROM outstanding
    ),
    due AS (
        SELECT
            pg_catalog.COUNT(*) AS due_count,
            pg_catalog.MIN(work.next_step_at) AS oldest_due_at
        FROM outstanding AS work
        CROSS JOIN health_clock AS clock
        LEFT JOIN internal.export_job_claims AS claims
          ON claims.job_id = work.job_id
        WHERE work.next_step_at <= clock.observed_at
          AND (
              claims.job_id IS NULL
              OR claims.lease_expires_at <= clock.observed_at
          )
    ),
    claim_health AS (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE claims.lease_expires_at > clock.observed_at
            ) AS active_claim_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE claims.lease_expires_at <= clock.observed_at
            ) AS expired_claim_count
        FROM outstanding AS work
        CROSS JOIN health_clock AS clock
        JOIN internal.export_job_claims AS claims
          ON claims.job_id = work.job_id
    )
    SELECT
        clock.observed_at,
        backlog.backlog_count,
        due.due_count,
        claims.active_claim_count,
        claims.expired_claim_count,
        due.oldest_due_at,
        CASE
            WHEN due.oldest_due_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at - due.oldest_due_at
                    )
                )::BIGINT
            )
        END
    FROM health_clock AS clock
    CROSS JOIN backlog
    CROSS JOIN due
    CROSS JOIN claim_health AS claims;
END;
$$;

COMMENT ON FUNCTION public.get_dwca_export_queue_health() IS
    'Returns service-only DwC-A backlog depth, claim state, and oldest-due age for dispatcher logs and independent production alerting.';

REVOKE ALL ON FUNCTION public.get_dwca_export_queue_health()
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_dwca_export_queue_health()
TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.get_due_export_job_ids(integer)',
        'Discovers a bounded oldest-due wave for the fair deadline-based DwC-A dispatcher.'
    ),
    (
        'service_role',
        'public.get_dwca_export_queue_health()',
        'Reads DwC-A continuation backlog depth and oldest-due age for dispatcher telemetry and scheduled alerting.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

-- pg_net otherwise gives the HTTP response only two seconds. The Edge route
-- begins durable phases inside a 40-second soft window; allow a slow final
-- R2/provider step to complete without making pg_cron itself own export state
-- or retries.
DO $schedule$
BEGIN
    PERFORM cron.unschedule('resume_dwca_exports_every_minute');
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
$schedule$;

SELECT cron.schedule(
    'resume_dwca_exports_every_minute',
    '* * * * *',
    $cron$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        SELECT secrets.decrypted_secret
        INTO project_url
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT secrets.decrypted_secret
        INTO service_role_key
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url := pg_catalog.CURRENT_SETTING(
                'app.settings.supabase_url',
                TRUE
            );
        END IF;
        IF service_role_key IS NULL THEN
            service_role_key := pg_catalog.CURRENT_SETTING(
                'app.settings.service_role_key',
                TRUE
            );
        END IF;

        IF NULLIF(pg_catalog.BTRIM(project_url), '') IS NOT NULL
           AND NULLIF(pg_catalog.BTRIM(service_role_key), '') IS NOT NULL THEN
            PERFORM net.http_post(
                url := project_url || '/functions/v1/export-dwca',
                headers := pg_catalog.JSONB_BUILD_OBJECT(
                    'Content-Type',
                    'application/json',
                    'Authorization',
                    'Bearer ' || service_role_key
                ),
                body := '{}'::JSONB,
                timeout_milliseconds := 120000
            );
        END IF;
    END;
    $job$;
    $cron$
);

NOTIFY pgrst, 'reload schema';

COMMIT;
