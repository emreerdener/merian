-- Account deletion remains durable even when the initiating request or one
-- reconciler invocation fails. Add a service-only aggregate health boundary
-- and indexes so an independent scheduler can detect reaper misconfiguration,
-- SLA breaches, retry failures, expired leases, and storage-erasure backlog
-- without exposing user identifiers or private queue rows.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

CREATE INDEX IF NOT EXISTS account_deletion_jobs_active_requested_idx
    ON internal.account_deletion_jobs (requested_at, id)
    WHERE status IN ('pending', 'storage_pending', 'auth_pending');

CREATE INDEX IF NOT EXISTS account_deletion_jobs_active_error_idx
    ON internal.account_deletion_jobs (updated_at, id)
    WHERE status IN ('pending', 'storage_pending', 'auth_pending')
      AND last_error_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS pending_storage_deletions_active_created_idx
    ON public.pending_storage_deletions (created_at, id)
    WHERE status IN ('pending', 'processing');

CREATE INDEX IF NOT EXISTS pending_storage_deletions_expired_claim_idx
    ON public.pending_storage_deletions (claim_expires_at, id)
    WHERE status IN ('pending', 'processing')
      AND claim_token IS NOT NULL;

CREATE INDEX IF NOT EXISTS pending_storage_deletions_active_error_idx
    ON public.pending_storage_deletions (updated_at, id)
    WHERE status IN ('pending', 'processing')
      AND last_error_code IS NOT NULL;

CREATE OR REPLACE FUNCTION public.get_account_deletion_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    active_job_count BIGINT,
    pending_cleanup_count BIGINT,
    storage_pending_count BIGINT,
    auth_pending_count BIGINT,
    due_job_count BIGINT,
    failed_job_count BIGINT,
    active_lease_count BIGINT,
    expired_lease_count BIGINT,
    oldest_pending_at TIMESTAMPTZ,
    oldest_pending_age_seconds BIGINT,
    oldest_due_at TIMESTAMPTZ,
    oldest_due_age_seconds BIGINT,
    storage_backlog_count BIGINT,
    storage_due_count BIGINT,
    storage_failed_job_count BIGINT,
    storage_active_lease_count BIGINT,
    storage_expired_lease_count BIGINT,
    verification_waiting_count BIGINT,
    orphaned_storage_job_count BIGINT,
    oldest_storage_pending_at TIMESTAMPTZ,
    oldest_storage_pending_age_seconds BIGINT,
    oldest_storage_due_at TIMESTAMPTZ,
    oldest_storage_due_age_seconds BIGINT,
    reaper_cron_active BOOLEAN,
    reaper_credentials_configured BOOLEAN
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
    account_health AS MATERIALIZED (
        SELECT
            pg_catalog.COUNT(*) AS active_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.status = 'pending'
            ) AS pending_cleanup_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.status = 'storage_pending'
            ) AS storage_pending_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.status = 'auth_pending'
            ) AS auth_pending_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.next_attempt_at <= clock.observed_at
                  AND (
                      deletion_job.claim_token IS NULL
                      OR deletion_job.claim_expires_at <= clock.observed_at
                  )
            ) AS due_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.last_error_code IS NOT NULL
            ) AS failed_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.claim_token IS NOT NULL
                  AND deletion_job.claim_expires_at > clock.observed_at
            ) AS active_lease_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE deletion_job.claim_token IS NOT NULL
                  AND deletion_job.claim_expires_at <= clock.observed_at
            ) AS expired_lease_count,
            pg_catalog.MIN(deletion_job.requested_at) AS oldest_pending_at,
            pg_catalog.MIN(deletion_job.next_attempt_at) FILTER (
                WHERE deletion_job.next_attempt_at <= clock.observed_at
                  AND (
                      deletion_job.claim_token IS NULL
                      OR deletion_job.claim_expires_at <= clock.observed_at
                  )
            ) AS oldest_due_at
        FROM internal.account_deletion_jobs AS deletion_job
        CROSS JOIN health_clock AS clock
        WHERE deletion_job.status IN (
            'pending',
            'storage_pending',
            'auth_pending'
        )
    ),
    storage_health AS MATERIALIZED (
        SELECT
            pg_catalog.COUNT(*) AS storage_backlog_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.next_attempt_at <= clock.observed_at
                  AND (
                      storage.claim_token IS NULL
                      OR storage.claim_expires_at <= clock.observed_at
                  )
            ) AS storage_due_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.last_error_code IS NOT NULL
            ) AS storage_failed_job_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.claim_token IS NOT NULL
                  AND storage.claim_expires_at > clock.observed_at
            ) AS storage_active_lease_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.claim_token IS NOT NULL
                  AND storage.claim_expires_at <= clock.observed_at
            ) AS storage_expired_lease_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE storage.phase = 'verification'
                  AND storage.next_attempt_at > clock.observed_at
                  AND storage.claim_token IS NULL
            ) AS verification_waiting_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE NOT EXISTS (
                    SELECT 1
                    FROM internal.account_deletion_jobs AS deletion_job
                    WHERE deletion_job.user_id = storage.target_user_id
                      AND deletion_job.status = 'storage_pending'
                      AND deletion_job.cleanup_completed_at IS NOT NULL
                      AND deletion_job.storage_completed_at IS NULL
                )
            ) AS orphaned_storage_job_count,
            pg_catalog.MIN(storage.created_at) AS oldest_storage_pending_at,
            pg_catalog.MIN(storage.next_attempt_at) FILTER (
                WHERE storage.next_attempt_at <= clock.observed_at
                  AND (
                      storage.claim_token IS NULL
                      OR storage.claim_expires_at <= clock.observed_at
                  )
            ) AS oldest_storage_due_at
        FROM public.pending_storage_deletions AS storage
        CROSS JOIN health_clock AS clock
        WHERE storage.status IN ('pending', 'processing')
    ),
    scheduler_health AS MATERIALIZED (
        SELECT EXISTS (
            SELECT 1
            FROM cron.job AS scheduled_job
            WHERE scheduled_job.jobname =
                'reconcile_account_deletions_every_five_minutes'
              AND scheduled_job.active
        ) AS reaper_cron_active
    ),
    configuration_values AS MATERIALIZED (
        SELECT
            COALESCE(
                (
                    SELECT secret.decrypted_secret
                    FROM vault.decrypted_secrets AS secret
                    WHERE secret.name = 'SUPABASE_URL'
                    LIMIT 1
                ),
                pg_catalog.CURRENT_SETTING(
                    'app.settings.supabase_url',
                    TRUE
                )
            ) AS project_url,
            COALESCE(
                (
                    SELECT secret.decrypted_secret
                    FROM vault.decrypted_secrets AS secret
                    WHERE secret.name = 'SUPABASE_SERVICE_ROLE_KEY'
                    LIMIT 1
                ),
                pg_catalog.CURRENT_SETTING(
                    'app.settings.service_role_key',
                    TRUE
                )
            ) AS service_role_key
    ),
    configuration_health AS MATERIALIZED (
        -- Match the reaper's Vault-first, NULL-only fallback exactly. A blank
        -- Vault value must not be masked by a nonblank legacy app setting.
        SELECT
            NULLIF(
                pg_catalog.BTRIM(configuration.project_url),
                ''
            ) IS NOT NULL
            AND NULLIF(
                pg_catalog.BTRIM(configuration.service_role_key),
                ''
            ) IS NOT NULL AS reaper_credentials_configured
        FROM configuration_values AS configuration
    )
    SELECT
        clock.observed_at,
        accounts.active_job_count,
        accounts.pending_cleanup_count,
        accounts.storage_pending_count,
        accounts.auth_pending_count,
        accounts.due_job_count,
        accounts.failed_job_count,
        accounts.active_lease_count,
        accounts.expired_lease_count,
        accounts.oldest_pending_at,
        CASE
            WHEN accounts.oldest_pending_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at - accounts.oldest_pending_at
                    )
                )::BIGINT
            )
        END,
        accounts.oldest_due_at,
        CASE
            WHEN accounts.oldest_due_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at - accounts.oldest_due_at
                    )
                )::BIGINT
            )
        END,
        storage.storage_backlog_count,
        storage.storage_due_count,
        storage.storage_failed_job_count,
        storage.storage_active_lease_count,
        storage.storage_expired_lease_count,
        storage.verification_waiting_count,
        storage.orphaned_storage_job_count,
        storage.oldest_storage_pending_at,
        CASE
            WHEN storage.oldest_storage_pending_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at -
                            storage.oldest_storage_pending_at
                    )
                )::BIGINT
            )
        END,
        storage.oldest_storage_due_at,
        CASE
            WHEN storage.oldest_storage_due_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at -
                            storage.oldest_storage_due_at
                    )
                )::BIGINT
            )
        END,
        scheduler.reaper_cron_active,
        configuration.reaper_credentials_configured
    FROM health_clock AS clock
    CROSS JOIN account_health AS accounts
    CROSS JOIN storage_health AS storage
    CROSS JOIN scheduler_health AS scheduler
    CROSS JOIN configuration_health AS configuration;
END;
$$;

COMMENT ON FUNCTION public.get_account_deletion_health() IS
    'Returns aggregate service-only account-erasure queue, lease, retry, scheduler, credential, and SLA health without user identifiers.';

REVOKE ALL ON FUNCTION public.get_account_deletion_health()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_account_deletion_health()
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.get_account_deletion_health()',
    'Reads aggregate account-erasure backlog, lease, retry, scheduler, and configuration health for independent production alerting.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

COMMIT;
