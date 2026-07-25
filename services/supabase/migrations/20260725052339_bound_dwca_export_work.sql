BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

ALTER TABLE public.export_jobs
    ADD COLUMN max_export_rows INTEGER NOT NULL DEFAULT 5000,
    ADD COLUMN max_archive_bytes BIGINT NOT NULL DEFAULT 8388608;

ALTER TABLE public.export_jobs
    ADD CONSTRAINT export_jobs_max_rows_check
        CHECK (max_export_rows BETWEEN 1 AND 20000),
    ADD CONSTRAINT export_jobs_max_archive_bytes_check
        CHECK (max_archive_bytes BETWEEN 1048576 AND 16777216);

COMMENT ON COLUMN public.export_jobs.max_export_rows IS
    'Immutable canonical ceiling across occurrence and multimedia rows.';
COMMENT ON COLUMN public.export_jobs.max_archive_bytes IS
    'Immutable canonical ceiling for the final stored ZIP object.';

-- The first hardening migration introduced broad keyset indexes. Keep those
-- rollout-safe indexes in place, and add predicates matching the privacy fence
-- used by the phased worker so deleted-account tombstones are never scanned.
CREATE INDEX IF NOT EXISTS idx_scans_dwca_personal_active_keyset
    ON public.scans (user_id, id)
    WHERE is_live_capture = TRUE
      AND ecology_type <> 'domesticated'
      AND is_tombstoned = FALSE;

CREATE INDEX IF NOT EXISTS idx_scans_dwca_global_active_keyset
    ON public.scans (id)
    WHERE is_live_capture = TRUE
      AND ecology_type <> 'domesticated'
      AND geoprivacy = 'open'
      AND is_tombstoned = FALSE;

CREATE TABLE internal.export_job_work (
    job_id UUID PRIMARY KEY
        REFERENCES public.export_jobs(id) ON DELETE CASCADE,
    phase TEXT NOT NULL DEFAULT 'occurrence',
    occurrence_after_id UUID,
    multimedia_after_id UUID,
    occurrence_rows INTEGER NOT NULL DEFAULT 0,
    multimedia_rows INTEGER NOT NULL DEFAULT 0,
    csv_bytes BIGINT NOT NULL DEFAULT 0,
    chunk_sequence INTEGER NOT NULL DEFAULT 0,
    next_step_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    retry_count INTEGER NOT NULL DEFAULT 0,
    last_error_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT export_job_work_phase_check
        CHECK (
            phase IN (
                'occurrence',
                'multimedia',
                'assembling',
                'delivering',
                'completed'
            )
        ),
    CONSTRAINT export_job_work_count_check
        CHECK (
            occurrence_rows BETWEEN 0 AND 20000
            AND multimedia_rows BETWEEN 0 AND 20000
            AND csv_bytes BETWEEN 0 AND 16777216
            AND chunk_sequence BETWEEN 0 AND 100000
            AND retry_count BETWEEN 0 AND 100
        ),
    CONSTRAINT export_job_work_error_check
        CHECK (
            last_error_code IS NULL
            OR last_error_code ~ '^[a-z][a-z0-9_]{1,63}$'
        )
);

CREATE TABLE internal.export_job_chunks (
    job_id UUID NOT NULL
        REFERENCES public.export_jobs(id) ON DELETE CASCADE,
    phase TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    object_key TEXT NOT NULL,
    byte_count INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (job_id, phase, sequence),
    CONSTRAINT export_job_chunks_phase_check
        CHECK (phase IN ('occurrence', 'multimedia')),
    CONSTRAINT export_job_chunks_sequence_check
        CHECK (sequence BETWEEN 0 AND 100000),
    CONSTRAINT export_job_chunks_object_key_check
        CHECK (
            pg_catalog.CHAR_LENGTH(object_key) BETWEEN 1 AND 512
            AND object_key !~ '[[:cntrl:]]'
            AND object_key NOT LIKE '%..%'
        ),
    CONSTRAINT export_job_chunks_byte_count_check
        CHECK (byte_count BETWEEN 0 AND 524288)
);

COMMENT ON TABLE internal.export_job_work IS
    'Durable cursor, budget, and phase state for one bounded DwC-A batch step per Edge invocation.';
COMMENT ON TABLE internal.export_job_chunks IS
    'Ordered R2 CSV chunk manifest used to assemble a bounded final archive without rescanning source tables.';

CREATE INDEX export_job_work_due_idx
    ON internal.export_job_work (next_step_at, job_id)
    WHERE phase <> 'completed';

ALTER TABLE internal.export_job_work ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.export_job_chunks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.export_job_work
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE internal.export_job_chunks
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.initialize_export_job_work()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO internal.export_job_work (job_id)
    VALUES (NEW.id)
    ON CONFLICT (job_id) DO NOTHING;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.initialize_export_job_work()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS initialize_export_job_work ON public.export_jobs;
CREATE TRIGGER initialize_export_job_work
AFTER INSERT ON public.export_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.initialize_export_job_work();

INSERT INTO internal.export_job_work (job_id, phase)
SELECT
    jobs.id,
    CASE
        WHEN jobs.archive_ready_at IS NOT NULL THEN 'delivering'
        ELSE 'occurrence'
    END
FROM public.export_jobs AS jobs
WHERE jobs.status IN ('pending', 'processing')
ON CONFLICT (job_id) DO NOTHING;

CREATE OR REPLACE FUNCTION internal.enforce_export_job_budget_immutability()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.max_export_rows IS DISTINCT FROM OLD.max_export_rows
       OR NEW.max_archive_bytes IS DISTINCT FROM OLD.max_archive_bytes THEN
        RAISE EXCEPTION 'export_job_budget_is_immutable'
            USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_export_job_budget_immutability()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS enforce_export_job_budget_immutability
    ON public.export_jobs;
CREATE TRIGGER enforce_export_job_budget_immutability
BEFORE UPDATE ON public.export_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_export_job_budget_immutability();

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
    SELECT jobs.id
    FROM public.export_jobs AS jobs
    LEFT JOIN internal.export_job_work AS work
      ON work.job_id = jobs.id
    LEFT JOIN internal.export_job_claims AS claims
      ON claims.job_id = jobs.id
    WHERE jobs.status IN ('pending', 'processing')
      AND COALESCE(work.phase, 'occurrence') <> 'completed'
      AND COALESCE(work.next_step_at, jobs.created_at) <= pg_catalog.NOW()
      AND (
          claims.job_id IS NULL
          OR claims.lease_expires_at <= pg_catalog.NOW()
      )
    ORDER BY
        COALESCE(work.next_step_at, jobs.created_at),
        jobs.id
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_export_job_step(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TABLE (
    job_id UUID,
    user_id UUID,
    export_scope TEXT,
    include_precise_coordinates BOOLEAN,
    pseudonym_key_version SMALLINT,
    max_export_rows INTEGER,
    max_archive_bytes BIGINT,
    archive_object_key TEXT,
    file_url TEXT,
    archive_ready_at TIMESTAMPTZ,
    attempt_count INTEGER,
    lease_expires_at TIMESTAMPTZ,
    work_phase TEXT,
    occurrence_after_id UUID,
    multimedia_after_id UUID,
    occurrence_rows INTEGER,
    multimedia_rows INTEGER,
    csv_bytes BIGINT,
    chunk_sequence INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    job_row public.export_jobs%ROWTYPE;
    work_row internal.export_job_work%ROWTYPE;
    claim_row internal.export_job_claims%ROWTYPE;
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
    FOR UPDATE;

    IF NOT FOUND OR job_row.status IN ('completed', 'failed') THEN
        RETURN;
    END IF;

    INSERT INTO internal.export_job_work (job_id)
    VALUES (p_job_id)
    ON CONFLICT ON CONSTRAINT export_job_work_pkey DO NOTHING;

    SELECT work.*
    INTO STRICT work_row
    FROM internal.export_job_work AS work
    WHERE work.job_id = p_job_id
    FOR UPDATE;

    IF work_row.phase = 'completed'
       OR work_row.next_step_at > pg_catalog.NOW() THEN
        RETURN;
    END IF;

    SELECT claims.*
    INTO claim_row
    FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id
    FOR UPDATE;

    IF claim_row.job_id IS NOT NULL
       AND claim_row.lease_expires_at > pg_catalog.NOW() THEN
        RETURN;
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
        pg_catalog.NOW() + INTERVAL '2 minutes',
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
        job_row.max_export_rows,
        job_row.max_archive_bytes,
        job_row.archive_object_key,
        job_row.file_url,
        job_row.archive_ready_at,
        claim_row.attempt_count,
        claim_row.lease_expires_at,
        work_row.phase,
        work_row.occurrence_after_id,
        work_row.multimedia_after_id,
        work_row.occurrence_rows,
        work_row.multimedia_rows,
        work_row.csv_bytes,
        work_row.chunk_sequence;
END;
$$;

CREATE OR REPLACE FUNCTION public.advance_export_job_step(
    p_job_id UUID,
    p_claim_token UUID,
    p_expected_phase TEXT,
    p_next_after_id UUID,
    p_row_count INTEGER,
    p_chunk_object_key TEXT,
    p_chunk_byte_count INTEGER,
    p_page_complete BOOLEAN
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    job_row public.export_jobs%ROWTYPE;
    work_row internal.export_job_work%ROWTYPE;
    current_after_id UUID;
    expected_object_key TEXT;
    next_phase TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_expected_phase NOT IN ('occurrence', 'multimedia')
       OR p_row_count IS NULL
       OR p_row_count NOT BETWEEN 0 AND 20000
       OR p_chunk_byte_count IS NULL
       OR p_chunk_byte_count NOT BETWEEN 0 AND 524288
       OR p_page_complete IS NULL THEN
        RAISE EXCEPTION 'invalid_export_batch_progress'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.*
    INTO STRICT job_row
    FROM public.export_jobs AS jobs
    JOIN internal.export_job_claims AS claims
      ON claims.job_id = jobs.id
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
    FOR UPDATE OF jobs;

    SELECT work.*
    INTO STRICT work_row
    FROM internal.export_job_work AS work
    WHERE work.job_id = p_job_id
      AND work.phase = p_expected_phase
    FOR UPDATE;

    current_after_id := CASE
        WHEN p_expected_phase = 'occurrence'
            THEN work_row.occurrence_after_id
        ELSE work_row.multimedia_after_id
    END;

    IF p_next_after_id IS NOT DISTINCT FROM current_after_id THEN
        IF p_page_complete IS NOT TRUE OR p_row_count <> 0 THEN
            RAISE EXCEPTION 'invalid_export_batch_cursor'
                USING ERRCODE = '22023';
        END IF;
    ELSIF p_next_after_id IS NULL
       OR (
           current_after_id IS NOT NULL
           AND p_next_after_id <= current_after_id
       ) THEN
        RAISE EXCEPTION 'invalid_export_batch_cursor'
            USING ERRCODE = '22023';
    END IF;

    expected_object_key :=
        'exports/' || job_row.user_id::TEXT || '/' || job_row.id::TEXT
        || '/work/' || p_expected_phase || '/'
        || pg_catalog.LPAD(work_row.chunk_sequence::TEXT, 8, '0')
        || '-' || p_claim_token::TEXT || '.csv';

    IF p_chunk_object_key IS DISTINCT FROM expected_object_key
       OR work_row.occurrence_rows + work_row.multimedia_rows
            + p_row_count > job_row.max_export_rows
       OR work_row.csv_bytes + p_chunk_byte_count
            > job_row.max_archive_bytes - 65536 THEN
        RAISE EXCEPTION 'export_budget_exceeded'
            USING ERRCODE = '54000';
    END IF;

    INSERT INTO internal.export_job_chunks (
        job_id,
        phase,
        sequence,
        object_key,
        byte_count
    )
    VALUES (
        p_job_id,
        p_expected_phase,
        work_row.chunk_sequence,
        p_chunk_object_key,
        p_chunk_byte_count
    );

    next_phase := CASE
        WHEN p_page_complete AND p_expected_phase = 'occurrence'
            THEN 'multimedia'
        WHEN p_page_complete AND p_expected_phase = 'multimedia'
            THEN 'assembling'
        ELSE p_expected_phase
    END;

    UPDATE internal.export_job_work AS work
    SET phase = next_phase,
        occurrence_after_id = CASE
            WHEN p_expected_phase = 'occurrence' THEN p_next_after_id
            ELSE work.occurrence_after_id
        END,
        multimedia_after_id = CASE
            WHEN p_expected_phase = 'multimedia' THEN p_next_after_id
            ELSE work.multimedia_after_id
        END,
        occurrence_rows = work.occurrence_rows + CASE
            WHEN p_expected_phase = 'occurrence' THEN p_row_count
            ELSE 0
        END,
        multimedia_rows = work.multimedia_rows + CASE
            WHEN p_expected_phase = 'multimedia' THEN p_row_count
            ELSE 0
        END,
        csv_bytes = work.csv_bytes + p_chunk_byte_count,
        chunk_sequence = work.chunk_sequence + 1,
        next_step_at = pg_catalog.NOW(),
        retry_count = 0,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE work.job_id = p_job_id
      AND work.phase = p_expected_phase;

    DELETE FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token;

    RETURN next_phase;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_export_job_chunks(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TABLE (
    chunk_phase TEXT,
    chunk_sequence INTEGER,
    object_key TEXT,
    byte_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF NOT EXISTS (
        SELECT 1
        FROM public.export_jobs AS jobs
        JOIN internal.export_job_claims AS claims
          ON claims.job_id = jobs.id
        JOIN internal.export_job_work AS work
          ON work.job_id = jobs.id
        WHERE jobs.id = p_job_id
          AND jobs.status = 'processing'
          AND work.phase = 'assembling'
          AND claims.claim_token = p_claim_token
          AND claims.lease_expires_at > pg_catalog.NOW()
    ) THEN
        RAISE EXCEPTION 'export_job_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    RETURN QUERY
    SELECT
        chunks.phase,
        chunks.sequence,
        chunks.object_key,
        chunks.byte_count
    FROM internal.export_job_chunks AS chunks
    WHERE chunks.job_id = p_job_id
    ORDER BY
        CASE chunks.phase WHEN 'occurrence' THEN 0 ELSE 1 END,
        chunks.sequence;
END;
$$;

CREATE OR REPLACE FUNCTION public.stage_prepared_export_archive(
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
    expected_object_key TEXT;
    affected_rows INTEGER;
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
    FROM internal.export_job_claims AS claims,
         internal.export_job_work AS work
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.job_id = jobs.id
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
      AND work.job_id = jobs.id
      AND work.phase = 'assembling';

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
        RETURN FALSE;
    END IF;

    UPDATE internal.export_job_work AS work
    SET phase = 'delivering',
        next_step_at = pg_catalog.NOW(),
        retry_count = 0,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE work.job_id = p_job_id
      AND work.phase = 'assembling';

    DELETE FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_prepared_export_job(
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
    FROM internal.export_job_claims AS claims,
         internal.export_job_work AS work
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND jobs.file_url IS NOT NULL
      AND jobs.archive_object_key IS NOT NULL
      AND jobs.archive_ready_at IS NOT NULL
      AND claims.job_id = jobs.id
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
      AND work.job_id = jobs.id
      AND work.phase = 'delivering';

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    IF affected_rows <> 1 THEN
        RETURN FALSE;
    END IF;

    UPDATE internal.export_job_work AS work
    SET phase = 'completed',
        updated_at = pg_catalog.NOW()
    WHERE work.job_id = p_job_id;

    DELETE FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_export_job_step(
    p_job_id UUID,
    p_claim_token UUID,
    p_failure_code TEXT,
    p_terminal BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    job_row public.export_jobs%ROWTYPE;
    work_row internal.export_job_work%ROWTYPE;
    affected_rows INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_failure_code IS NULL
       OR p_failure_code !~ '^[a-z][a-z0-9_]{1,63}$'
       OR p_terminal IS NULL THEN
        RAISE EXCEPTION 'invalid_export_failure_code'
            USING ERRCODE = '22023';
    END IF;

    -- Keep the lock order identical to claim/advance/stage/complete:
    -- canonical job first, then durable work state.
    SELECT jobs.*
    INTO job_row
    FROM public.export_jobs AS jobs
    JOIN internal.export_job_claims AS claims
      ON claims.job_id = jobs.id
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
    FOR UPDATE OF jobs;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    SELECT work.*
    INTO work_row
    FROM internal.export_job_work AS work
    WHERE work.job_id = p_job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF p_terminal THEN
        UPDATE public.export_jobs AS jobs
        SET status = 'failed',
            failure_code = p_failure_code,
            error_message = CASE p_failure_code
                WHEN 'pseudonym_key_unavailable' THEN
                    'Export security configuration is unavailable. Please retry later.'
                WHEN 'export_too_large' THEN
                    'This export exceeds the current export limits. Please contact support.'
                ELSE 'Export processing failed. Please retry.'
            END,
            completed_at = pg_catalog.NOW()
        WHERE jobs.id = p_job_id
          AND jobs.status = 'processing';
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
    ELSE
        UPDATE internal.export_job_work AS work
        SET retry_count = LEAST(work.retry_count + 1, 100),
            next_step_at = pg_catalog.NOW() + CASE
                WHEN work.retry_count < 2 THEN INTERVAL '1 minute'
                WHEN work.retry_count < 5 THEN INTERVAL '5 minutes'
                WHEN work.retry_count < 10 THEN INTERVAL '15 minutes'
                ELSE INTERVAL '1 hour'
            END,
            last_error_code = p_failure_code,
            updated_at = pg_catalog.NOW()
        WHERE work.job_id = p_job_id;
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
    END IF;

    DELETE FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token;

    RETURN affected_rows = 1;
END;
$$;

REVOKE ALL ON FUNCTION public.get_due_export_job_ids(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_export_job_step(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.advance_export_job_step(
    UUID, UUID, TEXT, UUID, INTEGER, TEXT, INTEGER, BOOLEAN
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_export_job_chunks(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.stage_prepared_export_archive(
    UUID, UUID, TEXT, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_prepared_export_job(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.release_export_job_step(
    UUID, UUID, TEXT, BOOLEAN
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_due_export_job_ids(INTEGER)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_export_job_step(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.advance_export_job_step(
    UUID, UUID, TEXT, UUID, INTEGER, TEXT, INTEGER, BOOLEAN
) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_export_job_chunks(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.stage_prepared_export_archive(
    UUID, UUID, TEXT, TEXT
) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_prepared_export_job(UUID, UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.release_export_job_step(
    UUID, UUID, TEXT, BOOLEAN
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.get_due_export_job_ids(integer)',
        'Returns only bounded due-job identifiers for durable dispatch.'
    ),
    (
        'service_role',
        'public.claim_export_job_step(uuid,uuid)',
        'Leases one canonical resumable DwC-A batch step.'
    ),
    (
        'service_role',
        'public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,boolean)',
        'Atomically advances a fenced DwC-A cursor and chunk manifest.'
    ),
    (
        'service_role',
        'public.get_export_job_chunks(uuid,uuid)',
        'Reads a bounded prepared CSV manifest for final archive assembly.'
    ),
    (
        'service_role',
        'public.stage_prepared_export_archive(uuid,uuid,text,text)',
        'Atomically stages a bounded final archive and advances delivery phase.'
    ),
    (
        'service_role',
        'public.complete_prepared_export_job(uuid,uuid)',
        'Completes delivery under the active batch-step fence.'
    ),
    (
        'service_role',
        'public.release_export_job_step(uuid,uuid,text,boolean)',
        'Durably retries or terminally fails a fenced export step.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

-- Phased jobs are allowed to sit between short claims while pg_cron schedules
-- their next bounded step. Only genuinely abandoned work becomes terminal.
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
        AND NOT EXISTS (
            SELECT 1
            FROM internal.export_job_work AS work
            WHERE work.job_id = jobs.id
              AND work.updated_at >=
                    pg_catalog.NOW() - INTERVAL '30 minutes'
        )
    ) OR (
        jobs.status = 'processing'
        AND EXISTS (
            SELECT 1
            FROM internal.export_job_work AS work
            WHERE work.job_id = jobs.id
              AND work.phase <> 'completed'
              AND work.updated_at <
                    pg_catalog.NOW() - INTERVAL '2 hours'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM internal.export_job_claims AS claims
            WHERE claims.job_id = jobs.id
              AND claims.lease_expires_at > pg_catalog.NOW()
        )
    );
END;
$$;

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

        project_url := COALESCE(
            project_url,
            pg_catalog.CURRENT_SETTING('app.settings.supabase_url', TRUE)
        );
        service_role_key := COALESCE(
            service_role_key,
            pg_catalog.CURRENT_SETTING(
                'app.settings.service_role_key',
                TRUE
            )
        );

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
                body := '{}'::JSONB
            );
        END IF;
    END;
    $job$;
    $cron$
);

NOTIFY pgrst, 'reload schema';

COMMIT;
