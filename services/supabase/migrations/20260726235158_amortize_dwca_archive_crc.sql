BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- ZIP CRCs are calculated once while each CSV chunk is already resident in a
-- bounded preparation invocation. The final assembly invocation combines these
-- durable values algebraically instead of scanning every archive byte in
-- JavaScript.
-- A pre-migration manifest cannot be safely assigned a checksum without
-- downloading its R2 object. Fence only workers that could still consume or
-- append those manifests, then restart those jobs from their already durable
-- immutable source snapshot. Attempt-scoped R2 objects become lifecycle-cleaned
-- orphans. Delivery jobs already have a staged archive and need no manifest.
--
-- Lock canonical jobs in routine lock order before touching the chunk table.
-- An old worker already inside a database routine finishes first and its
-- committed phase is re-evaluated;
-- an affected old worker doing R2 I/O blocks on the job row after this point
-- and loses its deleted claim when the migration commits. This avoids taking an
-- ACCESS EXCLUSIVE chunk-table lock while waiting for a worker's job row.
SELECT jobs.id AS fenced_job_id
FROM public.export_jobs AS jobs
JOIN internal.export_job_work AS work
  ON work.job_id = jobs.id
WHERE jobs.status IN ('pending', 'processing')
  AND work.phase IN ('occurrence', 'multimedia', 'assembling')
ORDER BY jobs.id
FOR UPDATE OF jobs;

DELETE FROM internal.export_job_claims AS claims
USING internal.export_job_work AS work, public.export_jobs AS jobs
WHERE work.job_id = claims.job_id
  AND jobs.id = work.job_id
  AND jobs.status IN ('pending', 'processing')
  AND work.phase IN ('occurrence', 'multimedia', 'assembling');

UPDATE public.export_jobs AS jobs
SET file_url = NULL,
    archive_object_key = NULL,
    archive_ready_at = NULL,
    failure_code = NULL,
    error_message = NULL,
    completed_at = NULL
FROM internal.export_job_work AS work
WHERE work.job_id = jobs.id
  AND jobs.status IN ('pending', 'processing')
  AND work.phase IN ('occurrence', 'multimedia', 'assembling');

UPDATE internal.export_job_work AS work
SET phase = 'occurrence',
    occurrence_after_id = NULL,
    multimedia_after_id = NULL,
    occurrence_rows = 0,
    multimedia_rows = 0,
    csv_bytes = 0,
    chunk_sequence = 0,
    next_step_at = pg_catalog.NOW(),
    retry_count = 0,
    last_error_code = NULL,
    updated_at = pg_catalog.NOW()
FROM public.export_jobs AS jobs
WHERE jobs.id = work.job_id
  AND jobs.status IN ('pending', 'processing')
  AND work.phase IN ('occurrence', 'multimedia', 'assembling');

-- Every existing row predates the checksum contract. Chunk manifests are
-- temporary and no terminal or delivery phase reads them, so removing legacy
-- rows is safe and permits a fail-closed NOT NULL invariant for all future
-- assembly work.
DELETE FROM internal.export_job_chunks;

ALTER TABLE internal.export_job_chunks
ADD COLUMN crc32 BIGINT;

COMMENT ON COLUMN internal.export_job_chunks.crc32 IS
    'Unsigned CRC-32 of the exact bounded CSV object bytes; combined without rereading the complete archive during ZIP assembly.';

COMMENT ON TABLE internal.export_job_chunks IS
    'Ordered R2 CSV chunk manifest with durable byte counts and CRC-32 values used to assemble a bounded final archive without rescanning source tables or archive bytes.';

ALTER TABLE internal.export_job_chunks
ALTER COLUMN crc32 SET NOT NULL;

ALTER TABLE internal.export_job_chunks
ADD CONSTRAINT export_job_chunks_crc32_check
CHECK (
    crc32 BETWEEN 0 AND 4294967295
    AND (byte_count <> 0 OR crc32 = 0)
);

DELETE FROM internal.privileged_routine_grants AS grants
WHERE grants.role_name = 'service_role'
  AND grants.routine_signature =
      'public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,boolean)';

DROP FUNCTION public.advance_export_job_step(
    UUID, UUID, TEXT, UUID, INTEGER, TEXT, INTEGER, BOOLEAN
);

CREATE FUNCTION public.advance_export_job_step(
    p_job_id UUID,
    p_claim_token UUID,
    p_expected_phase TEXT,
    p_next_after_id UUID,
    p_row_count INTEGER,
    p_chunk_object_key TEXT,
    p_chunk_byte_count INTEGER,
    p_chunk_crc32 BIGINT,
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
       OR p_chunk_crc32 IS NULL
       OR p_chunk_crc32 NOT BETWEEN 0 AND 4294967295
       OR (p_chunk_byte_count = 0 AND p_chunk_crc32 <> 0)
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
        byte_count,
        crc32
    )
    VALUES (
        p_job_id,
        p_expected_phase,
        work_row.chunk_sequence,
        p_chunk_object_key,
        p_chunk_byte_count,
        p_chunk_crc32
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

COMMENT ON FUNCTION public.advance_export_job_step(
    UUID, UUID, TEXT, UUID, INTEGER, TEXT, INTEGER, BIGINT, BOOLEAN
) IS
    'Atomically commits one fenced CSV chunk, including its unsigned CRC-32, and advances durable DwC-A preparation state.';

-- A TABLE return type cannot be changed with CREATE OR REPLACE.
DROP FUNCTION public.get_export_job_chunks(UUID, UUID);

CREATE FUNCTION public.get_export_job_chunks(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS TABLE (
    chunk_phase TEXT,
    chunk_sequence INTEGER,
    object_key TEXT,
    byte_count INTEGER,
    crc32 BIGINT
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
        chunks.byte_count,
        chunks.crc32
    FROM internal.export_job_chunks AS chunks
    WHERE chunks.job_id = p_job_id
    ORDER BY
        CASE chunks.phase WHEN 'occurrence' THEN 0 ELSE 1 END,
        chunks.sequence;
END;
$$;

COMMENT ON FUNCTION public.get_export_job_chunks(UUID, UUID) IS
    'Returns the ordered bounded CSV object manifest and durable per-chunk CRCs under the active assembly lease.';

REVOKE ALL ON FUNCTION public.advance_export_job_step(
    UUID, UUID, TEXT, UUID, INTEGER, TEXT, INTEGER, BIGINT, BOOLEAN
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_export_job_chunks(UUID, UUID)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.advance_export_job_step(
    UUID, UUID, TEXT, UUID, INTEGER, TEXT, INTEGER, BIGINT, BOOLEAN
) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_export_job_chunks(UUID, UUID)
TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,bigint,boolean)',
        'Atomically advances a fenced DwC-A cursor and persists a bounded chunk CRC for CPU-bounded final assembly.'
    ),
    (
        'service_role',
        'public.get_export_job_chunks(uuid,uuid)',
        'Reads a bounded prepared CSV manifest and per-chunk CRCs for CPU-bounded final archive assembly.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

COMMIT;
