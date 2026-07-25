-- Account deletion is a durable, retryable state machine.
--
-- The previous Edge path deleted auth.users before relational anonymization.
-- A later database failure therefore stranded personal data behind an identity
-- that could no longer authenticate. The database now records intent first,
-- fences workers with leases, completes and verifies relational cleanup in one
-- transaction, and only then permits the Edge worker to delete the Auth user.

CREATE TABLE internal.account_deletion_jobs (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    user_id UUID,
    status TEXT NOT NULL DEFAULT 'pending',
    requested_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    cleanup_completed_at TIMESTAMPTZ,
    auth_deleted_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    claim_token UUID,
    claimed_at TIMESTAMPTZ,
    claim_expires_at TIMESTAMPTZ,
    last_error_code TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT account_deletion_jobs_active_user_unique UNIQUE (user_id),
    CONSTRAINT account_deletion_jobs_status_check
        CHECK (status IN ('pending', 'auth_pending', 'completed')),
    CONSTRAINT account_deletion_jobs_attempt_count_check
        CHECK (attempt_count >= 0),
    CONSTRAINT account_deletion_jobs_error_code_check
        CHECK (
            last_error_code IS NULL
            OR (
                pg_catalog.CHAR_LENGTH(last_error_code) BETWEEN 1 AND 120
                AND last_error_code !~ '[[:cntrl:]]'
            )
        ),
    CONSTRAINT account_deletion_jobs_claim_check
        CHECK (
            (
                claim_token IS NULL
                AND claimed_at IS NULL
                AND claim_expires_at IS NULL
            )
            OR (
                claim_token IS NOT NULL
                AND claimed_at IS NOT NULL
                AND claim_expires_at IS NOT NULL
                AND claim_expires_at > claimed_at
            )
        ),
    CONSTRAINT account_deletion_jobs_state_check
        CHECK (
            (
                status = 'pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'auth_pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NOT NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'completed'
                AND user_id IS NULL
                AND cleanup_completed_at IS NOT NULL
                AND auth_deleted_at IS NOT NULL
                AND completed_at IS NOT NULL
                AND claim_token IS NULL
                AND claimed_at IS NULL
                AND claim_expires_at IS NULL
                AND last_error_code IS NULL
            )
        )
);

COMMENT ON TABLE internal.account_deletion_jobs IS
    'Private durable account-erasure state machine. Active rows retain the Auth UUID only until cleanup and Auth deletion complete; terminal rows erase it.';

ALTER TABLE internal.account_deletion_jobs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.account_deletion_jobs
    FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX account_deletion_jobs_due_idx
    ON internal.account_deletion_jobs (
        next_attempt_at,
        requested_at,
        id
    )
    WHERE status IN ('pending', 'auth_pending');

CREATE INDEX account_deletion_jobs_expired_claim_idx
    ON internal.account_deletion_jobs (
        claim_expires_at,
        id
    )
    WHERE claim_token IS NOT NULL;

-- Auth remains present until the final external step. Prevent Auth metadata
-- triggers or trusted backend upserts from resurrecting the public profile
-- after deletion intent has been recorded.
CREATE OR REPLACE FUNCTION internal.reject_account_deletion_profile_recreation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.id <>
       '00000000-0000-0000-0000-000000000000'::UUID
       AND EXISTS (
           SELECT 1
           FROM internal.account_deletion_jobs AS deletion_job
           WHERE deletion_job.user_id = NEW.id
             AND deletion_job.status IN ('pending', 'auth_pending')
       ) THEN
        RAISE EXCEPTION 'account_deletion_in_progress'
            USING ERRCODE = '55000';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION internal.reject_account_deletion_profile_recreation() IS
    'Blocks recreation of public.users while durable account deletion is active, closing the cleanup-to-Auth-removal race.';

REVOKE ALL ON FUNCTION internal.reject_account_deletion_profile_recreation()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_reject_account_deletion_profile_recreation
    ON public.users;
CREATE TRIGGER trg_reject_account_deletion_profile_recreation
BEFORE INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.reject_account_deletion_profile_recreation();

-- The legacy queue pre-dates an idempotency constraint. Preserve the oldest
-- outbox row for each user before making retries conflict-safe.
WITH duplicate_storage_deletions AS (
    SELECT ranked.id
    FROM (
        SELECT
            deletion.id,
            pg_catalog.ROW_NUMBER() OVER (
                PARTITION BY deletion.target_user_id
                ORDER BY
                    CASE deletion.status
                        WHEN 'completed' THEN 1
                        WHEN 'processing' THEN 2
                        WHEN 'pending' THEN 3
                        ELSE 4
                    END,
                    deletion.created_at,
                    deletion.id
            ) AS duplicate_rank
        FROM public.pending_storage_deletions AS deletion
    ) AS ranked
    WHERE ranked.duplicate_rank > 1
)
DELETE FROM public.pending_storage_deletions AS deletion
USING duplicate_storage_deletions AS duplicate
WHERE deletion.id = duplicate.id;

CREATE UNIQUE INDEX pending_storage_deletions_target_user_unique_idx
    ON public.pending_storage_deletions (target_user_id);

CREATE OR REPLACE FUNCTION public.request_account_deletion(
    p_user_id UUID
)
RETURNS TABLE (
    job_id UUID,
    job_status TEXT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_user_id =
           '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    INSERT INTO internal.account_deletion_jobs AS deletion_job (
        user_id,
        status,
        next_attempt_at
    )
    VALUES (
        p_user_id,
        'pending',
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET updated_at = pg_catalog.NOW()
    RETURNING deletion_job.id, deletion_job.status;
END;
$$;

COMMENT ON FUNCTION public.request_account_deletion(UUID) IS
    'Service-only idempotent intake for an authenticated user account-deletion request. It persists intent before any destructive work.';

CREATE OR REPLACE FUNCTION public.claim_account_deletion_jobs(
    p_limit INTEGER DEFAULT 25,
    p_target_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    job_id UUID,
    user_id UUID,
    job_status TEXT,
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

    IF p_target_user_id =
       '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH candidates AS (
        SELECT deletion_job.id
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.status IN ('pending', 'auth_pending')
          AND deletion_job.user_id IS NOT NULL
          AND deletion_job.next_attempt_at <= pg_catalog.NOW()
          AND (
              deletion_job.claim_token IS NULL
              OR deletion_job.claim_expires_at <= pg_catalog.NOW()
          )
          AND (
              p_target_user_id IS NULL
              OR deletion_job.user_id = p_target_user_id
          )
        ORDER BY
            deletion_job.next_attempt_at,
            deletion_job.requested_at,
            deletion_job.id
        FOR UPDATE OF deletion_job SKIP LOCKED
        LIMIT LEAST(
            GREATEST(COALESCE(p_limit, 25), 1),
            100
        )
    ),
    claimed AS (
        UPDATE internal.account_deletion_jobs AS deletion_job
        SET claim_token = pg_catalog.GEN_RANDOM_UUID(),
            claimed_at = pg_catalog.CLOCK_TIMESTAMP(),
            claim_expires_at =
                pg_catalog.CLOCK_TIMESTAMP() + INTERVAL '5 minutes',
            attempt_count = deletion_job.attempt_count + 1,
            updated_at = pg_catalog.NOW()
        FROM candidates
        WHERE deletion_job.id = candidates.id
        RETURNING
            deletion_job.id,
            deletion_job.user_id,
            deletion_job.status,
            deletion_job.claim_token,
            deletion_job.claim_expires_at
    )
    SELECT
        claimed.id,
        claimed.user_id,
        claimed.status,
        claimed.claim_token,
        claimed.claim_expires_at
    FROM claimed
    ORDER BY claimed.id;
END;
$$;

COMMENT ON FUNCTION public.claim_account_deletion_jobs(INTEGER, UUID) IS
    'Service-only SKIP LOCKED lease claim for due account-deletion jobs. A target UUID is used only for the initiating request fast path.';

CREATE OR REPLACE FUNCTION public.complete_account_deletion_cleanup(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();

    IF p_job_id IS NULL OR p_claim_token IS NULL THEN
        RAISE EXCEPTION 'account_deletion_claim_required'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.*
    INTO deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = p_job_id
      AND jobs.claim_token = p_claim_token
    FOR UPDATE;

    IF NOT FOUND
       OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP() THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF deletion_job.status NOT IN ('pending', 'auth_pending')
       OR deletion_job.user_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_invalid_state'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.pending_storage_deletions AS existing_deletion (
        target_user_id,
        status
    )
    VALUES (
        deletion_job.user_id,
        'pending'
    )
    ON CONFLICT (target_user_id) DO UPDATE
    SET status = CASE
        WHEN existing_deletion.status IN (
            'completed',
            'processing'
        ) THEN existing_deletion.status
        ELSE 'pending'
    END;

    PERFORM public.apply_user_tombstone(deletion_job.user_id);

    IF EXISTS (
        SELECT 1
        FROM public.users AS users
        WHERE users.id = deletion_job.user_id
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.user_id = deletion_job.user_id
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.pending_storage_deletions AS deletion
        WHERE deletion.target_user_id = deletion_job.user_id
    ) THEN
        RAISE EXCEPTION 'account_deletion_cleanup_verification_failed'
            USING ERRCODE = 'P0004';
    END IF;

    UPDATE internal.account_deletion_jobs AS jobs
    SET status = 'auth_pending',
        cleanup_completed_at = COALESCE(
            jobs.cleanup_completed_at,
            pg_catalog.NOW()
        ),
        next_attempt_at = pg_catalog.NOW(),
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE jobs.id = deletion_job.id
      AND jobs.claim_token = p_claim_token;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID) IS
    'Service-only claimed transition that atomically queues storage cleanup, tombstones relational data, verifies anonymization, and advances to auth_pending.';

CREATE OR REPLACE FUNCTION public.finish_account_deletion_attempt(
    p_job_id UUID,
    p_claim_token UUID,
    p_auth_deleted BOOLEAN,
    p_error_code TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    retry_delay INTERVAL;
BEGIN
    PERFORM internal.require_service_role();

    IF p_job_id IS NULL
       OR p_claim_token IS NULL
       OR p_auth_deleted IS NULL THEN
        RAISE EXCEPTION 'account_deletion_attempt_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.*
    INTO deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = p_job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_job_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF deletion_job.status = 'completed' THEN
        IF p_auth_deleted THEN
            RETURN;
        END IF;

        RAISE EXCEPTION 'account_deletion_already_completed'
            USING ERRCODE = '55000';
    END IF;

    IF deletion_job.claim_token IS NULL
       OR deletion_job.claim_token <> p_claim_token
       OR deletion_job.claim_expires_at IS NULL
       OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP() THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_auth_deleted THEN
        IF deletion_job.status <> 'auth_pending'
           OR deletion_job.cleanup_completed_at IS NULL THEN
            RAISE EXCEPTION 'account_deletion_cleanup_required'
                USING ERRCODE = '55000';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM public.users AS users
            WHERE users.id = deletion_job.user_id
        ) OR EXISTS (
            SELECT 1
            FROM public.scans AS scans
            WHERE scans.user_id = deletion_job.user_id
        ) OR NOT EXISTS (
            SELECT 1
            FROM public.pending_storage_deletions AS deletion
            WHERE deletion.target_user_id = deletion_job.user_id
        ) THEN
            RAISE EXCEPTION 'account_deletion_cleanup_verification_failed'
                USING ERRCODE = 'P0004';
        END IF;

        UPDATE internal.account_deletion_jobs AS jobs
        SET user_id = NULL,
            status = 'completed',
            auth_deleted_at = pg_catalog.NOW(),
            completed_at = pg_catalog.NOW(),
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;
    ELSE
        retry_delay := CASE
            WHEN deletion_job.attempt_count <= 1 THEN INTERVAL '1 minute'
            WHEN deletion_job.attempt_count = 2 THEN INTERVAL '2 minutes'
            WHEN deletion_job.attempt_count = 3 THEN INTERVAL '5 minutes'
            WHEN deletion_job.attempt_count = 4 THEN INTERVAL '15 minutes'
            ELSE INTERVAL '1 hour'
        END;

        UPDATE internal.account_deletion_jobs AS jobs
        SET next_attempt_at = pg_catalog.NOW() + retry_delay,
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = pg_catalog.LEFT(
                COALESCE(
                    NULLIF(
                        pg_catalog.BTRIM(p_error_code),
                        ''
                    ),
                    'retryable_failure'
                ),
                120
            ),
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;
    END IF;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.finish_account_deletion_attempt(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) IS
    'Service-only claim-fenced completion/retry transition. Auth success is rejected unless relational cleanup was committed and re-verified first.';

REVOKE ALL ON FUNCTION public.request_account_deletion(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_account_deletion_jobs(INTEGER, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.finish_account_deletion_attempt(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.request_account_deletion(uuid)',
        'Authenticated safe-delete intake persists deletion intent before destructive work.'
    ),
    (
        'service_role',
        'public.claim_account_deletion_jobs(integer,uuid)',
        'Account-deletion Edge workers lease due cleanup and Auth-deletion jobs.'
    ),
    (
        'service_role',
        'public.complete_account_deletion_cleanup(uuid,uuid)',
        'Claimed account-deletion worker atomically tombstones and verifies relational cleanup.'
    ),
    (
        'service_role',
        'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)',
        'Claimed account-deletion worker records Auth completion or a bounded retry.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

GRANT EXECUTE ON FUNCTION public.request_account_deletion(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion_jobs(INTEGER, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_account_deletion_attempt(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) TO service_role;

DO $migration$
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'API roles unexpectedly have direct account-deletion internals access.';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'Account-deletion intake grants do not match the service-only boundary.';
    END IF;
END;
$migration$;

DO $migration$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM cron.job
        WHERE jobname = 'reconcile_account_deletions_every_five_minutes'
    ) THEN
        PERFORM cron.unschedule(
            'reconcile_account_deletions_every_five_minutes'
        );
    END IF;
END;
$migration$;

SELECT cron.schedule(
    'reconcile_account_deletions_every_five_minutes',
    '*/5 * * * *',
    $schedule$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        SELECT decrypted_secret
        INTO project_url
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT decrypted_secret
        INTO service_role_key
        FROM vault.decrypted_secrets
        WHERE name = 'SUPABASE_SERVICE_ROLE_KEY'
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

        IF project_url IS NOT NULL AND service_role_key IS NOT NULL THEN
            PERFORM net.http_post(
                url := project_url ||
                    '/functions/v1/reconcile-account-deletions',
                headers := pg_catalog.JSONB_BUILD_OBJECT(
                    'Content-Type',
                    'application/json',
                    'Authorization',
                    'Bearer ' || service_role_key
                ),
                body := pg_catalog.JSONB_BUILD_OBJECT('limit', 25)
            );
        END IF;
    END;
    $job$;
    $schedule$
);

NOTIFY pgrst, 'reload schema';
