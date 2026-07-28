SET lock_timeout = '10s';
SET statement_timeout = '10min';

-- Public browsers reach Explore through the Next.js server. Keep the database
-- credential and RLS bypass on that trusted server boundary, and expose only
-- the already privacy-filtered projection needed by the web UI. In particular,
-- callers cannot supply a viewer identity to impersonate block/ownership state.
CREATE OR REPLACE FUNCTION public.get_public_web_explore_posts(
    p_target_post_id UUID DEFAULT NULL,
    p_max_limit INTEGER DEFAULT 24
)
RETURNS TABLE(
    post_id UUID,
    scan_id UUID,
    hero_image_url TEXT,
    reference_thumbnail_url TEXT,
    shared_at TIMESTAMPTZ,
    author_user_id UUID,
    author_name TEXT,
    author_username TEXT,
    author_avatar_url TEXT,
    author_is_pro BOOLEAN,
    species_common_name TEXT,
    species_scientific_name TEXT,
    pet_identification JSONB,
    public_location_label TEXT,
    location_sharing TEXT,
    time_of_day TEXT,
    current_month INTEGER,
    weather_condition TEXT,
    weather_temperature_f DOUBLE PRECISION,
    like_count INTEGER,
    comment_count INTEGER,
    viewer_has_liked BOOLEAN,
    is_owned_by_viewer BOOLEAN,
    media_items JSONB
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_max_limit IS NULL OR p_max_limit NOT BETWEEN 1 AND 48 THEN
        RAISE EXCEPTION 'invalid_public_web_explore_limit'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        cards.post_id,
        cards.scan_id,
        cards.hero_image_url,
        public.public_species_first_reference_image_url(
            COALESCE(scan.confirmed_species_id, scan.species_id),
            species.reference_image_url
        ),
        cards.shared_at,
        cards.author_user_id,
        cards.author_name,
        author.public_username,
        cards.author_avatar_url,
        author.subscription_tier = 'pro',
        cards.species_common_name,
        cards.species_scientific_name,
        cards.pet_identification,
        cards.public_location_label,
        cards.location_sharing,
        cards.time_of_day,
        cards.current_month,
        cards.weather_condition,
        cards.weather_temperature_f,
        0::INTEGER,
        0::INTEGER,
        FALSE,
        FALSE,
        cards.media_items
    FROM public.explore_projected_post_cards(NULL::UUID) AS cards
    INNER JOIN public.scans AS scan
        ON scan.id = cards.scan_id
    INNER JOIN public.users AS author
        ON author.id = cards.author_user_id
    LEFT JOIN public.species_dictionary AS species
        ON species.id = COALESCE(
            scan.confirmed_species_id,
            scan.species_id
        )
    WHERE (
        p_target_post_id IS NULL
        OR cards.post_id = p_target_post_id
    )
    ORDER BY cards.shared_at DESC, cards.post_id DESC
    LIMIT CASE
        WHEN p_target_post_id IS NULL THEN p_max_limit
        ELSE 1
    END;
END;
$$;

COMMENT ON FUNCTION public.get_public_web_explore_posts(UUID, INTEGER) IS
    'Service-only public-web projection with a fixed anonymous viewer. Returns privacy-filtered post cards without engagement or ownership state.';

REVOKE ALL ON FUNCTION public.get_public_web_explore_posts(UUID, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_web_explore_posts(UUID, INTEGER)
    TO service_role;

CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_detail(
    p_target_post_id UUID
)
RETURNS TABLE(
    post_id UUID,
    field_notes TEXT,
    location_sharing TEXT,
    hashtags TEXT[],
    species_dictionary_id UUID,
    alternative_common_names TEXT[],
    taxonomy_kingdom TEXT,
    taxonomy_phylum TEXT,
    taxonomy_class TEXT,
    taxonomy_order TEXT,
    taxonomy_family TEXT,
    taxonomy_genus TEXT,
    ai_reasoning TEXT,
    habitat_description TEXT,
    gbif_taxon_key INTEGER,
    iucn_red_list_status TEXT,
    hazard_type TEXT,
    wikipedia_url TEXT,
    reference_image_url TEXT,
    wikipedia_overview TEXT
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_target_post_id IS NULL THEN
        RAISE EXCEPTION 'invalid_public_web_explore_post'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        detail.post_id,
        detail.field_notes,
        detail.location_sharing,
        detail.hashtags,
        detail.species_dictionary_id,
        detail.alternative_common_names,
        detail.taxonomy_kingdom,
        detail.taxonomy_phylum,
        detail.taxonomy_class,
        detail.taxonomy_order,
        detail.taxonomy_family,
        detail.taxonomy_genus,
        detail.ai_reasoning,
        detail.habitat_description,
        detail.gbif_taxon_key,
        detail.iucn_red_list_status,
        detail.hazard_type,
        detail.wikipedia_url,
        detail.reference_image_url,
        detail.wikipedia_overview
    FROM public.get_explore_post_detail(
        NULL::UUID,
        p_target_post_id
    ) AS detail
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_public_web_explore_post_detail(UUID) IS
    'Service-only public-web detail projection with a fixed anonymous viewer and the canonical visibility/privacy boundary.';

REVOKE ALL ON FUNCTION public.get_public_web_explore_post_detail(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_web_explore_post_detail(UUID)
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.get_public_web_explore_posts(uuid,integer)',
        'Returns the narrowly scoped anonymous Explore card projection to the server-only public web application.'
    ),
    (
        'service_role',
        'public.get_public_web_explore_post_detail(uuid)',
        'Returns the narrowly scoped anonymous Explore detail projection to the server-only public web application.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

-- Stop inserts while the snapshot representation is replaced. Dropping these
-- triggers takes and retains the export_jobs table lock for this CLI-managed
-- migration transaction, so no job can be created without a snapshot.
DROP TRIGGER IF EXISTS initialize_dwca_export_source_snapshot
    ON public.export_jobs;
DROP TRIGGER IF EXISTS purge_dwca_export_source_snapshot
    ON public.export_jobs;

-- Fence every nonterminal worker before replacing its durable source and work
-- state. Attempt-scoped R2 objects are harmless orphans covered by lifecycle
-- expiry and cannot be referenced by a replacement claim.
DELETE FROM internal.export_job_claims AS claims
USING public.export_jobs AS jobs
WHERE jobs.id = claims.job_id
  AND jobs.status IN ('pending', 'processing');

DELETE FROM internal.export_job_chunks AS chunks
USING public.export_jobs AS jobs
WHERE jobs.id = chunks.job_id
  AND jobs.status IN ('pending', 'processing');

DELETE FROM internal.export_job_source_state AS source_state
USING public.export_jobs AS jobs
WHERE jobs.id = source_state.job_id
  AND jobs.status IN ('pending', 'processing');

DROP TABLE internal.export_job_source_membership;

CREATE TABLE internal.export_job_source_rows (
    job_id UUID NOT NULL
        REFERENCES public.export_jobs(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL,
    eligibility_sha256 BYTEA NOT NULL,
    occurrence_payload JSONB NOT NULL,
    occurrence_byte_count INTEGER NOT NULL,
    multimedia_payload JSONB NOT NULL,
    multimedia_byte_count INTEGER NOT NULL,
    PRIMARY KEY (job_id, scan_id),
    CONSTRAINT export_job_source_rows_hash_check
        CHECK (pg_catalog.OCTET_LENGTH(eligibility_sha256) = 32),
    CONSTRAINT export_job_source_rows_payload_types_check
        CHECK (
            pg_catalog.JSONB_TYPEOF(occurrence_payload) = 'object'
            AND pg_catalog.JSONB_TYPEOF(multimedia_payload) = 'object'
        ),
    CONSTRAINT export_job_source_rows_occurrence_bytes_check
        CHECK (
            occurrence_byte_count BETWEEN 1 AND 262144
            AND occurrence_byte_count = pg_catalog.OCTET_LENGTH(
                occurrence_payload::TEXT
            )
        ),
    CONSTRAINT export_job_source_rows_multimedia_bytes_check
        CHECK (
            multimedia_byte_count BETWEEN 1 AND 262144
            AND multimedia_byte_count = pg_catalog.OCTET_LENGTH(
                multimedia_payload::TEXT
            )
        )
);

COMMENT ON TABLE internal.export_job_source_rows IS
    'Private immutable privacy-projected DwC-A DTO rows shared by every phase and purged when the job becomes terminal.';
COMMENT ON COLUMN internal.export_job_source_rows.scan_id IS
    'Intentionally has no scans FK so an account deletion or source removal can revoke the export through its eligibility hash without deleting the immutable DTO prematurely.';
COMMENT ON COLUMN internal.export_job_source_rows.eligibility_sha256 IS
    'Scope-aware live privacy eligibility fence. Personal snapshots ignore geoprivacy; both scopes track whether protected-species coordinate redaction is required.';

ALTER TABLE internal.export_job_source_rows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.export_job_source_rows
    FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE internal.export_job_source_state
    DROP CONSTRAINT export_job_source_state_version_check,
    ALTER COLUMN snapshot_version SET DEFAULT 2,
    ADD COLUMN source_byte_count BIGINT,
    ADD COLUMN max_source_bytes BIGINT;

UPDATE internal.export_job_source_state AS source_state
SET snapshot_version = 2,
    source_byte_count = 0,
    max_source_bytes = LEAST(
        67108864::BIGINT,
        jobs.max_archive_bytes * 4
    )
FROM public.export_jobs AS jobs
WHERE jobs.id = source_state.job_id;

ALTER TABLE internal.export_job_source_state
    ALTER COLUMN source_byte_count SET NOT NULL,
    ALTER COLUMN max_source_bytes SET NOT NULL,
    ADD CONSTRAINT export_job_source_state_version_check
        CHECK (snapshot_version = 2),
    ADD CONSTRAINT export_job_source_state_max_bytes_check
        CHECK (max_source_bytes BETWEEN 4194304 AND 67108864),
    ADD CONSTRAINT export_job_source_state_bytes_check
        CHECK (
            source_byte_count BETWEEN 0 AND max_source_bytes + 1
        ),
    ADD CONSTRAINT export_job_source_state_size_check
        CHECK (
            source_too_large
            OR source_byte_count <= max_source_bytes
        );

COMMENT ON TABLE internal.export_job_source_state IS
    'Private creation-time state for one immutable DwC-A DTO snapshot. Row count is capped at max_export_rows + 1; source bytes are capped at max_source_bytes + 1.';
COMMENT ON COLUMN internal.export_job_source_state.source_byte_count IS
    'Canonical UTF-8 byte count of occurrence plus multimedia JSON projections, capped at max_source_bytes + 1 when oversized.';
COMMENT ON COLUMN internal.export_job_source_state.max_source_bytes IS
    'Immutable database snapshot budget: four times max_archive_bytes, capped at 64 MiB.';

DROP VIEW internal.dwca_export_current_source;

-- The projection is evaluated exactly once when a job is created. The
-- occurrence dictionary follows the authoritative final identity while
-- retaining the AI species_id on scans for audit/history.
CREATE VIEW internal.dwca_export_snapshot_source
WITH (security_invoker = TRUE)
AS
SELECT
    scans.id AS scan_id,
    scans.user_id,
    scans.is_live_capture,
    scans.is_tombstoned,
    scans.ecology_type,
    scans.geoprivacy,
    COALESCE(scans.confirmed_species_id, scans.species_id)
        AS effective_species_id,
    species.iucn_red_list_status,
    COALESCE(
        species.iucn_red_list_status IN (
            'vulnerable',
            'endangered',
            'critically_endangered',
            'near_threatened'
        ),
        FALSE
    ) AS coordinate_protection_required,
    pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', scans.user_id,
        'is_live_capture', scans.is_live_capture,
        'is_tombstoned', scans.is_tombstoned,
        'ecology_type', scans.ecology_type,
        'geoprivacy', NULL,
        'coordinate_protection_required',
            COALESCE(
                species.iucn_red_list_status IN (
                    'vulnerable',
                    'endangered',
                    'critically_endangered',
                    'near_threatened'
                ),
                FALSE
            )
    ) AS personal_eligibility_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', scans.user_id,
        'is_live_capture', scans.is_live_capture,
        'is_tombstoned', scans.is_tombstoned,
        'ecology_type', scans.ecology_type,
        'geoprivacy', scans.geoprivacy,
        'coordinate_protection_required',
            COALESCE(
                species.iucn_red_list_status IN (
                    'vulnerable',
                    'endangered',
                    'critically_endangered',
                    'near_threatened'
                ),
                FALSE
            )
    ) AS global_eligibility_payload,
    pg_catalog.JSONB_BUILD_OBJECT(
        'id', scans.id,
        'user_id', scans.user_id,
        'effective_species_id',
            COALESCE(scans.confirmed_species_id, scans.species_id),
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
    ON species.id = COALESCE(
        scans.confirmed_species_id,
        scans.species_id
    );

REVOKE ALL ON TABLE internal.dwca_export_snapshot_source
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON VIEW internal.dwca_export_snapshot_source IS
    'Private one-statement source projection used to materialize immutable authoritative DwC-A DTO rows and scope-aware privacy eligibility hashes.';

CREATE OR REPLACE FUNCTION internal.materialize_dwca_export_source_snapshot(
    p_job_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '30s'
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

    -- Membership, immutable DTOs, byte totals, and privacy hashes are derived by
    -- one SQL statement and therefore one MVCC snapshot.
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
    projected_rows AS MATERIALIZED (
        SELECT
            source.scan_id,
            CASE
                WHEN job_row.export_scope = 'personal'
                    THEN source.personal_eligibility_payload
                ELSE source.global_eligibility_payload
            END AS eligibility_payload,
            CASE
                WHEN job_row.export_scope = 'personal'
                     AND job_row.include_precise_coordinates
                     AND source.coordinate_protection_required = FALSE
                    THEN source.occurrence_payload
                ELSE source.occurrence_payload
                    - ARRAY['gps_lat_exact', 'gps_long_exact']::TEXT[]
            END AS occurrence_payload,
            source.multimedia_payload
        FROM eligible_membership AS eligible
        INNER JOIN internal.dwca_export_snapshot_source AS source
            ON source.scan_id = eligible.scan_id
    ),
    snapshot_rows AS MATERIALIZED (
        SELECT
            projected.scan_id,
            projected.eligibility_payload,
            projected.occurrence_payload,
            pg_catalog.OCTET_LENGTH(
                projected.occurrence_payload::TEXT
            )::INTEGER AS occurrence_byte_count,
            projected.multimedia_payload,
            pg_catalog.OCTET_LENGTH(
                projected.multimedia_payload::TEXT
            )::INTEGER AS multimedia_byte_count
        FROM projected_rows AS projected
    ),
    snapshot_budget AS (
        SELECT LEAST(
            67108864::BIGINT,
            job_row.max_archive_bytes * 4
        ) AS max_source_bytes
    ),
    snapshot_stats AS (
        SELECT
            pg_catalog.COUNT(*)::INTEGER AS source_scan_count,
            COALESCE(
                pg_catalog.SUM(
                    rows.occurrence_byte_count::BIGINT
                    + rows.multimedia_byte_count::BIGINT
                ),
                0
            ) AS source_byte_count,
            COALESCE(
                pg_catalog.BOOL_OR(
                    rows.occurrence_byte_count > 262144
                    OR rows.multimedia_byte_count > 262144
                ),
                FALSE
            ) AS source_row_oversize
        FROM snapshot_rows AS rows
    ),
    inserted_state AS (
        INSERT INTO internal.export_job_source_state (
            job_id,
            snapshot_version,
            snapshot_at,
            source_scan_count,
            source_byte_count,
            max_source_bytes,
            source_too_large
        )
        SELECT
            job_row.id,
            2,
            pg_catalog.STATEMENT_TIMESTAMP(),
            stats.source_scan_count,
            LEAST(
                stats.source_byte_count,
                budget.max_source_bytes + 1
            ),
            budget.max_source_bytes,
            stats.source_scan_count > job_row.max_export_rows
                OR stats.source_byte_count > budget.max_source_bytes
                OR stats.source_row_oversize
        FROM snapshot_stats AS stats
        CROSS JOIN snapshot_budget AS budget
        RETURNING source_too_large
    )
    INSERT INTO internal.export_job_source_rows (
        job_id,
        scan_id,
        eligibility_sha256,
        occurrence_payload,
        occurrence_byte_count,
        multimedia_payload,
        multimedia_byte_count
    )
    SELECT
        job_row.id,
        rows.scan_id,
        extensions.digest(rows.eligibility_payload::TEXT, 'sha256'),
        rows.occurrence_payload,
        rows.occurrence_byte_count,
        rows.multimedia_payload,
        rows.multimedia_byte_count
    FROM snapshot_rows AS rows
    CROSS JOIN inserted_state AS source_state
    WHERE source_state.source_too_large = FALSE
    ORDER BY rows.scan_id;
END;
$$;

COMMENT ON FUNCTION internal.materialize_dwca_export_source_snapshot(UUID) IS
    'Materializes one bounded immutable DwC-A DTO snapshot and scope-aware live privacy eligibility hashes in a single MVCC statement.';

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

CREATE OR REPLACE FUNCTION internal.purge_dwca_export_source_snapshot()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF OLD.status NOT IN ('completed', 'failed')
       AND NEW.status IN ('completed', 'failed') THEN
        DELETE FROM internal.export_job_source_rows AS source_rows
        WHERE source_rows.job_id = NEW.id;

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

CREATE TRIGGER initialize_dwca_export_source_snapshot
AFTER INSERT ON public.export_jobs
FOR EACH ROW
WHEN (NEW.status IN ('pending', 'processing'))
EXECUTE FUNCTION internal.initialize_dwca_export_source_snapshot();

CREATE TRIGGER purge_dwca_export_source_snapshot
AFTER UPDATE OF status ON public.export_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.purge_dwca_export_source_snapshot();

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
    snapshot_scope TEXT;
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
        source_state.source_too_large,
        jobs.export_scope
    INTO
        canonical_after_id,
        snapshot_too_large,
        snapshot_scope
    FROM public.export_jobs AS jobs
    INNER JOIN internal.export_job_claims AS claims
        ON claims.job_id = jobs.id
    INNER JOIN internal.export_job_work AS work
        ON work.job_id = jobs.id
    INNER JOIN internal.export_job_source_state AS source_state
        ON source_state.job_id = jobs.id
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND claims.claim_token = p_claim_token
      AND claims.lease_expires_at > pg_catalog.NOW()
      AND work.phase = p_expected_phase
      AND source_state.snapshot_version = 2
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
    WITH candidate_rows AS MATERIALIZED (
        SELECT
            source_rows.scan_id,
            source_rows.eligibility_sha256,
            CASE
                WHEN p_expected_phase = 'occurrence'
                    THEN source_rows.occurrence_payload
                ELSE source_rows.multimedia_payload
            END AS immutable_payload,
            CASE
                WHEN p_expected_phase = 'occurrence'
                    THEN source_rows.occurrence_byte_count
                ELSE source_rows.multimedia_byte_count
            END AS immutable_byte_count
        FROM internal.export_job_source_rows AS source_rows
        WHERE source_rows.job_id = p_job_id
          AND (
              p_after_id IS NULL
              OR source_rows.scan_id > p_after_id
          )
        ORDER BY source_rows.scan_id
        LIMIT p_max_rows + 1
    ),
    eligibility_revisions AS MATERIALIZED (
        SELECT
            candidates.scan_id,
            candidates.immutable_payload,
            candidates.immutable_byte_count,
            (
                current_source.scan_id IS NULL
                OR extensions.digest(
                    (
                        CASE
                            WHEN snapshot_scope = 'personal'
                                THEN current_source.personal_eligibility_payload
                            ELSE current_source.global_eligibility_payload
                        END
                    )::TEXT,
                    'sha256'
                ) IS DISTINCT FROM candidates.eligibility_sha256
            ) AS eligibility_changed,
            pg_catalog.ROW_NUMBER() OVER (
                ORDER BY candidates.scan_id
            ) AS row_ordinal
        FROM candidate_rows AS candidates
        LEFT JOIN internal.dwca_export_snapshot_source AS current_source
            ON current_source.scan_id = candidates.scan_id
    ),
    revision_stats AS (
        SELECT COALESCE(
            pg_catalog.BOOL_OR(revisions.eligibility_changed),
            FALSE
        ) AS eligibility_changed
        FROM eligibility_revisions AS revisions
    ),
    running_rows AS MATERIALIZED (
        SELECT
            revisions.scan_id,
            revisions.immutable_payload,
            revisions.immutable_byte_count,
            revisions.row_ordinal,
            pg_catalog.SUM(revisions.immutable_byte_count) OVER (
                ORDER BY revisions.scan_id
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS running_byte_count
        FROM eligibility_revisions AS revisions
        WHERE revisions.eligibility_changed = FALSE
    ),
    bounded_rows AS MATERIALIZED (
        SELECT
            running.scan_id,
            running.immutable_payload,
            running.immutable_byte_count
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
                    SELECT first_row.immutable_byte_count
                    FROM running_rows AS first_row
                    WHERE first_row.row_ordinal = 1
                ),
                0
            )::INTEGER AS first_source_byte_count
    )
    SELECT
        bounded.scan_id,
        bounded.immutable_payload,
        bounded.immutable_byte_count,
        stats.candidate_count = stats.bounded_count,
        FALSE,
        FALSE
    FROM bounded_rows AS bounded
    CROSS JOIN page_stats AS stats
    CROSS JOIN revision_stats AS revisions
    WHERE revisions.eligibility_changed = FALSE

    UNION ALL

    SELECT
        NULL::UUID,
        NULL::JSONB,
        0,
        FALSE,
        FALSE,
        TRUE
    FROM revision_stats AS revisions
    WHERE revisions.eligibility_changed

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
    WHERE revisions.eligibility_changed = FALSE
      AND stats.bounded_count = 0
    ORDER BY 1 NULLS LAST;
END;
$$;

COMMENT ON FUNCTION public.get_dwca_export_scan_batch(
    UUID, UUID, TEXT, UUID, INTEGER, INTEGER
) IS
    'Returns one byte-bounded claim page from immutable creation-time DTO rows, while rejecting deletion or scope-aware live privacy eligibility revocation.';

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
    'Reads byte-bounded immutable creation-time DwC-A DTO rows and enforces scope-aware live privacy eligibility.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;
