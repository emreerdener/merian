BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- Expired-lease cleanup previously scanned every queue row. PostgreSQL cannot
-- use NOW() in a partial-index predicate, so index the stable claimed-row
-- subset and keep the expiration timestamp as the leading range column.
CREATE INDEX revenuecat_reconciliation_claim_expiry_idx
    ON internal.revenuecat_reconciliation_queue (
        claim_expires_at,
        merian_user_id
    )
    INCLUDE (next_reconcile_at)
    WHERE claim_token IS NOT NULL;

CREATE OR REPLACE FUNCTION public.claim_revenuecat_reconciliations(
    p_limit INTEGER DEFAULT 6
)
RETURNS TABLE (
    user_id UUID,
    lookup_app_user_id TEXT,
    claim_token UUID,
    claim_expires_at TIMESTAMPTZ,
    allow_non_subscription_pass_grant BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_limit'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.revenuecat_reconciliation_queue AS queue
    SET claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        next_reconcile_at = LEAST(
            queue.next_reconcile_at,
            pg_catalog.NOW()
        ),
        updated_at = pg_catalog.NOW()
    WHERE queue.claim_token IS NOT NULL
      AND queue.claim_expires_at <= pg_catalog.NOW();

    RETURN QUERY
    WITH due AS (
        SELECT queue.merian_user_id
        FROM internal.revenuecat_reconciliation_queue AS queue
        WHERE queue.claim_token IS NULL
          AND queue.next_reconcile_at <= pg_catalog.NOW()
        ORDER BY queue.next_reconcile_at, queue.merian_user_id
        FOR UPDATE SKIP LOCKED
        LIMIT p_limit
    ),
    claimed AS (
        UPDATE internal.revenuecat_reconciliation_queue AS queue
        SET claim_token = extensions.gen_random_uuid(),
            claimed_at = pg_catalog.NOW(),
            claim_expires_at = pg_catalog.NOW() + INTERVAL '2 minutes',
            updated_at = pg_catalog.NOW()
        FROM due
        WHERE queue.merian_user_id = due.merian_user_id
        RETURNING
            queue.merian_user_id,
            queue.lookup_app_user_id,
            queue.claim_token,
            queue.claim_expires_at
    )
    SELECT
        claimed.merian_user_id,
        claimed.lookup_app_user_id,
        claimed.claim_token,
        claimed.claim_expires_at,
        (
            users.subscription_tier =
                'pro'::public.subscription_tier_enum
            OR states.merian_user_id IS NULL
        )
    FROM claimed
    JOIN public.users AS users
      ON users.id = claimed.merian_user_id
    LEFT JOIN internal.revenuecat_customer_state AS states
      ON states.merian_user_id = claimed.merian_user_id
    ORDER BY claimed.merian_user_id;
END;
$$;

COMMENT ON FUNCTION public.claim_revenuecat_reconciliations(INTEGER) IS
    'Reclaims expired leases through the claimed-row partial index, then leases one bounded SKIP LOCKED wave of due RevenueCat customers.';

-- Keep backlog inspection index-backed and proportional to outstanding work,
-- not the complete linked-user population. Active, unexpired claims are not
-- overdue because another worker still owns them.
CREATE OR REPLACE FUNCTION public.get_revenuecat_reconciliation_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    due_count BIGINT,
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
    unclaimed_due AS (
        SELECT
            pg_catalog.COUNT(*) AS due_count,
            pg_catalog.MIN(queue.next_reconcile_at) AS oldest_due_at
        FROM internal.revenuecat_reconciliation_queue AS queue
        CROSS JOIN health_clock AS clock
        WHERE queue.claim_token IS NULL
          AND queue.next_reconcile_at <= clock.observed_at
    ),
    expired_due AS (
        SELECT
            pg_catalog.COUNT(*) AS due_count,
            pg_catalog.MIN(queue.next_reconcile_at) AS oldest_due_at
        FROM internal.revenuecat_reconciliation_queue AS queue
        CROSS JOIN health_clock AS clock
        WHERE queue.claim_token IS NOT NULL
          AND queue.claim_expires_at <= clock.observed_at
          AND queue.next_reconcile_at <= clock.observed_at
    ),
    expired_claims AS (
        SELECT pg_catalog.COUNT(*) AS expired_claim_count
        FROM internal.revenuecat_reconciliation_queue AS queue
        CROSS JOIN health_clock AS clock
        WHERE queue.claim_token IS NOT NULL
          AND queue.claim_expires_at <= clock.observed_at
    ),
    oldest_due AS (
        SELECT pg_catalog.MIN(candidates.due_at) AS due_at
        FROM (
            VALUES
                (
                    (
                        SELECT unclaimed.oldest_due_at
                        FROM unclaimed_due AS unclaimed
                    )
                ),
                (
                    (
                        SELECT expired.oldest_due_at
                        FROM expired_due AS expired
                    )
                )
        ) AS candidates(due_at)
    )
    SELECT
        clock.observed_at,
        unclaimed.due_count + expired.due_count,
        expired_claims.expired_claim_count,
        oldest.due_at,
        CASE
            WHEN oldest.due_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM clock.observed_at - oldest.due_at
                    )
                )::BIGINT
            )
        END
    FROM health_clock AS clock
    CROSS JOIN unclaimed_due AS unclaimed
    CROSS JOIN expired_due AS expired
    CROSS JOIN expired_claims
    CROSS JOIN oldest_due AS oldest;
END;
$$;

COMMENT ON FUNCTION public.get_revenuecat_reconciliation_health() IS
    'Returns service-only due-count, expired-lease, and oldest-due-age telemetry using the two partial queue indexes.';

REVOKE ALL ON FUNCTION public.claim_revenuecat_reconciliations(INTEGER)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_revenuecat_reconciliations(INTEGER)
TO service_role;

REVOKE ALL ON FUNCTION public.get_revenuecat_reconciliation_health()
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_revenuecat_reconciliation_health()
TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.claim_revenuecat_reconciliations(integer)',
        'Reclaims expired subscriber leases and leases one bounded SKIP LOCKED reconciliation wave.'
    ),
    (
        'service_role',
        'public.get_revenuecat_reconciliation_health()',
        'Reads index-backed RevenueCat subscriber backlog age for scheduled alerting.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

-- pg_net defaults to a two-second response timeout. The Edge worker now drains
-- for up to 90 seconds, so leave connection headroom while staying below the
-- hosted 150-second response-initiation ceiling.
DO $schedule$
BEGIN
    PERFORM cron.unschedule(
        'reconcile_revenuecat_subscribers_every_fifteen_minutes'
    );
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
$schedule$;

SELECT cron.schedule(
    'reconcile_revenuecat_subscribers_every_fifteen_minutes',
    '*/15 * * * *',
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
            project_url :=
                pg_catalog.CURRENT_SETTING(
                    'app.settings.supabase_url',
                    TRUE
                );
        END IF;
        IF service_role_key IS NULL THEN
            service_role_key :=
                pg_catalog.CURRENT_SETTING(
                    'app.settings.service_role_key',
                    TRUE
                );
        END IF;

        IF project_url IS NOT NULL AND service_role_key IS NOT NULL THEN
            PERFORM net.http_post(
                url := project_url ||
                    '/functions/v1/reconcile-revenuecat-subscribers',
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
