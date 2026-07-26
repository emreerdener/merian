BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '5min';

-- Validation uses PostgreSQL's lighter validation lock after the prior
-- constraint-installation transaction has released its ALTER TABLE lock.
-- The bounded export RPC is created only after every legacy row passes.
ALTER TABLE public.scans
    VALIDATE CONSTRAINT scans_dwca_image_urls_bounded_check;
ALTER TABLE public.scans
    VALIDATE CONSTRAINT scans_dwca_interactions_bounded_check;
ALTER TABLE public.species_dictionary
    VALIDATE CONSTRAINT species_dictionary_dwca_taxonomy_bounded_check;

-- These private views are the only source projections used by the export page
-- RPC. They intentionally omit media from occurrence rows and taxonomy from
-- multimedia rows.
CREATE OR REPLACE VIEW internal.dwca_export_occurrence_source
WITH (security_invoker = TRUE)
AS
SELECT
    scans.id AS scan_id,
    scans.user_id,
    scans.geoprivacy,
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
    ) AS scan_payload
FROM public.scans AS scans
LEFT JOIN public.species_dictionary AS species
  ON species.id = scans.species_id
WHERE scans.is_live_capture = TRUE
  AND scans.is_tombstoned = FALSE
  AND scans.ecology_type <> 'domesticated';

CREATE OR REPLACE VIEW internal.dwca_export_multimedia_source
WITH (security_invoker = TRUE)
AS
SELECT
    scans.id AS scan_id,
    scans.user_id,
    scans.geoprivacy,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'image_storage_urls', scans.image_storage_urls
    ) AS scan_payload
FROM public.scans AS scans
WHERE scans.is_live_capture = TRUE
  AND scans.is_tombstoned = FALSE
  AND scans.ecology_type <> 'domesticated';

REVOKE ALL ON TABLE
    internal.dwca_export_occurrence_source,
    internal.dwca_export_multimedia_source
FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON VIEW internal.dwca_export_occurrence_source IS
    'Private bounded source projection for one DwC-A occurrence CSV pass.';
COMMENT ON VIEW internal.dwca_export_multimedia_source IS
    'Private bounded source projection for one DwC-A multimedia CSV pass.';

CREATE OR REPLACE FUNCTION public.get_dwca_export_scan_batch(
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
    source_row_oversize BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    canonical_user_id UUID;
    canonical_scope TEXT;
    canonical_after_id UUID;
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
        jobs.user_id,
        jobs.export_scope,
        CASE
            WHEN p_expected_phase = 'occurrence'
                THEN work.occurrence_after_id
            ELSE work.multimedia_after_id
        END
    INTO
        canonical_user_id,
        canonical_scope,
        canonical_after_id
    FROM public.export_jobs AS jobs
    JOIN internal.export_job_claims AS claims
      ON claims.job_id = jobs.id
    JOIN internal.export_job_work AS work
      ON work.job_id = jobs.id
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
      AND work.phase = p_expected_phase
    FOR SHARE OF jobs, claims, work;

    IF NOT FOUND
       OR p_after_id IS DISTINCT FROM canonical_after_id THEN
        RAISE EXCEPTION 'export_job_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    RETURN QUERY
    WITH source_rows AS NOT MATERIALIZED (
        SELECT
            occurrence_source.scan_id,
            occurrence_source.user_id,
            occurrence_source.geoprivacy,
            occurrence_source.scan_payload
        FROM internal.dwca_export_occurrence_source AS occurrence_source
        WHERE p_expected_phase = 'occurrence'

        UNION ALL

        SELECT
            multimedia_source.scan_id,
            multimedia_source.user_id,
            multimedia_source.geoprivacy,
            multimedia_source.scan_payload
        FROM internal.dwca_export_multimedia_source AS multimedia_source
        WHERE p_expected_phase = 'multimedia'
    ),
    scoped_rows AS NOT MATERIALIZED (
        SELECT
            personal_source.scan_id,
            personal_source.scan_payload
        FROM source_rows AS personal_source
        WHERE canonical_scope = 'personal'
          AND personal_source.user_id = canonical_user_id

        UNION ALL

        SELECT
            global_source.scan_id,
            global_source.scan_payload
        FROM source_rows AS global_source
        WHERE canonical_scope = 'global'
          AND global_source.geoprivacy = 'open'
    ),
    candidate_rows AS MATERIALIZED (
        SELECT
            scoped_source.scan_id,
            scoped_source.scan_payload
        FROM scoped_rows AS scoped_source
        WHERE p_after_id IS NULL
           OR scoped_source.scan_id > p_after_id
        ORDER BY scoped_source.scan_id
        LIMIT p_max_rows + 1
    ),
    sized_rows AS MATERIALIZED (
        SELECT
            candidates.scan_id,
            candidates.scan_payload,
            pg_catalog.OCTET_LENGTH(
                candidates.scan_payload::TEXT
            ) AS source_byte_count,
            pg_catalog.ROW_NUMBER() OVER (
                ORDER BY candidates.scan_id
            ) AS row_ordinal
        FROM candidate_rows AS candidates
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
                FROM candidate_rows AS all_candidates
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
        FALSE
    FROM bounded_rows AS bounded
    CROSS JOIN page_stats AS stats

    UNION ALL

    SELECT
        NULL::UUID,
        NULL::JSONB,
        stats.first_source_byte_count,
        stats.candidate_count = 0,
        stats.candidate_count > 0
    FROM page_stats AS stats
    WHERE stats.bounded_count = 0
    ORDER BY 1 NULLS LAST;
END;
$$;

COMMENT ON FUNCTION public.get_dwca_export_scan_batch(
    UUID, UUID, TEXT, UUID, INTEGER, INTEGER
) IS
    'Returns one claim-bound keyset page capped by rows and serialized source bytes; a sentinel distinguishes completion from an oversized first row.';

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
    'Reads one fenced DwC-A keyset page under strict source-row and aggregate byte ceilings.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

COMMIT;
