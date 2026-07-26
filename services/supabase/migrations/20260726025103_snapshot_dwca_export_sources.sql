BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '5min';

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- A job snapshots only membership and fixed-size revision fingerprints. Copying
-- complete source payloads would retain a potentially very large second copy of
-- private observation data for every queued export. The page RPC below compares
-- the current projection with these creation-time fingerprints in the same SQL
-- statement that returns the payload. A changed or deleted source row therefore
-- fails the complete job instead of mixing revisions.
CREATE TABLE internal.export_job_source_state (
    job_id UUID PRIMARY KEY
        REFERENCES public.export_jobs(id) ON DELETE CASCADE,
    snapshot_version SMALLINT NOT NULL DEFAULT 1,
    snapshot_at TIMESTAMPTZ NOT NULL,
    source_scan_count INTEGER NOT NULL,
    source_too_large BOOLEAN NOT NULL,
    purged_at TIMESTAMPTZ,
    CONSTRAINT export_job_source_state_version_check
        CHECK (snapshot_version = 1),
    CONSTRAINT export_job_source_state_count_check
        CHECK (source_scan_count BETWEEN 0 AND 20001),
    CONSTRAINT export_job_source_state_purge_check
        CHECK (purged_at IS NULL OR purged_at >= snapshot_at)
);

CREATE TABLE internal.export_job_source_membership (
    job_id UUID NOT NULL
        REFERENCES public.export_jobs(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL,
    eligibility_sha256 BYTEA NOT NULL,
    occurrence_sha256 BYTEA NOT NULL,
    multimedia_sha256 BYTEA NOT NULL,
    PRIMARY KEY (job_id, scan_id),
    CONSTRAINT export_job_source_membership_hashes_check
        CHECK (
            pg_catalog.OCTET_LENGTH(eligibility_sha256) = 32
            AND pg_catalog.OCTET_LENGTH(occurrence_sha256) = 32
            AND pg_catalog.OCTET_LENGTH(multimedia_sha256) = 32
    )
);

COMMENT ON COLUMN internal.export_job_source_membership.scan_id IS
    'Intentionally has no scans FK: physical deletion must produce a revision mismatch, not silently shrink job membership.';

ALTER TABLE internal.export_job_source_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.export_job_source_membership ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    internal.export_job_source_state,
    internal.export_job_source_membership
FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.export_job_source_state IS
    'Private creation-time state for one immutable DwC-A source membership snapshot. source_scan_count is capped at max_export_rows + 1 when source_too_large is true.';
COMMENT ON TABLE internal.export_job_source_membership IS
    'Private fixed membership and SHA-256 revision fingerprints shared by every phase of one DwC-A export.';

-- This private projection has no eligibility WHERE clause. A previously
-- snapshotted row remains visible to the revision comparison after its privacy,
-- tombstone, capture, or ecology state changes, allowing the RPC to reject the
-- revision rather than silently dropping it from a later phase.
CREATE OR REPLACE VIEW internal.dwca_export_current_source
WITH (security_invoker = TRUE)
AS
SELECT
    scans.id AS scan_id,
    scans.user_id,
    scans.is_live_capture,
    scans.is_tombstoned,
    scans.ecology_type,
    scans.geoprivacy,
    pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', scans.user_id,
        'is_live_capture', scans.is_live_capture,
        'is_tombstoned', scans.is_tombstoned,
        'ecology_type', scans.ecology_type,
        'geoprivacy', scans.geoprivacy
    ) AS eligibility_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'timestamp', scans.timestamp,
        'gps_lat_exact', scans.gps_lat_exact,
        'gps_long_exact', scans.gps_long_exact,
        'gps_lat_public', scans.gps_lat_public,
        'gps_long_public', scans.gps_long_public,
        'coordinate_uncertainty_in_meters',
            scans.coordinate_uncertainty_in_meters,
        'life_stage', scans.life_stage,
        'reproductive_condition', scans.reproductive_condition,
        'sex', scans.sex,
        'individual_count', scans.individual_count,
        'ecological_interactions',
            COALESCE(scans.ecological_interactions, ARRAY[]::TEXT[]),
        'ai_confidence_score', scans.ai_confidence_score,
        'species_dictionary', CASE
            WHEN species.id IS NULL THEN NULL
            ELSE pg_catalog.JSONB_BUILD_OBJECT(
                'scientific_name', species.scientific_name,
                'kingdom', species.kingdom,
                'phylum', species.phylum,
                'class', species.class,
                'order', species."order",
                'family', species.family,
                'genus', species.genus,
                'iucn_red_list_status', species.iucn_red_list_status
            )
        END
    ) AS occurrence_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'image_storage_urls', scans.image_storage_urls
    ) AS multimedia_payload
FROM public.scans AS scans
LEFT JOIN public.species_dictionary AS species
  ON species.id = scans.species_id;

REVOKE ALL ON TABLE internal.dwca_export_current_source
FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON VIEW internal.dwca_export_current_source IS
    'Private current projection compared with creation-time DwC-A membership fingerprints before any row is emitted.';

CREATE OR REPLACE FUNCTION internal.materialize_dwca_export_source_snapshot(
    p_job_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    job_row public.export_jobs%ROWTYPE;
BEGIN
    SELECT jobs.*
    INTO job_row
    FROM public.export_jobs AS jobs
    WHERE jobs.id = p_job_id
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'dwca_export_job_not_found'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.export_job_source_state AS source_state
        WHERE source_state.job_id = p_job_id
    ) THEN
        RAISE EXCEPTION 'dwca_export_source_snapshot_already_exists'
            USING ERRCODE = '55000';
    END IF;

    -- Membership, state, and all three hashes are derived by one statement and
    -- therefore one MVCC snapshot. The max + 1 lookahead detects a job that is
    -- guaranteed to exceed the occurrence-row budget without storing its rows.
    WITH eligible_membership AS MATERIALIZED (
        SELECT personal_scans.id AS scan_id
        FROM public.scans AS personal_scans
        WHERE job_row.export_scope = 'personal'
          AND personal_scans.user_id = job_row.user_id
          AND personal_scans.is_live_capture = TRUE
          AND personal_scans.is_tombstoned = FALSE
          AND personal_scans.ecology_type <> 'domesticated'

        UNION ALL

        SELECT global_scans.id AS scan_id
        FROM public.scans AS global_scans
        WHERE job_row.export_scope = 'global'
          AND global_scans.geoprivacy = 'open'
          AND global_scans.is_live_capture = TRUE
          AND global_scans.is_tombstoned = FALSE
          AND global_scans.ecology_type <> 'domesticated'

        ORDER BY scan_id
        LIMIT job_row.max_export_rows + 1
    ),
    membership_stats AS (
        SELECT pg_catalog.COUNT(*)::INTEGER AS source_scan_count
        FROM eligible_membership
    ),
    inserted_state AS (
        INSERT INTO internal.export_job_source_state (
            job_id,
            snapshot_version,
            snapshot_at,
            source_scan_count,
            source_too_large
        )
        SELECT
            job_row.id,
            1,
            pg_catalog.STATEMENT_TIMESTAMP(),
            membership_stats.source_scan_count,
            membership_stats.source_scan_count > job_row.max_export_rows
        FROM membership_stats
        RETURNING source_too_large
    )
    INSERT INTO internal.export_job_source_membership (
        job_id,
        scan_id,
        eligibility_sha256,
        occurrence_sha256,
        multimedia_sha256
    )
    SELECT
        job_row.id,
        eligible.scan_id,
        extensions.digest(
            current_source.eligibility_payload::TEXT,
            'sha256'
        ),
        extensions.digest(
            current_source.occurrence_payload::TEXT,
            'sha256'
        ),
        extensions.digest(
            current_source.multimedia_payload::TEXT,
            'sha256'
        )
    FROM eligible_membership AS eligible
    JOIN internal.dwca_export_current_source AS current_source
      ON current_source.scan_id = eligible.scan_id
    CROSS JOIN inserted_state AS source_state
    WHERE source_state.source_too_large = FALSE
    ORDER BY eligible.scan_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.materialize_dwca_export_source_snapshot(UUID)
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.initialize_dwca_export_source_snapshot()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.materialize_dwca_export_source_snapshot(NEW.id);
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.initialize_dwca_export_source_snapshot()
FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS initialize_dwca_export_source_snapshot
ON public.export_jobs;
CREATE TRIGGER initialize_dwca_export_source_snapshot
AFTER INSERT ON public.export_jobs
FOR EACH ROW
WHEN (NEW.status IN ('pending', 'processing'))
EXECUTE FUNCTION internal.initialize_dwca_export_source_snapshot();

CREATE OR REPLACE FUNCTION internal.purge_dwca_export_source_snapshot()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF OLD.status NOT IN ('completed', 'failed')
       AND NEW.status IN ('completed', 'failed') THEN
        DELETE FROM internal.export_job_source_membership AS membership
        WHERE membership.job_id = NEW.id;

        UPDATE internal.export_job_source_state AS source_state
        SET purged_at = pg_catalog.CLOCK_TIMESTAMP()
        WHERE source_state.job_id = NEW.id
          AND source_state.purged_at IS NULL;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.purge_dwca_export_source_snapshot()
FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS purge_dwca_export_source_snapshot
ON public.export_jobs;
CREATE TRIGGER purge_dwca_export_source_snapshot
AFTER UPDATE OF status ON public.export_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.purge_dwca_export_source_snapshot();

-- Fence and restart every nonterminal pre-migration job. Its prior phase
-- chunks could have been built from different live revisions and must never be
-- assembled with the new membership snapshot. Attempt-fenced R2 objects become
-- harmless orphans covered by the configured lifecycle policy.
DELETE FROM internal.export_job_claims AS claims
USING public.export_jobs AS jobs
WHERE jobs.id = claims.job_id
  AND jobs.status IN ('pending', 'processing');

DELETE FROM internal.export_job_chunks AS chunks
USING public.export_jobs AS jobs
WHERE jobs.id = chunks.job_id
  AND jobs.status IN ('pending', 'processing');

INSERT INTO internal.export_job_work (job_id)
SELECT jobs.id
FROM public.export_jobs AS jobs
WHERE jobs.status IN ('pending', 'processing')
ON CONFLICT ON CONSTRAINT export_job_work_pkey DO NOTHING;

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
  AND jobs.status IN ('pending', 'processing');

UPDATE public.export_jobs AS jobs
SET file_url = NULL,
    archive_object_key = NULL,
    archive_ready_at = NULL,
    failure_code = NULL,
    error_message = NULL,
    completed_at = NULL
WHERE jobs.status IN ('pending', 'processing');

DO $backfill$
DECLARE
    active_job RECORD;
BEGIN
    FOR active_job IN
        SELECT jobs.id
        FROM public.export_jobs AS jobs
        WHERE jobs.status IN ('pending', 'processing')
        ORDER BY jobs.id
    LOOP
        PERFORM internal.materialize_dwca_export_source_snapshot(
            active_job.id
        );
    END LOOP;
END;
$backfill$;

-- Preserve the RPC signature used by the deployed worker during
-- migration-before-bundle rollout. The extra result flag is ignored by the old
-- parser for normal rows. A revision mismatch appears inconsistent to that
-- parser and is retried without emitting data until the new bundle can fail the
-- job terminally.
DROP FUNCTION public.get_dwca_export_scan_batch(
    UUID, UUID, TEXT, UUID, INTEGER, INTEGER
);

DROP VIEW internal.dwca_export_occurrence_source;
DROP VIEW internal.dwca_export_multimedia_source;

CREATE FUNCTION public.get_dwca_export_scan_batch(
    p_job_id UUID,
    p_claim_token UUID,
    p_expected_phase TEXT,
    p_after_id UUID,
    p_max_rows INTEGER DEFAULT 100,
    p_max_source_bytes INTEGER DEFAULT 262144
)
RETURNS TABLE (
    scan_id UUID,
    scan_payload JSONB,
    source_byte_count INTEGER,
    page_complete BOOLEAN,
    source_row_oversize BOOLEAN,
    source_revision_changed BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    canonical_after_id UUID;
    snapshot_too_large BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_job_id IS NULL
       OR p_claim_token IS NULL
       OR p_expected_phase IS NULL
       OR p_expected_phase NOT IN ('occurrence', 'multimedia')
       OR p_max_rows IS NULL
       OR p_max_rows NOT BETWEEN 1 AND 100
       OR p_max_source_bytes IS NULL
       OR p_max_source_bytes NOT BETWEEN 1 AND 262144 THEN
        RAISE EXCEPTION 'invalid_dwca_export_source_page'
            USING ERRCODE = '22023';
    END IF;

    SELECT
        CASE
            WHEN p_expected_phase = 'occurrence'
                THEN work.occurrence_after_id
            ELSE work.multimedia_after_id
        END,
        source_state.source_too_large
    INTO
        canonical_after_id,
        snapshot_too_large
    FROM public.export_jobs AS jobs
    JOIN internal.export_job_claims AS claims
      ON claims.job_id = jobs.id
    JOIN internal.export_job_work AS work
      ON work.job_id = jobs.id
    JOIN internal.export_job_source_state AS source_state
      ON source_state.job_id = jobs.id
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
      AND work.phase = p_expected_phase
      AND source_state.snapshot_version = 1
      AND source_state.purged_at IS NULL
    FOR SHARE OF jobs, claims, work, source_state;

    IF NOT FOUND
       OR p_after_id IS DISTINCT FROM canonical_after_id THEN
        RAISE EXCEPTION 'export_job_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    IF snapshot_too_large THEN
        RETURN QUERY
        SELECT
            NULL::UUID,
            NULL::JSONB,
            p_max_source_bytes + 1,
            FALSE,
            TRUE,
            FALSE;
        RETURN;
    END IF;

    RETURN QUERY
    WITH candidate_membership AS MATERIALIZED (
        SELECT
            membership.scan_id,
            membership.eligibility_sha256,
            membership.occurrence_sha256,
            membership.multimedia_sha256
        FROM internal.export_job_source_membership AS membership
        WHERE membership.job_id = p_job_id
          AND (
              p_after_id IS NULL
              OR membership.scan_id > p_after_id
          )
        ORDER BY membership.scan_id
        LIMIT p_max_rows + 1
    ),
    current_revisions AS MATERIALIZED (
        SELECT
            candidates.scan_id,
            CASE
                WHEN p_expected_phase = 'occurrence'
                    THEN current_source.occurrence_payload
                ELSE current_source.multimedia_payload
            END AS scan_payload,
            (
                current_source.scan_id IS NULL
                OR extensions.digest(
                    current_source.eligibility_payload::TEXT,
                    'sha256'
                ) IS DISTINCT FROM candidates.eligibility_sha256
                OR (
                    CASE
                        WHEN p_expected_phase = 'occurrence'
                            THEN extensions.digest(
                                current_source.occurrence_payload::TEXT,
                                'sha256'
                            )
                        ELSE extensions.digest(
                            current_source.multimedia_payload::TEXT,
                            'sha256'
                        )
                    END
                ) IS DISTINCT FROM (
                    CASE
                        WHEN p_expected_phase = 'occurrence'
                            THEN candidates.occurrence_sha256
                        ELSE candidates.multimedia_sha256
                    END
                )
            ) AS revision_changed,
            pg_catalog.ROW_NUMBER() OVER (
                ORDER BY candidates.scan_id
            ) AS row_ordinal
        FROM candidate_membership AS candidates
        LEFT JOIN internal.dwca_export_current_source AS current_source
          ON current_source.scan_id = candidates.scan_id
    ),
    revision_stats AS (
        SELECT COALESCE(
            pg_catalog.BOOL_OR(revisions.revision_changed),
            FALSE
        ) AS revision_changed
        FROM current_revisions AS revisions
    ),
    sized_rows AS MATERIALIZED (
        SELECT
            revisions.scan_id,
            revisions.scan_payload,
            pg_catalog.OCTET_LENGTH(
                revisions.scan_payload::TEXT
            ) AS source_byte_count,
            revisions.row_ordinal
        FROM current_revisions AS revisions
        WHERE revisions.revision_changed = FALSE
    ),
    running_rows AS MATERIALIZED (
        SELECT
            sized.scan_id,
            sized.scan_payload,
            sized.source_byte_count,
            sized.row_ordinal,
            pg_catalog.SUM(sized.source_byte_count) OVER (
                ORDER BY sized.scan_id
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS running_byte_count
        FROM sized_rows AS sized
    ),
    bounded_rows AS MATERIALIZED (
        SELECT
            running.scan_id,
            running.scan_payload,
            running.source_byte_count
        FROM running_rows AS running
        WHERE running.row_ordinal <= p_max_rows
          AND running.running_byte_count <= p_max_source_bytes
    ),
    page_stats AS (
        SELECT
            (
                SELECT pg_catalog.COUNT(*)
                FROM candidate_membership AS all_candidates
            ) AS candidate_count,
            (
                SELECT pg_catalog.COUNT(*)
                FROM bounded_rows AS all_bounded
            ) AS bounded_count,
            COALESCE(
                (
                    SELECT first_sized.source_byte_count
                    FROM sized_rows AS first_sized
                    WHERE first_sized.row_ordinal = 1
                ),
                0
            )::INTEGER AS first_source_byte_count
    )
    SELECT
        bounded.scan_id,
        bounded.scan_payload,
        bounded.source_byte_count,
        stats.candidate_count = stats.bounded_count,
        FALSE,
        FALSE
    FROM bounded_rows AS bounded
    CROSS JOIN page_stats AS stats
    CROSS JOIN revision_stats AS revisions
    WHERE revisions.revision_changed = FALSE

    UNION ALL

    SELECT
        NULL::UUID,
        NULL::JSONB,
        0,
        FALSE,
        FALSE,
        TRUE
    FROM revision_stats AS revisions
    WHERE revisions.revision_changed

    UNION ALL

    SELECT
        NULL::UUID,
        NULL::JSONB,
        stats.first_source_byte_count,
        stats.candidate_count = 0,
        stats.candidate_count > 0,
        FALSE
    FROM page_stats AS stats
    CROSS JOIN revision_stats AS revisions
    WHERE revisions.revision_changed = FALSE
      AND stats.bounded_count = 0
    ORDER BY 1 NULLS LAST;
END;
$$;

COMMENT ON FUNCTION public.get_dwca_export_scan_batch(
    UUID, UUID, TEXT, UUID, INTEGER, INTEGER
) IS
    'Returns one claim-bound page from immutable job membership; each emitted projection must match its creation-time SHA-256 revision and aggregate source-byte ceiling.';

REVOKE ALL ON FUNCTION public.get_dwca_export_scan_batch(
    UUID, UUID, TEXT, UUID, INTEGER, INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_dwca_export_scan_batch(
    UUID, UUID, TEXT, UUID, INTEGER, INTEGER
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.get_dwca_export_scan_batch(uuid,uuid,text,uuid,integer,integer)',
    'Reads one fenced page from immutable job membership and rejects any source revision change before returning data.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

COMMIT;
