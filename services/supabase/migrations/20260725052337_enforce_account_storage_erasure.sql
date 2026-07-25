-- Make object-storage erasure a required durable phase of account deletion.
--
-- Existing workers considered creation of pending_storage_deletions sufficient
-- and could remove auth.users while R2 media remained. The outbox is now a
-- leased, retryable prefix sweep with a delayed verification pass. The delay is
-- intentionally longer than the maximum staging PUT signature lifetime, and
-- new signatures are denied as soon as deletion intent exists.

BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

ALTER TABLE public.pending_storage_deletions
    ADD COLUMN IF NOT EXISTS prefixes TEXT[],
    ADD COLUMN IF NOT EXISTS phase TEXT,
    ADD COLUMN IF NOT EXISTS prefix_index INTEGER,
    ADD COLUMN IF NOT EXISTS start_after_key TEXT,
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER,
    ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS claim_token UUID,
    ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS claim_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verification_not_before TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_error_code TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE public.pending_storage_deletions AS deletion
SET status = 'pending',
    prefixes = ARRAY[
        'public_uploads/free/' || deletion.target_user_id::TEXT || '/',
        'public_uploads/pro/' || deletion.target_user_id::TEXT || '/',
        'staging/' || deletion.target_user_id::TEXT || '/',
        'avatars/' || deletion.target_user_id::TEXT || '/',
        'exports/' || deletion.target_user_id::TEXT || '/'
    ]::TEXT[],
    phase = 'sweep',
    prefix_index = 1,
    start_after_key = NULL,
    attempt_count = 0,
    next_attempt_at = pg_catalog.NOW(),
    verification_not_before =
        pg_catalog.NOW() + INTERVAL '25 hours',
    completed_at = NULL,
    claim_token = NULL,
    claimed_at = NULL,
    claim_expires_at = NULL,
    last_error_code = NULL,
    updated_at = pg_catalog.NOW();

ALTER TABLE public.pending_storage_deletions
    ALTER COLUMN prefixes SET NOT NULL,
    ALTER COLUMN phase SET NOT NULL,
    ALTER COLUMN phase SET DEFAULT 'sweep',
    ALTER COLUMN prefix_index SET NOT NULL,
    ALTER COLUMN prefix_index SET DEFAULT 1,
    ALTER COLUMN attempt_count SET NOT NULL,
    ALTER COLUMN attempt_count SET DEFAULT 0,
    ALTER COLUMN next_attempt_at SET NOT NULL,
    ALTER COLUMN next_attempt_at SET DEFAULT pg_catalog.NOW(),
    ALTER COLUMN verification_not_before SET NOT NULL,
    ALTER COLUMN verification_not_before
        SET DEFAULT (pg_catalog.NOW() + INTERVAL '25 hours'),
    ALTER COLUMN updated_at SET NOT NULL,
    ALTER COLUMN updated_at SET DEFAULT pg_catalog.NOW();

ALTER TABLE public.pending_storage_deletions
    DROP CONSTRAINT IF EXISTS pending_storage_deletions_status_check,
    ADD CONSTRAINT pending_storage_deletions_status_check
        CHECK (status IN ('pending', 'processing', 'completed')),
    DROP CONSTRAINT IF EXISTS pending_storage_deletions_phase_check,
    ADD CONSTRAINT pending_storage_deletions_phase_check
        CHECK (phase IN ('sweep', 'verification')),
    DROP CONSTRAINT IF EXISTS pending_storage_deletions_prefixes_check,
    ADD CONSTRAINT pending_storage_deletions_prefixes_check
        CHECK (
            pg_catalog.CARDINALITY(prefixes) = 5
            AND prefix_index BETWEEN 1 AND pg_catalog.CARDINALITY(prefixes)
        ),
    DROP CONSTRAINT IF EXISTS pending_storage_deletions_attempt_check,
    ADD CONSTRAINT pending_storage_deletions_attempt_check
        CHECK (attempt_count >= 0),
    DROP CONSTRAINT IF EXISTS pending_storage_deletions_claim_check,
    ADD CONSTRAINT pending_storage_deletions_claim_check
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
    DROP CONSTRAINT IF EXISTS pending_storage_deletions_terminal_check,
    ADD CONSTRAINT pending_storage_deletions_terminal_check
        CHECK (
            (
                status = 'completed'
                AND phase = 'verification'
                AND completed_at IS NOT NULL
                AND claim_token IS NULL
            )
            OR (
                status <> 'completed'
                AND completed_at IS NULL
            )
        ),
    DROP CONSTRAINT IF EXISTS pending_storage_deletions_error_check,
    ADD CONSTRAINT pending_storage_deletions_error_check
        CHECK (
            last_error_code IS NULL
            OR (
                pg_catalog.CHAR_LENGTH(last_error_code) BETWEEN 1 AND 120
                AND last_error_code !~ '[[:cntrl:]]'
            )
        );

COMMENT ON TABLE public.pending_storage_deletions IS
    'Private durable R2 erasure outbox. A terminal row proves a complete prefix sweep after every pre-deletion staging signature expired.';

REVOKE ALL ON TABLE public.pending_storage_deletions
    FROM PUBLIC, anon, authenticated, service_role;

DROP INDEX IF EXISTS public.pending_storage_deletions_status_idx;
CREATE INDEX pending_storage_deletions_due_idx
    ON public.pending_storage_deletions (
        next_attempt_at,
        created_at,
        id
    )
    WHERE status IN ('pending', 'processing');

CREATE OR REPLACE FUNCTION public.account_deletion_is_active(
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '2s'
AS $$
BEGIN
    PERFORM internal.require_service_role();
    RETURN EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.user_id = p_user_id
          AND deletion_job.status IN (
              'pending',
              'storage_pending',
              'auth_pending'
          )
    );
END;
$$;

COMMENT ON FUNCTION public.account_deletion_is_active(UUID) IS
    'Service-only upload fence used to prevent new presigned object writes after account-deletion intake.';

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
        WHERE deletion.status IN ('pending', 'processing')
          AND deletion.next_attempt_at <= pg_catalog.NOW()
          AND (
              deletion.claim_token IS NULL
              OR deletion.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP()
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
    'Service-only SKIP LOCKED lease claim for one bounded R2 prefix page per deletion.';

CREATE OR REPLACE FUNCTION public.advance_pending_storage_deletion(
    p_deletion_id UUID,
    p_claim_token UUID,
    p_last_key TEXT,
    p_prefix_finished BOOLEAN
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    deletion public.pending_storage_deletions%ROWTYPE;
    resulting_status TEXT;
BEGIN
    PERFORM internal.require_service_role();

    SELECT rows.*
    INTO deletion
    FROM public.pending_storage_deletions AS rows
    WHERE rows.id = p_deletion_id
      AND rows.claim_token = p_claim_token
    FOR UPDATE;

    IF NOT FOUND
       OR deletion.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP()
       OR deletion.status <> 'processing' THEN
        RAISE EXCEPTION 'storage_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_prefix_finished IS NOT TRUE
       AND (
           p_last_key IS NULL
           OR p_last_key <= deletion.prefixes[deletion.prefix_index]
           OR (
               deletion.start_after_key IS NOT NULL
               AND p_last_key <= deletion.start_after_key
           )
           OR pg_catalog.LEFT(
               p_last_key,
               pg_catalog.CHAR_LENGTH(
                   deletion.prefixes[deletion.prefix_index]
               )
           ) <> deletion.prefixes[deletion.prefix_index]
       ) THEN
        RAISE EXCEPTION 'storage_deletion_progress_invalid'
            USING ERRCODE = '22023';
    END IF;

    IF p_prefix_finished IS NOT TRUE THEN
        UPDATE public.pending_storage_deletions AS rows
        SET start_after_key = p_last_key,
            status = 'pending',
            next_attempt_at = pg_catalog.NOW(),
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE rows.id = deletion.id;
        resulting_status := 'pending';
    ELSIF deletion.prefix_index < pg_catalog.CARDINALITY(deletion.prefixes) THEN
        UPDATE public.pending_storage_deletions AS rows
        SET prefix_index = rows.prefix_index + 1,
            start_after_key = NULL,
            status = 'pending',
            next_attempt_at = pg_catalog.NOW(),
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE rows.id = deletion.id;
        resulting_status := 'pending';
    ELSIF deletion.phase = 'sweep' THEN
        UPDATE public.pending_storage_deletions AS rows
        SET phase = 'verification',
            prefix_index = 1,
            start_after_key = NULL,
            status = 'pending',
            next_attempt_at = GREATEST(
                pg_catalog.NOW(),
                rows.verification_not_before
            ),
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE rows.id = deletion.id;
        resulting_status := 'verifying';
    ELSE
        IF deletion.verification_not_before > pg_catalog.NOW() THEN
            RAISE EXCEPTION 'storage_deletion_verification_too_early'
                USING ERRCODE = '55000';
        END IF;

        UPDATE public.pending_storage_deletions AS rows
        SET status = 'completed',
            completed_at = pg_catalog.NOW(),
            claim_token = NULL,
            claimed_at = NULL,
            claim_expires_at = NULL,
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE rows.id = deletion.id;

        UPDATE internal.account_deletion_jobs AS deletion_job
        SET next_attempt_at = pg_catalog.NOW(),
            updated_at = pg_catalog.NOW()
        WHERE deletion_job.user_id = deletion.target_user_id
          AND deletion_job.status = 'storage_pending';
        resulting_status := 'completed';
    END IF;

    RETURN resulting_status;
END;
$$;

COMMENT ON FUNCTION public.advance_pending_storage_deletion(
    UUID,
    UUID,
    TEXT,
    BOOLEAN
) IS
    'Service-only claim-fenced prefix cursor advancement. Completion is possible only after the delayed verification pass.';

CREATE OR REPLACE FUNCTION public.fail_pending_storage_deletion(
    p_deletion_id UUID,
    p_claim_token UUID,
    p_error_code TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    changed BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    UPDATE public.pending_storage_deletions AS deletion
    SET status = 'pending',
        next_attempt_at = pg_catalog.NOW() + CASE
            WHEN deletion.attempt_count <= 1 THEN INTERVAL '1 minute'
            WHEN deletion.attempt_count = 2 THEN INTERVAL '2 minutes'
            WHEN deletion.attempt_count = 3 THEN INTERVAL '5 minutes'
            WHEN deletion.attempt_count = 4 THEN INTERVAL '15 minutes'
            ELSE INTERVAL '1 hour'
        END,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = pg_catalog.LEFT(
            COALESCE(NULLIF(pg_catalog.BTRIM(p_error_code), ''), 'r2_failed'),
            120
        ),
        updated_at = pg_catalog.NOW()
    WHERE deletion.id = p_deletion_id
      AND deletion.claim_token = p_claim_token
      AND deletion.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()
      AND deletion.status = 'processing'
    RETURNING TRUE INTO changed;

    RETURN changed IS TRUE;
END;
$$;

COMMENT ON FUNCTION public.fail_pending_storage_deletion(UUID, UUID, TEXT) IS
    'Service-only claim-fenced bounded-backoff release for transient R2 erasure failures.';

-- Introduce the required storage phase and upgrade any active auth_pending row
-- from an older worker according to its actual outbox state.
ALTER TABLE internal.account_deletion_jobs
    ADD COLUMN IF NOT EXISTS storage_completed_at TIMESTAMPTZ;

ALTER TABLE internal.account_deletion_jobs
    DROP CONSTRAINT IF EXISTS account_deletion_jobs_status_check,
    DROP CONSTRAINT IF EXISTS account_deletion_jobs_state_check;

UPDATE internal.account_deletion_jobs AS deletion_job
SET status = CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.pending_storage_deletions AS storage
            WHERE storage.target_user_id = deletion_job.user_id
              AND storage.status = 'completed'
        ) THEN 'auth_pending'
        ELSE 'storage_pending'
    END,
    storage_completed_at = CASE
        WHEN EXISTS (
            SELECT 1
            FROM public.pending_storage_deletions AS storage
            WHERE storage.target_user_id = deletion_job.user_id
              AND storage.status = 'completed'
        ) THEN COALESCE(
            deletion_job.storage_completed_at,
            pg_catalog.NOW()
        )
        ELSE NULL
    END
WHERE deletion_job.status = 'auth_pending';

ALTER TABLE internal.account_deletion_jobs
    ADD CONSTRAINT account_deletion_jobs_status_check
        CHECK (
            status IN (
                'pending',
                'storage_pending',
                'auth_pending',
                'completed'
            )
        ),
    ADD CONSTRAINT account_deletion_jobs_state_check
        CHECK (
            (
                status = 'pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NULL
                AND storage_completed_at IS NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'storage_pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NOT NULL
                AND storage_completed_at IS NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'auth_pending'
                AND user_id IS NOT NULL
                AND cleanup_completed_at IS NOT NULL
                AND storage_completed_at IS NOT NULL
                AND auth_deleted_at IS NULL
                AND completed_at IS NULL
            )
            OR (
                status = 'completed'
                AND user_id IS NULL
                AND cleanup_completed_at IS NOT NULL
                AND storage_completed_at IS NOT NULL
                AND auth_deleted_at IS NOT NULL
                AND completed_at IS NOT NULL
                AND claim_token IS NULL
                AND claimed_at IS NULL
                AND claim_expires_at IS NULL
                AND last_error_code IS NULL
            )
        );

DROP INDEX IF EXISTS internal.account_deletion_jobs_due_idx;
CREATE INDEX account_deletion_jobs_due_idx
    ON internal.account_deletion_jobs (
        next_attempt_at,
        requested_at,
        id
    )
    WHERE status IN ('pending', 'storage_pending', 'auth_pending');

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
             AND deletion_job.status IN (
                 'pending',
                 'storage_pending',
                 'auth_pending'
             )
       ) THEN
        RAISE EXCEPTION 'account_deletion_in_progress'
            USING ERRCODE = '55000';
    END IF;

    RETURN NEW;
END;
$$;

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

    RETURN QUERY
    WITH candidates AS (
        SELECT deletion_job.id
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.status IN (
            'pending',
            'storage_pending',
            'auth_pending'
        )
          AND deletion_job.user_id IS NOT NULL
          AND deletion_job.next_attempt_at <= pg_catalog.NOW()
          AND (
              deletion_job.claim_token IS NULL
              OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP()
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
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100)
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

DROP FUNCTION public.complete_account_deletion_cleanup(UUID, UUID);
CREATE FUNCTION public.complete_account_deletion_cleanup(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    storage_status TEXT;
BEGIN
    PERFORM internal.require_service_role();

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

    IF deletion_job.status NOT IN (
        'pending',
        'storage_pending',
        'auth_pending'
    )
       OR deletion_job.user_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_invalid_state'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.pending_storage_deletions AS existing_deletion (
        target_user_id,
        status,
        prefixes,
        phase,
        prefix_index,
        next_attempt_at,
        verification_not_before,
        updated_at
    )
    VALUES (
        deletion_job.user_id,
        'pending',
        ARRAY[
            'public_uploads/free/' || deletion_job.user_id::TEXT || '/',
            'public_uploads/pro/' || deletion_job.user_id::TEXT || '/',
            'staging/' || deletion_job.user_id::TEXT || '/',
            'avatars/' || deletion_job.user_id::TEXT || '/',
            'exports/' || deletion_job.user_id::TEXT || '/'
        ]::TEXT[],
        'sweep',
        1,
        pg_catalog.NOW(),
        pg_catalog.NOW() + INTERVAL '25 hours',
        pg_catalog.NOW()
    )
    ON CONFLICT (target_user_id) DO NOTHING;

    PERFORM public.apply_user_tombstone(deletion_job.user_id);

    IF EXISTS (
        SELECT 1
        FROM public.users AS users
        WHERE users.id = deletion_job.user_id
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.user_id = deletion_job.user_id
    ) THEN
        RAISE EXCEPTION 'account_deletion_cleanup_verification_failed'
            USING ERRCODE = 'P0004';
    END IF;

    SELECT storage.status
    INTO storage_status
    FROM public.pending_storage_deletions AS storage
    WHERE storage.target_user_id = deletion_job.user_id
    FOR UPDATE;

    IF storage_status = 'completed' THEN
        UPDATE internal.account_deletion_jobs AS jobs
        SET status = 'auth_pending',
            cleanup_completed_at = COALESCE(
                jobs.cleanup_completed_at,
                pg_catalog.NOW()
            ),
            storage_completed_at = COALESCE(
                jobs.storage_completed_at,
                pg_catalog.NOW()
            ),
            next_attempt_at = pg_catalog.NOW(),
            last_error_code = NULL,
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;
        RETURN 'auth_pending';
    END IF;

    UPDATE internal.account_deletion_jobs AS jobs
    SET status = 'storage_pending',
        cleanup_completed_at = COALESCE(
            jobs.cleanup_completed_at,
            pg_catalog.NOW()
        ),
        storage_completed_at = NULL,
        next_attempt_at = pg_catalog.NOW() + INTERVAL '5 minutes',
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE jobs.id = deletion_job.id
      AND jobs.claim_token = p_claim_token;

    RETURN 'storage_pending';
END;
$$;

COMMENT ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID) IS
    'Service-only claimed relational cleanup. It returns storage_pending and releases the lease until verified R2 erasure permits auth_pending.';

CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF target_user_id IS NULL
       OR target_user_id =
            '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.scans AS scans
    SET user_id = NULL,
        is_tombstoned = TRUE,
        image_storage_urls = ARRAY[]::TEXT[],
        video_storage_urls = ARRAY[]::TEXT[],
        audio_storage_urls = ARRAY[]::TEXT[],
        captured_media = NULL,
        gps_lat_exact = NULL,
        gps_long_exact = NULL,
        gps_elevation = NULL,
        semantic_location = NULL,
        device_locale = NULL,
        device_time_zone = NULL,
        user_observation_context = NULL,
        custom_tags = ARRAY[]::TEXT[],
        human_intervention_notes = NULL
    WHERE scans.user_id = target_user_id;

    DELETE FROM public.users AS users
    WHERE users.id = target_user_id;
END;
$$;

COMMENT ON FUNCTION public.apply_user_tombstone(UUID) IS
    'Service-only relational anonymization. Retained ownerless scans contain no deleted-user media URLs while the durable R2 prefix eraser runs.';

-- Converge account deletions completed by the earlier bundle. Those rows are
-- already ownerless, so they cannot be reached by the target-user update in
-- the replacement routine above. Their outbox rows were reset to a real sweep
-- at the start of this migration; remove retained URL and free-form identity
-- surfaces before trusted exports can observe them.
UPDATE public.scans AS scans
SET image_storage_urls = ARRAY[]::TEXT[],
    video_storage_urls = ARRAY[]::TEXT[],
    audio_storage_urls = ARRAY[]::TEXT[],
    captured_media = NULL,
    gps_lat_exact = NULL,
    gps_long_exact = NULL,
    gps_elevation = NULL,
    semantic_location = NULL,
    device_locale = NULL,
    device_time_zone = NULL,
    user_observation_context = NULL,
    custom_tags = ARRAY[]::TEXT[],
    human_intervention_notes = NULL
WHERE scans.user_id IS NULL
  AND scans.is_tombstoned IS TRUE
  AND (
      pg_catalog.CARDINALITY(scans.image_storage_urls) > 0
      OR pg_catalog.CARDINALITY(scans.video_storage_urls) > 0
      OR pg_catalog.CARDINALITY(scans.audio_storage_urls) > 0
      OR scans.captured_media IS NOT NULL
      OR scans.gps_lat_exact IS NOT NULL
      OR scans.gps_long_exact IS NOT NULL
      OR scans.gps_elevation IS NOT NULL
      OR scans.semantic_location IS NOT NULL
      OR scans.device_locale IS NOT NULL
      OR scans.device_time_zone IS NOT NULL
      OR scans.user_observation_context IS NOT NULL
      OR pg_catalog.CARDINALITY(scans.custom_tags) > 0
      OR scans.human_intervention_notes IS NOT NULL
  );

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

    IF p_auth_deleted IS NULL THEN
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
    IF deletion_job.status = 'completed' AND p_auth_deleted IS TRUE THEN
        RETURN;
    END IF;
    IF deletion_job.claim_token IS NULL
       OR deletion_job.claim_token <> p_claim_token
       OR deletion_job.claim_expires_at <= pg_catalog.CLOCK_TIMESTAMP() THEN
        RAISE EXCEPTION 'account_deletion_claim_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF p_auth_deleted IS TRUE THEN
        IF deletion_job.status <> 'auth_pending'
           OR deletion_job.storage_completed_at IS NULL
           OR NOT EXISTS (
               SELECT 1
               FROM public.pending_storage_deletions AS storage
               WHERE storage.target_user_id = deletion_job.user_id
                 AND storage.status = 'completed'
                 AND storage.completed_at IS NOT NULL
           ) THEN
            RAISE EXCEPTION 'account_deletion_storage_required'
                USING ERRCODE = '55000';
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
                    NULLIF(pg_catalog.BTRIM(p_error_code), ''),
                    'retryable_failure'
                ),
                120
            ),
            updated_at = pg_catalog.NOW()
        WHERE jobs.id = deletion_job.id
          AND jobs.claim_token = p_claim_token;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.account_deletion_is_active(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_pending_storage_deletions(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.advance_pending_storage_deletion(
    UUID,
    UUID,
    TEXT,
    BOOLEAN
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fail_pending_storage_deletion(UUID, UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_account_deletion_jobs(INTEGER, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.finish_account_deletion_attempt(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.account_deletion_is_active(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_pending_storage_deletions(INTEGER)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.advance_pending_storage_deletion(
    UUID,
    UUID,
    TEXT,
    BOOLEAN
) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_pending_storage_deletion(UUID, UUID, TEXT)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_account_deletion_jobs(INTEGER, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_account_deletion_cleanup(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_account_deletion_attempt(
    UUID,
    UUID,
    BOOLEAN,
    TEXT
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.account_deletion_is_active(uuid)',
        'Blocks new signed media writes while deletion is active.'
    ),
    (
        'service_role',
        'public.claim_pending_storage_deletions(integer)',
        'Leases bounded R2 erasure pages.'
    ),
    (
        'service_role',
        'public.advance_pending_storage_deletion(uuid,uuid,text,boolean)',
        'Advances claim-fenced R2 prefix deletion cursors.'
    ),
    (
        'service_role',
        'public.fail_pending_storage_deletion(uuid,uuid,text)',
        'Releases failed R2 erasure leases with bounded backoff.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

COMMIT;
