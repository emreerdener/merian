-- Make Darwin Core export execution canonical, leased, and bounded.
--
-- The hardened worker treats only the opaque webhook job id as authority. A
-- service-only RPC locks that row, loads its immutable request fields, and
-- installs a private fencing token. Every later state transition must present
-- the same token, so a delayed worker cannot complete or fail a newer attempt.

ALTER TABLE public.export_jobs
    ADD COLUMN IF NOT EXISTS pseudonym_key_version SMALLINT NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS archive_object_key TEXT,
    ADD COLUMN IF NOT EXISTS archive_ready_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS failure_code TEXT;

ALTER TABLE public.export_jobs
    ALTER COLUMN include_precise_coordinates SET DEFAULT FALSE;

UPDATE public.export_jobs
SET export_scope = 'personal'
WHERE export_scope NOT IN ('personal', 'global');

UPDATE public.export_jobs
SET error_message = pg_catalog.LEFT(error_message, 500)
WHERE pg_catalog.CHAR_LENGTH(error_message) > 500;

-- Do not invalidate a pre-deploy worker already processing a row. Migrations
-- land before Edge bundles, so the transition trigger below permits an
-- unleased service worker to finish during the bounded rollout window. New
-- workers always install a claim before processing.

ALTER TABLE public.export_jobs
    DROP CONSTRAINT IF EXISTS export_jobs_scope_check,
    ADD CONSTRAINT export_jobs_scope_check
        CHECK (export_scope IN ('personal', 'global')),
    DROP CONSTRAINT IF EXISTS export_jobs_pseudonym_key_version_check,
    ADD CONSTRAINT export_jobs_pseudonym_key_version_check
        CHECK (pseudonym_key_version BETWEEN 1 AND 1000),
    DROP CONSTRAINT IF EXISTS export_jobs_archive_object_key_check,
    ADD CONSTRAINT export_jobs_archive_object_key_check
        CHECK (
            archive_object_key IS NULL
            OR (
                pg_catalog.CHAR_LENGTH(archive_object_key) BETWEEN 1 AND 512
                AND archive_object_key !~ '[[:cntrl:]]'
                AND archive_object_key NOT LIKE '%..%'
            )
        ),
    DROP CONSTRAINT IF EXISTS export_jobs_file_url_length_check,
    ADD CONSTRAINT export_jobs_file_url_length_check
        CHECK (
            file_url IS NULL
            OR pg_catalog.CHAR_LENGTH(file_url) BETWEEN 1 AND 4096
        ),
    DROP CONSTRAINT IF EXISTS export_jobs_failure_code_check,
    ADD CONSTRAINT export_jobs_failure_code_check
        CHECK (
            failure_code IS NULL
            OR failure_code ~ '^[a-z][a-z0-9_]{1,63}$'
        ),
    DROP CONSTRAINT IF EXISTS export_jobs_error_message_length_check,
    ADD CONSTRAINT export_jobs_error_message_length_check
        CHECK (
            error_message IS NULL
            OR pg_catalog.CHAR_LENGTH(error_message) <= 500
        );

COMMENT ON COLUMN public.export_jobs.pseudonym_key_version IS
    'Immutable version selecting DWCA_PSEUDONYM_HMAC_KEY_V{n}; rotate by provisioning the next secret before changing this column default in a migration.';
COMMENT ON COLUMN public.export_jobs.archive_object_key IS
    'Attempt-fenced R2 key staged by the currently fenced worker before delivery.';
COMMENT ON COLUMN public.export_jobs.archive_ready_at IS
    'Time the winning archive and its reusable signed delivery URL were durably staged.';
COMMENT ON COLUMN public.export_jobs.failure_code IS
    'Stable public-safe failure classification; provider and implementation details remain in structured Edge logs only.';

CREATE TABLE internal.export_job_claims (
    job_id UUID PRIMARY KEY
        REFERENCES public.export_jobs(id) ON DELETE CASCADE,
    claim_token UUID NOT NULL,
    lease_expires_at TIMESTAMPTZ NOT NULL,
    claimed_at TIMESTAMPTZ NOT NULL,
    heartbeat_at TIMESTAMPTZ NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT export_job_claims_attempt_count_check
        CHECK (attempt_count BETWEEN 1 AND 100)
);

-- The production workflow applies migrations before Edge bundles. Preserve the
-- old payload shape only for jobs created during this finite deployment
-- cohort. Once the deadline passes, newly queued jobs receive job_id only and
-- cannot transition to processing without a private claim. The cohort remains
-- eligible to finish if an old worker was already started near the deadline.
CREATE TABLE internal.export_worker_protocol (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE,
    legacy_payload_until TIMESTAMPTZ NOT NULL,
    CONSTRAINT export_worker_protocol_singleton_check
        CHECK (singleton)
);

INSERT INTO internal.export_worker_protocol (
    singleton,
    legacy_payload_until
)
VALUES (
    TRUE,
    pg_catalog.NOW() + INTERVAL '2 hours'
);

CREATE INDEX export_job_claims_expired_lease_idx
    ON internal.export_job_claims (lease_expires_at, job_id);

CREATE INDEX IF NOT EXISTS idx_export_jobs_user_recent_success
    ON public.export_jobs (user_id, created_at DESC)
    WHERE status <> 'failed';

ALTER TABLE internal.export_job_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.export_worker_protocol ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.export_job_claims
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE internal.export_worker_protocol
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.export_job_claims IS
    'Private fencing-token and lease state for Darwin Core export workers. API roles can mutate it only through reviewed service-role RPCs.';
COMMENT ON TABLE internal.export_worker_protocol IS
    'Private rollout protocol state. The one-time legacy payload deadline bounds migration-before-bundle compatibility to a finite job cohort.';

-- These partial indexes make every page an index-backed UUID keyset scan.
-- Migration-pipeline replay does not support CREATE INDEX CONCURRENTLY.
CREATE INDEX IF NOT EXISTS idx_scans_dwca_personal_keyset
    ON public.scans (user_id, id)
    WHERE is_live_capture = TRUE
      AND ecology_type <> 'domesticated';

CREATE INDEX IF NOT EXISTS idx_scans_dwca_global_keyset
    ON public.scans (id)
    WHERE is_live_capture = TRUE
      AND ecology_type <> 'domesticated'
      AND geoprivacy = 'open';

-- The authenticated Data API does not own queue insertion. All requests pass
-- through request-export-dwca, which authenticates the caller and applies the
-- rate limit before inserting with the service client.
DROP POLICY IF EXISTS "Users can insert their own export jobs."
    ON public.export_jobs;
REVOKE INSERT ON TABLE public.export_jobs FROM anon, authenticated;

CREATE OR REPLACE FUNCTION internal.enforce_export_job_update()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    has_claim BOOLEAN;
    legacy_payload_until TIMESTAMPTZ;
    legacy_worker_eligible BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM internal.export_job_claims AS claims
        WHERE claims.job_id = OLD.id
    )
    INTO has_claim;

    SELECT protocol.legacy_payload_until
    INTO legacy_payload_until
    FROM internal.export_worker_protocol AS protocol
    WHERE protocol.singleton;

    legacy_worker_eligible :=
        NOT has_claim
        AND COALESCE(OLD.created_at <= legacy_payload_until, FALSE);

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.export_scope IS DISTINCT FROM OLD.export_scope
       OR NEW.include_precise_coordinates
            IS DISTINCT FROM OLD.include_precise_coordinates
       OR NEW.pseudonym_key_version
            IS DISTINCT FROM OLD.pseudonym_key_version
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'export_job_request_is_immutable'
            USING ERRCODE = '22023';
    END IF;

    -- Account merging may reparent historical jobs. A processing job must
    -- become terminal first so its old owner/token can no longer publish.
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       AND OLD.status IN ('pending', 'processing') THEN
        NEW.status := 'failed';
        NEW.failure_code := 'owner_changed';
        NEW.error_message :=
            'Export ownership changed while processing. Please request a new export.';
        NEW.file_url := NULL;
        NEW.archive_object_key := NULL;
        NEW.archive_ready_at := NULL;
        NEW.completed_at := pg_catalog.NOW();
    END IF;

    IF OLD.status = 'pending'
       AND NEW.status NOT IN ('pending', 'processing', 'failed') THEN
        RAISE EXCEPTION 'invalid_export_job_status_transition'
            USING ERRCODE = '22023';
    ELSIF OLD.status = 'processing'
       AND NEW.status NOT IN ('processing', 'completed', 'failed') THEN
        RAISE EXCEPTION 'invalid_export_job_status_transition'
            USING ERRCODE = '22023';
    ELSIF OLD.status IN ('completed', 'failed')
       AND (
           NEW.status IS DISTINCT FROM OLD.status
           OR NEW.file_url IS DISTINCT FROM OLD.file_url
           OR NEW.archive_object_key IS DISTINCT FROM OLD.archive_object_key
           OR NEW.archive_ready_at IS DISTINCT FROM OLD.archive_ready_at
           OR NEW.failure_code IS DISTINCT FROM OLD.failure_code
           OR NEW.error_message IS DISTINCT FROM OLD.error_message
           OR NEW.completed_at IS DISTINCT FROM OLD.completed_at
       ) THEN
        RAISE EXCEPTION 'terminal_export_job_is_immutable'
            USING ERRCODE = '22023';
    END IF;

    IF OLD.status = 'pending'
       AND NEW.status = 'processing'
       AND NOT has_claim
       AND NOT legacy_worker_eligible THEN
        RAISE EXCEPTION 'export_job_claim_required'
            USING ERRCODE = '55000';
    END IF;

    IF OLD.status = 'processing'
       AND has_claim
       AND NEW.status = 'processing'
       AND NEW.file_url IS NOT DISTINCT FROM OLD.file_url
       AND NEW.archive_object_key IS NOT DISTINCT FROM OLD.archive_object_key
       AND NEW.archive_ready_at IS NOT DISTINCT FROM OLD.archive_ready_at
       AND NEW.failure_code IS NOT DISTINCT FROM OLD.failure_code
       AND NEW.error_message IS NOT DISTINCT FROM OLD.error_message
       AND NEW.completed_at IS NOT DISTINCT FROM OLD.completed_at THEN
        RAISE EXCEPTION 'claimed_export_job_already_owned'
            USING ERRCODE = '55000';
    END IF;

    -- A previous bundle can still be in flight when the hardened bundle
    -- claims its pending row. Once a claim exists, that old worker may not
    -- replace the staged archive or fail the newer attempt with raw text.
    IF OLD.status = 'processing'
       AND has_claim
       AND NEW.status = 'completed'
       AND (
           NEW.file_url IS DISTINCT FROM OLD.file_url
           OR NEW.archive_object_key IS DISTINCT FROM OLD.archive_object_key
           OR NEW.archive_ready_at IS DISTINCT FROM OLD.archive_ready_at
       ) THEN
        RAISE EXCEPTION 'claimed_export_job_result_requires_rpc'
            USING ERRCODE = '55000';
    END IF;

    IF OLD.status = 'processing'
       AND has_claim
       AND NEW.status = 'failed'
       AND NEW.failure_code IS NULL THEN
        -- The atomic ghost-profile merge predates failure_code and uses this
        -- exact owner-safe marker when two active export rows converge.
        IF NEW.error_message = 'Superseded during account merge' THEN
            NEW.failure_code := 'owner_changed';
        ELSE
            RAISE EXCEPTION 'claimed_export_job_failure_requires_rpc'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF NEW.status = 'pending' THEN
        NEW.file_url := NULL;
        NEW.archive_object_key := NULL;
        NEW.archive_ready_at := NULL;
        NEW.failure_code := NULL;
        NEW.error_message := NULL;
        NEW.completed_at := NULL;
    ELSIF NEW.status = 'processing' THEN
        NEW.failure_code := NULL;
        NEW.error_message := NULL;
        NEW.completed_at := NULL;
    ELSIF NEW.status = 'completed' THEN
        IF OLD.status IS DISTINCT FROM 'completed'
           AND (
               NEW.file_url IS NULL
               OR NEW.archive_object_key IS NULL
               OR NEW.archive_ready_at IS NULL
           )
           AND NOT legacy_worker_eligible THEN
            RAISE EXCEPTION 'completed_export_job_requires_archive'
                USING ERRCODE = '23514';
        END IF;
        NEW.failure_code := NULL;
        NEW.error_message := NULL;
        NEW.completed_at := COALESCE(NEW.completed_at, pg_catalog.NOW());
    ELSE
        NEW.failure_code := COALESCE(NEW.failure_code, 'export_failed');
        -- Never persist provider or implementation details supplied by a
        -- rollout-era worker. This column is readable by the job owner.
        NEW.error_message := CASE NEW.failure_code
            WHEN 'owner_changed' THEN
                'Export ownership changed while processing. Please request a new export.'
            WHEN 'pseudonym_key_unavailable' THEN
                'Export security configuration is unavailable. Please retry later.'
            WHEN 'export_too_large' THEN
                'This export is too large for the current worker. Please contact support.'
            WHEN 'worker_lease_expired' THEN
                'Export processing timed out before completion. Please retry.'
            ELSE
                'Export processing failed. Please retry.'
        END;
        NEW.file_url := NULL;
        NEW.archive_object_key := NULL;
        NEW.archive_ready_at := NULL;
        NEW.completed_at := COALESCE(NEW.completed_at, pg_catalog.NOW());
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_export_job_update()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS enforce_export_job_update ON public.export_jobs;
CREATE TRIGGER enforce_export_job_update
BEFORE UPDATE ON public.export_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_export_job_update();

CREATE OR REPLACE FUNCTION public.claim_export_job(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TABLE(
    job_id UUID,
    user_id UUID,
    export_scope TEXT,
    include_precise_coordinates BOOLEAN,
    pseudonym_key_version SMALLINT,
    archive_object_key TEXT,
    file_url TEXT,
    archive_ready_at TIMESTAMPTZ,
    attempt_count INTEGER,
    lease_expires_at TIMESTAMPTZ
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    job_row public.export_jobs%ROWTYPE;
    claim_row internal.export_job_claims%ROWTYPE;
    legacy_payload_until TIMESTAMPTZ;
    lease_duration CONSTANT INTERVAL := INTERVAL '10 minutes';
BEGIN
    PERFORM internal.require_service_role();

    IF p_job_id IS NULL
       OR p_claim_token IS NULL
       OR p_claim_token =
            '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'invalid_export_job_claim'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.*
    INTO job_row
    FROM public.export_jobs AS jobs
    WHERE jobs.id = p_job_id
    FOR UPDATE OF jobs;

    IF NOT FOUND OR job_row.status IN ('completed', 'failed') THEN
        RETURN;
    END IF;

    SELECT claims.*
    INTO claim_row
    FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id;

    SELECT protocol.legacy_payload_until
    INTO legacy_payload_until
    FROM internal.export_worker_protocol AS protocol
    WHERE protocol.singleton;

    IF job_row.status = 'processing' THEN
        IF claim_row.job_id IS NOT NULL
           AND claim_row.lease_expires_at > pg_catalog.NOW() THEN
            RETURN;
        END IF;

        -- A rollout-era worker marks processing without a claim. Never recover
        -- that row into the new protocol: the previous bundle did not observe
        -- update failures reliably and could continue provider side effects.
        -- The watchdog fails the unclaimed row after 30 minutes instead.
        IF claim_row.job_id IS NULL
           AND COALESCE(
               job_row.created_at <= legacy_payload_until,
               FALSE
           ) THEN
            RETURN;
        END IF;
    END IF;

    INSERT INTO internal.export_job_claims AS claims (
        job_id,
        claim_token,
        lease_expires_at,
        claimed_at,
        heartbeat_at,
        attempt_count
    )
    VALUES (
        p_job_id,
        p_claim_token,
        pg_catalog.NOW() + lease_duration,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        1
    )
    ON CONFLICT ON CONSTRAINT export_job_claims_pkey DO UPDATE
    SET claim_token = EXCLUDED.claim_token,
        lease_expires_at = EXCLUDED.lease_expires_at,
        claimed_at = EXCLUDED.claimed_at,
        heartbeat_at = EXCLUDED.heartbeat_at,
        attempt_count = LEAST(claims.attempt_count + 1, 100)
    RETURNING claims.*
    INTO STRICT claim_row;

    -- Install the claim before transitioning the public row. The update
    -- trigger therefore rejects direct post-rollout processing while allowing
    -- this atomic transaction to proceed; any later error rolls both back.
    IF job_row.status = 'pending' THEN
        UPDATE public.export_jobs AS jobs
        SET status = 'processing',
            failure_code = NULL,
            error_message = NULL,
            completed_at = NULL
        WHERE jobs.id = p_job_id;
    END IF;

    RETURN QUERY
    SELECT
        job_row.id,
        job_row.user_id,
        job_row.export_scope,
        job_row.include_precise_coordinates,
        job_row.pseudonym_key_version,
        job_row.archive_object_key,
        job_row.file_url,
        job_row.archive_ready_at,
        claim_row.attempt_count,
        claim_row.lease_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.renew_export_job_claim(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    UPDATE internal.export_job_claims AS claims
    SET lease_expires_at = pg_catalog.NOW() + INTERVAL '10 minutes',
        heartbeat_at = pg_catalog.NOW()
    FROM public.export_jobs AS jobs
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
      AND jobs.id = claims.job_id
      AND jobs.status = 'processing';

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN affected_rows = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.stage_export_job_archive(
    p_job_id UUID,
    p_claim_token UUID,
    p_archive_object_key TEXT,
    p_file_url TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    affected_rows INTEGER;
    expected_object_key TEXT;
BEGIN
    PERFORM internal.require_service_role();

    SELECT
        'exports/' || jobs.user_id::TEXT || '/' || jobs.id::TEXT || '/'
            || p_claim_token::TEXT || '.zip'
    INTO expected_object_key
    FROM public.export_jobs AS jobs
    WHERE jobs.id = p_job_id;

    IF expected_object_key IS NULL
       OR p_archive_object_key IS DISTINCT FROM expected_object_key
       OR p_file_url IS NULL
       OR pg_catalog.CHAR_LENGTH(p_file_url) NOT BETWEEN 1 AND 4096
       OR p_file_url !~ '^https://' THEN
        RAISE EXCEPTION 'invalid_export_archive'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.export_jobs AS jobs
    SET archive_object_key = p_archive_object_key,
        file_url = p_file_url,
        archive_ready_at = pg_catalog.NOW()
    FROM internal.export_job_claims AS claims
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.job_id = jobs.id
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW();

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN affected_rows = 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_export_job(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    UPDATE public.export_jobs AS jobs
    SET status = 'completed',
        completed_at = pg_catalog.NOW()
    FROM internal.export_job_claims AS claims
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND jobs.file_url IS NOT NULL
      AND jobs.archive_object_key IS NOT NULL
      AND jobs.archive_ready_at IS NOT NULL
      AND claims.job_id = jobs.id
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW();

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows = 1 THEN
        RETURN TRUE;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.export_jobs AS jobs
        JOIN internal.export_job_claims AS claims
          ON claims.job_id = jobs.id
        WHERE jobs.id = p_job_id
          AND jobs.status = 'completed'
          AND claims.claim_token = p_claim_token
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_export_job(
    p_job_id UUID,
    p_claim_token UUID,
    p_failure_code TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_failure_code IS NULL
       OR p_failure_code !~ '^[a-z][a-z0-9_]{1,63}$' THEN
        RAISE EXCEPTION 'invalid_export_failure_code'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.export_jobs AS jobs
    SET status = 'failed',
        failure_code = p_failure_code,
        error_message = CASE p_failure_code
            WHEN 'pseudonym_key_unavailable' THEN
                'Export security configuration is unavailable. Please retry later.'
            WHEN 'export_too_large' THEN
                'This export is too large for the current worker. Please contact support.'
            ELSE
                'Export processing failed. Please retry.'
        END,
        completed_at = pg_catalog.NOW()
    FROM internal.export_job_claims AS claims
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.job_id = jobs.id
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW();

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN affected_rows = 1;
END;
$$;

COMMENT ON FUNCTION public.claim_export_job(UUID, UUID) IS
    'Atomically claims one canonical pending or lease-expired DwC-A job and returns immutable request state to the service worker.';
COMMENT ON FUNCTION public.renew_export_job_claim(UUID, UUID) IS
    'Extends a DwC-A worker lease only when the private fencing token still owns the processing job.';
COMMENT ON FUNCTION public.stage_export_job_archive(UUID, UUID, TEXT, TEXT) IS
    'Stages the attempt-fenced R2 object and delivery URL under the current DwC-A fencing token.';
COMMENT ON FUNCTION public.complete_export_job(UUID, UUID) IS
    'Completes a staged DwC-A job only under its current fencing token.';
COMMENT ON FUNCTION public.fail_export_job(UUID, UUID, TEXT) IS
    'Fails a DwC-A job under its current fencing token using a stable public-safe failure code.';

REVOKE ALL ON FUNCTION public.claim_export_job(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.renew_export_job_claim(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.stage_export_job_archive(
    UUID,
    UUID,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_export_job(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fail_export_job(UUID, UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.claim_export_job(uuid,uuid)',
        'DwC-A worker canonical job claim and fencing RPC.'
    ),
    (
        'service_role',
        'public.renew_export_job_claim(uuid,uuid)',
        'DwC-A worker lease renewal RPC.'
    ),
    (
        'service_role',
        'public.stage_export_job_archive(uuid,uuid,text,text)',
        'DwC-A worker attempt-fenced archive staging RPC.'
    ),
    (
        'service_role',
        'public.complete_export_job(uuid,uuid)',
        'DwC-A worker fenced completion RPC.'
    ),
    (
        'service_role',
        'public.fail_export_job(uuid,uuid,text)',
        'DwC-A worker fenced failure RPC.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

GRANT EXECUTE ON FUNCTION public.claim_export_job(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.renew_export_job_claim(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.stage_export_job_archive(
    UUID,
    UUID,
    TEXT,
    TEXT
) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_export_job(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_export_job(UUID, UUID, TEXT)
    TO service_role;

-- The webhook is a wake-up signal, not a source of job authority.
CREATE OR REPLACE FUNCTION public.trigger_export_dwca_webhook()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    project_url TEXT;
    service_role_key TEXT;
    legacy_payload_until TIMESTAMPTZ;
    webhook_body JSONB;
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

    project_url := COALESCE(
        project_url,
        pg_catalog.CURRENT_SETTING('app.settings.supabase_url', TRUE)
    );
    service_role_key := COALESCE(
        service_role_key,
        pg_catalog.CURRENT_SETTING('app.settings.service_role_key', TRUE)
    );

    -- Local schema tests and incident maintenance may not configure Vault.
    -- Leave the canonical row pending; the operator can safely redeliver its
    -- job id after credentials are restored.
    IF NULLIF(pg_catalog.BTRIM(project_url), '') IS NULL
       OR NULLIF(pg_catalog.BTRIM(service_role_key), '') IS NULL THEN
        RAISE WARNING
            'DwC-A job % was queued without configured webhook credentials',
            NEW.id;
        RETURN NEW;
    END IF;

    SELECT protocol.legacy_payload_until
    INTO legacy_payload_until
    FROM internal.export_worker_protocol AS protocol
    WHERE protocol.singleton;

    webhook_body := pg_catalog.JSONB_BUILD_OBJECT('job_id', NEW.id);
    IF COALESCE(NEW.created_at <= legacy_payload_until, FALSE) THEN
        webhook_body := webhook_body || pg_catalog.JSONB_BUILD_OBJECT(
            'user_id',
            NEW.user_id,
            'export_scope',
            NEW.export_scope,
            'include_precise_coordinates',
            NEW.include_precise_coordinates
        );
    END IF;

    PERFORM net.http_post(
        url := project_url || '/functions/v1/export-dwca',
        headers := pg_catalog.JSONB_BUILD_OBJECT(
            'Content-Type',
            'application/json',
            'Authorization',
            'Bearer ' || service_role_key
        ),
        -- The deployed worker reads only job_id and reloads all authority from
        -- the locked row. Canonical row-derived hints exist only for the
        -- finite migration-before-bundle cohort selected above.
        body := webhook_body
    );

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trigger_export_dwca_webhook()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS on_export_job_created ON public.export_jobs;
CREATE TRIGGER on_export_job_created
AFTER INSERT ON public.export_jobs
FOR EACH ROW
WHEN (NEW.status = 'pending')
EXECUTE FUNCTION public.trigger_export_dwca_webhook();

CREATE OR REPLACE FUNCTION public.expire_stuck_export_jobs()
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    UPDATE public.export_jobs AS jobs
    SET status = 'failed',
        failure_code = 'worker_lease_expired',
        error_message =
            'Export processing timed out before completion. Please retry.',
        completed_at = pg_catalog.NOW()
    WHERE (
        jobs.status = 'pending'
        AND jobs.created_at < pg_catalog.NOW() - INTERVAL '30 minutes'
    ) OR (
        jobs.status = 'processing'
        AND (
            (
                NOT EXISTS (
                    SELECT 1
                    FROM internal.export_job_claims AS claims
                    WHERE claims.job_id = jobs.id
                )
                AND jobs.created_at <
                    pg_catalog.NOW() - INTERVAL '30 minutes'
            )
            OR EXISTS (
                SELECT 1
                FROM internal.export_job_claims AS claims
                WHERE claims.job_id = jobs.id
                  AND claims.lease_expires_at <= pg_catalog.NOW()
            )
        )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stuck_export_jobs()
    FROM PUBLIC, anon, authenticated, service_role;
