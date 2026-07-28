SET lock_timeout = '10s';
SET statement_timeout = '10min';

-- A processing export is visible to its owner through public.export_jobs.
-- Keep the signed archive URL in private work state until the same transaction
-- that passes the final privacy fence marks the job completed.
ALTER TABLE internal.export_job_work
    ADD COLUMN delivery_file_url TEXT,
    ADD CONSTRAINT export_job_work_delivery_url_check
        CHECK (
            delivery_file_url IS NULL
            OR (
                pg_catalog.CHAR_LENGTH(delivery_file_url)
                    BETWEEN 1 AND 4096
                AND delivery_file_url ~ '^https://'
            )
        );

UPDATE internal.export_job_work AS work
SET delivery_file_url = jobs.file_url
FROM public.export_jobs AS jobs
WHERE jobs.id = work.job_id
  AND jobs.status = 'processing'
  AND jobs.file_url IS NOT NULL;

UPDATE public.export_jobs AS jobs
SET file_url = NULL
WHERE jobs.status = 'processing'
  AND jobs.file_url IS NOT NULL;

COMMENT ON COLUMN internal.export_job_work.delivery_file_url IS
    'Private staged signed URL; copied to the owner-visible job only by the final transactionally fenced completion transition.';

-- Terminal transitions already purge immutable source DTOs. Extend that
-- single cleanup boundary to erase the private signed capability as well,
-- including owner-change and watchdog failures that do not pass through the
-- hardened delivery worker.
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

        UPDATE internal.export_job_work AS work
        SET delivery_file_url = NULL,
            updated_at = pg_catalog.NOW()
        WHERE work.job_id = NEW.id
          AND work.delivery_file_url IS NOT NULL;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.purge_dwca_export_source_snapshot()
    FROM PUBLIC, anon, authenticated, service_role;

-- Retain only the dependency metadata needed to invalidate a nonterminal
-- immutable export when the source's privacy eligibility changes. API roles
-- continue to have no direct access to either private table.
ALTER TABLE internal.export_job_source_rows
    ADD COLUMN effective_species_id UUID,
    ADD COLUMN coordinate_protection_required BOOLEAN;

UPDATE internal.export_job_source_rows AS source_rows
SET effective_species_id = NULLIF(
        source_rows.occurrence_payload ->> 'effective_species_id',
        ''
    )::UUID,
    coordinate_protection_required = COALESCE(
        (
            source_rows.occurrence_payload #>>
                '{species_dictionary,iucn_red_list_status}'
        ) IN (
            'vulnerable',
            'endangered',
            'critically_endangered',
            'near_threatened'
        ),
        FALSE
    );

ALTER TABLE internal.export_job_source_rows
    ALTER COLUMN coordinate_protection_required SET NOT NULL;

CREATE INDEX export_job_source_rows_scan_invalidation_idx
    ON internal.export_job_source_rows (scan_id, job_id);

CREATE INDEX export_job_source_rows_species_invalidation_idx
    ON internal.export_job_source_rows (effective_species_id, job_id)
    WHERE effective_species_id IS NOT NULL;

COMMENT ON COLUMN internal.export_job_source_rows.effective_species_id IS
    'Creation-time authoritative species dependency used only to invalidate queued exports when the coordinate-protection boundary changes.';
COMMENT ON COLUMN internal.export_job_source_rows.coordinate_protection_required IS
    'Creation-time protected-species coordinate policy used to detect a later privacy-boundary change.';

ALTER TABLE internal.export_job_source_state
    ADD COLUMN invalidated_at TIMESTAMPTZ,
    ADD COLUMN invalidation_reason TEXT,
    ADD CONSTRAINT export_job_source_state_invalidation_check
        CHECK (
            (
                invalidated_at IS NULL
                AND invalidation_reason IS NULL
            )
            OR (
                invalidated_at IS NOT NULL
                AND invalidation_reason ~ '^[a-z][a-z0-9_]{1,63}$'
                AND invalidated_at >= snapshot_at
            )
        );

COMMENT ON COLUMN internal.export_job_source_state.invalidated_at IS
    'Durable revocation fence set when a queued export no longer satisfies its creation-time privacy eligibility.';
COMMENT ON COLUMN internal.export_job_source_state.invalidation_reason IS
    'Stable internal reason code for a durable source revocation; never exposed as provider or schema detail.';

-- Build one immutable snapshot under the export-job insertion statement's MVCC
-- snapshot without constructing every DTO before checking the aggregate byte
-- budget. The cursor is consumed one row at a time and projection stops at the
-- first per-row or cumulative violation.
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
    source_cursor REFCURSOR := 'dwca_export_snapshot_cursor';
    source_row RECORD;
    snapshot_at TIMESTAMPTZ := pg_catalog.STATEMENT_TIMESTAMP();
    max_source_bytes BIGINT;
    eligible_scan_count INTEGER;
    inserted_scan_count INTEGER := 0;
    source_byte_count BIGINT := 0;
    occurrence_payload JSONB;
    eligibility_payload JSONB;
    occurrence_byte_count INTEGER;
    multimedia_byte_count INTEGER;
    snapshot_too_large BOOLEAN := FALSE;
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

    max_source_bytes := LEAST(
        67108864::BIGINT,
        job_row.max_archive_bytes * 4
    );

    -- Count only UUIDs up to the canonical row ceiling plus one. No source DTO
    -- or unbounded aggregate is built for a cardinality-rejected request.
    IF job_row.export_scope = 'personal' THEN
        SELECT pg_catalog.COUNT(*)::INTEGER
        INTO eligible_scan_count
        FROM (
            SELECT scans.id
            FROM public.scans AS scans
            WHERE scans.user_id = job_row.user_id
              AND scans.is_live_capture = TRUE
              AND scans.is_tombstoned = FALSE
              AND scans.ecology_type <> 'domesticated'
            ORDER BY scans.id
            LIMIT job_row.max_export_rows + 1
        ) AS bounded_membership;
    ELSE
        SELECT pg_catalog.COUNT(*)::INTEGER
        INTO eligible_scan_count
        FROM (
            SELECT scans.id
            FROM public.scans AS scans
            WHERE scans.geoprivacy = 'open'
              AND scans.is_live_capture = TRUE
              AND scans.is_tombstoned = FALSE
              AND scans.ecology_type <> 'domesticated'
            ORDER BY scans.id
            LIMIT job_row.max_export_rows + 1
        ) AS bounded_membership;
    END IF;

    IF eligible_scan_count > job_row.max_export_rows THEN
        INSERT INTO internal.export_job_source_state (
            job_id,
            snapshot_version,
            snapshot_at,
            source_scan_count,
            source_byte_count,
            max_source_bytes,
            source_too_large
        )
        VALUES (
            job_row.id,
            2,
            snapshot_at,
            eligible_scan_count,
            0,
            max_source_bytes,
            TRUE
        );
        RETURN;
    END IF;

    IF job_row.export_scope = 'personal' THEN
        OPEN source_cursor FOR
        SELECT source.*
        FROM (
            SELECT scans.id AS scan_id
            FROM public.scans AS scans
            WHERE scans.user_id = job_row.user_id
              AND scans.is_live_capture = TRUE
              AND scans.is_tombstoned = FALSE
              AND scans.ecology_type <> 'domesticated'
            ORDER BY scans.id
            LIMIT job_row.max_export_rows
        ) AS eligible
        CROSS JOIN LATERAL (
            SELECT projected.*
            FROM internal.dwca_export_snapshot_source AS projected
            WHERE projected.scan_id = eligible.scan_id
            LIMIT 1
        ) AS source;
    ELSE
        OPEN source_cursor FOR
        SELECT source.*
        FROM (
            SELECT scans.id AS scan_id
            FROM public.scans AS scans
            WHERE scans.geoprivacy = 'open'
              AND scans.is_live_capture = TRUE
              AND scans.is_tombstoned = FALSE
              AND scans.ecology_type <> 'domesticated'
            ORDER BY scans.id
            LIMIT job_row.max_export_rows
        ) AS eligible
        CROSS JOIN LATERAL (
            SELECT projected.*
            FROM internal.dwca_export_snapshot_source AS projected
            WHERE projected.scan_id = eligible.scan_id
            LIMIT 1
        ) AS source;
    END IF;

    LOOP
        FETCH source_cursor INTO source_row;
        EXIT WHEN NOT FOUND;

        eligibility_payload := CASE
            WHEN job_row.export_scope = 'personal'
                THEN source_row.personal_eligibility_payload
            ELSE source_row.global_eligibility_payload
        END;

        occurrence_payload := CASE
            WHEN job_row.export_scope = 'personal'
                 AND job_row.include_precise_coordinates
                 AND source_row.coordinate_protection_required = FALSE
                THEN source_row.occurrence_payload
            ELSE source_row.occurrence_payload
                - ARRAY['gps_lat_exact', 'gps_long_exact']::TEXT[]
        END;

        occurrence_byte_count := pg_catalog.OCTET_LENGTH(
            occurrence_payload::TEXT
        )::INTEGER;
        multimedia_byte_count := pg_catalog.OCTET_LENGTH(
            source_row.multimedia_payload::TEXT
        )::INTEGER;

        IF occurrence_byte_count > 262144
           OR multimedia_byte_count > 262144
           OR source_byte_count
                + occurrence_byte_count::BIGINT
                + multimedia_byte_count::BIGINT > max_source_bytes THEN
            snapshot_too_large := TRUE;
            source_byte_count := max_source_bytes + 1;
            EXIT;
        END IF;

        INSERT INTO internal.export_job_source_rows (
            job_id,
            scan_id,
            eligibility_sha256,
            occurrence_payload,
            occurrence_byte_count,
            multimedia_payload,
            multimedia_byte_count,
            effective_species_id,
            coordinate_protection_required
        )
        VALUES (
            job_row.id,
            source_row.scan_id,
            extensions.digest(eligibility_payload::TEXT, 'sha256'),
            occurrence_payload,
            occurrence_byte_count,
            source_row.multimedia_payload,
            multimedia_byte_count,
            source_row.effective_species_id,
            source_row.coordinate_protection_required
        );

        inserted_scan_count := inserted_scan_count + 1;
        source_byte_count := source_byte_count
            + occurrence_byte_count::BIGINT
            + multimedia_byte_count::BIGINT;
    END LOOP;

    CLOSE source_cursor;

    IF snapshot_too_large THEN
        DELETE FROM internal.export_job_source_rows AS source_rows
        WHERE source_rows.job_id = job_row.id;
    ELSIF inserted_scan_count <> eligible_scan_count THEN
        RAISE EXCEPTION 'dwca_export_snapshot_membership_changed'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO internal.export_job_source_state (
        job_id,
        snapshot_version,
        snapshot_at,
        source_scan_count,
        source_byte_count,
        max_source_bytes,
        source_too_large
    )
    VALUES (
        job_row.id,
        2,
        snapshot_at,
        eligible_scan_count,
        source_byte_count,
        max_source_bytes,
        snapshot_too_large
    );
END;
$$;

COMMENT ON FUNCTION internal.materialize_dwca_export_source_snapshot(UUID) IS
    'Streams one creation-statement MVCC snapshot into bounded immutable DwC-A DTO rows and stops projection at the first row or aggregate byte-budget violation.';

REVOKE ALL ON FUNCTION internal.materialize_dwca_export_source_snapshot(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

-- One full-set predicate is shared by assembly, staging, delivery, and
-- completion. It validates every creation-time member, not merely the rows
-- after a phase cursor.
CREATE OR REPLACE FUNCTION internal.dwca_export_source_is_current(
    p_job_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
    SELECT COALESCE(
        (
            SELECT
                source_state.snapshot_version = 2
                AND source_state.source_too_large = FALSE
                AND source_state.purged_at IS NULL
                AND source_state.invalidated_at IS NULL
                AND source_state.source_scan_count = (
                    SELECT pg_catalog.COUNT(*)::INTEGER
                    FROM internal.export_job_source_rows AS counted_rows
                    WHERE counted_rows.job_id = jobs.id
                )
                AND NOT EXISTS (
                    SELECT 1
                    FROM internal.export_job_source_rows AS source_rows
                    LEFT JOIN LATERAL (
                        SELECT
                            projected.scan_id,
                            projected.personal_eligibility_payload,
                            projected.global_eligibility_payload
                        FROM internal.dwca_export_snapshot_source
                            AS projected
                        WHERE projected.scan_id = source_rows.scan_id
                        LIMIT 1
                    ) AS current_source
                        ON TRUE
                    WHERE source_rows.job_id = jobs.id
                      AND (
                          current_source.scan_id IS NULL
                          OR extensions.digest(
                              (
                                  CASE
                                      WHEN jobs.export_scope = 'personal'
                                          THEN current_source.personal_eligibility_payload
                                      ELSE current_source.global_eligibility_payload
                                  END
                              )::TEXT,
                              'sha256'
                          ) IS DISTINCT FROM
                              source_rows.eligibility_sha256
                      )
                )
            FROM public.export_jobs AS jobs
            INNER JOIN internal.export_job_source_state AS source_state
                ON source_state.job_id = jobs.id
            WHERE jobs.id = p_job_id
        ),
        FALSE
    );
$$;

COMMENT ON FUNCTION internal.dwca_export_source_is_current(UUID) IS
    'Private full-membership privacy fence for a nonterminal immutable DwC-A source snapshot.';

REVOKE ALL ON FUNCTION internal.dwca_export_source_is_current(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

-- Persist revocation as soon as a scan's scope eligibility changes. Ordinary
-- immutable content edits remain valid; they do not alter the privacy boundary
-- and the archive continues to use its creation-time DTO.
CREATE OR REPLACE FUNCTION internal.invalidate_dwca_exports_for_scan()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_scan_id UUID;
    invalidate_all_scopes BOOLEAN := FALSE;
    invalidate_global_scope BOOLEAN := FALSE;
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        UPDATE internal.export_job_source_state AS source_state
        SET invalidated_at = COALESCE(
                source_state.invalidated_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            invalidation_reason = COALESCE(
                source_state.invalidation_reason,
                'scan_catalog_replaced'
            )
        FROM public.export_jobs AS jobs
        WHERE jobs.id = source_state.job_id
          AND jobs.status IN ('pending', 'processing')
          AND source_state.purged_at IS NULL
          AND EXISTS (
              SELECT 1
              FROM internal.export_job_source_rows AS source_rows
              WHERE source_rows.job_id = source_state.job_id
          );
        RETURN NULL;
    ELSIF TG_OP = 'DELETE' THEN
        target_scan_id := OLD.id;
        invalidate_all_scopes := TRUE;
    ELSE
        target_scan_id := NEW.id;
        invalidate_all_scopes :=
            NEW.user_id IS DISTINCT FROM OLD.user_id
            OR NEW.is_live_capture IS DISTINCT FROM OLD.is_live_capture
            OR NEW.is_tombstoned IS DISTINCT FROM OLD.is_tombstoned
            OR NEW.ecology_type IS DISTINCT FROM OLD.ecology_type
            OR NEW.species_id IS DISTINCT FROM OLD.species_id
            OR NEW.confirmed_species_id
                IS DISTINCT FROM OLD.confirmed_species_id;
        invalidate_global_scope := invalidate_all_scopes
            OR NEW.geoprivacy IS DISTINCT FROM OLD.geoprivacy;
    END IF;

    IF invalidate_all_scopes OR invalidate_global_scope THEN
        UPDATE internal.export_job_source_state AS source_state
        SET invalidated_at = COALESCE(
                source_state.invalidated_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            invalidation_reason = COALESCE(
                source_state.invalidation_reason,
                'scan_eligibility_changed'
            )
        FROM internal.export_job_source_rows AS source_rows,
             public.export_jobs AS jobs
        WHERE source_rows.scan_id = target_scan_id
          AND source_state.job_id = source_rows.job_id
          AND jobs.id = source_state.job_id
          AND jobs.status IN ('pending', 'processing')
          AND source_state.purged_at IS NULL
          AND (
              invalidate_all_scopes
              OR jobs.export_scope = 'global'
          );
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.invalidate_dwca_exports_for_scan()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_scan
    ON public.scans;
CREATE TRIGGER invalidate_dwca_exports_for_scan
AFTER DELETE OR UPDATE OF
    user_id,
    is_live_capture,
    is_tombstoned,
    ecology_type,
    geoprivacy,
    species_id,
    confirmed_species_id
ON public.scans
FOR EACH ROW
EXECUTE FUNCTION internal.invalidate_dwca_exports_for_scan();

DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_scan_truncate
    ON public.scans;
CREATE TRIGGER invalidate_dwca_exports_for_scan_truncate
AFTER TRUNCATE ON public.scans
FOR EACH STATEMENT
EXECUTE FUNCTION internal.invalidate_dwca_exports_for_scan();

-- A conservation-status edit is a privacy edit when it crosses the protected
-- coordinate boundary. Revoke dependent queued jobs without invalidating
-- unrelated taxonomy copy changes.
CREATE OR REPLACE FUNCTION internal.invalidate_dwca_exports_for_species()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    target_species_id UUID;
    protection_required BOOLEAN;
BEGIN
    IF TG_OP = 'TRUNCATE' THEN
        UPDATE internal.export_job_source_state AS source_state
        SET invalidated_at = COALESCE(
                source_state.invalidated_at,
                pg_catalog.CLOCK_TIMESTAMP()
            ),
            invalidation_reason = COALESCE(
                source_state.invalidation_reason,
                'species_catalog_replaced'
            )
        FROM public.export_jobs AS jobs
        WHERE jobs.id = source_state.job_id
          AND jobs.status IN ('pending', 'processing')
          AND source_state.purged_at IS NULL
          AND EXISTS (
              SELECT 1
              FROM internal.export_job_source_rows AS source_rows
              WHERE source_rows.job_id = source_state.job_id
                AND source_rows.effective_species_id IS NOT NULL
          );
        RETURN NULL;
    ELSIF TG_OP = 'DELETE' THEN
        target_species_id := OLD.id;
        protection_required := NULL;
    ELSE
        target_species_id := NEW.id;
        protection_required := COALESCE(
            NEW.iucn_red_list_status IN (
                'vulnerable',
                'endangered',
                'critically_endangered',
                'near_threatened'
            ),
            FALSE
        );
    END IF;

    UPDATE internal.export_job_source_state AS source_state
    SET invalidated_at = COALESCE(
            source_state.invalidated_at,
            pg_catalog.CLOCK_TIMESTAMP()
        ),
        invalidation_reason = COALESCE(
            source_state.invalidation_reason,
            'species_protection_changed'
        )
    FROM internal.export_job_source_rows AS source_rows,
         public.export_jobs AS jobs
    WHERE source_rows.effective_species_id = target_species_id
      AND source_state.job_id = source_rows.job_id
      AND jobs.id = source_state.job_id
      AND jobs.status IN ('pending', 'processing')
      AND source_state.purged_at IS NULL
      AND (
          TG_OP = 'DELETE'
          OR source_rows.coordinate_protection_required
              IS DISTINCT FROM protection_required
      );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.invalidate_dwca_exports_for_species()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_species
    ON public.species_dictionary;
CREATE TRIGGER invalidate_dwca_exports_for_species
AFTER DELETE OR UPDATE OF iucn_red_list_status
ON public.species_dictionary
FOR EACH ROW
EXECUTE FUNCTION internal.invalidate_dwca_exports_for_species();

DROP TRIGGER IF EXISTS invalidate_dwca_exports_for_species_truncate
    ON public.species_dictionary;
CREATE TRIGGER invalidate_dwca_exports_for_species_truncate
AFTER TRUNCATE ON public.species_dictionary
FOR EACH STATEMENT
EXECUTE FUNCTION internal.invalidate_dwca_exports_for_species();

-- Mark any already queued snapshot that changed before the invalidation
-- triggers were installed. This closes the migration cutover window without
-- rebuilding immutable content or silently accepting a stale privacy boundary.
UPDATE internal.export_job_source_state AS source_state
SET invalidated_at = pg_catalog.CLOCK_TIMESTAMP(),
    invalidation_reason = 'migration_privacy_revalidation'
FROM public.export_jobs AS jobs
WHERE jobs.id = source_state.job_id
  AND jobs.status IN ('pending', 'processing')
  AND source_state.purged_at IS NULL
  AND NOT internal.dwca_export_source_is_current(source_state.job_id);

-- Workers call this full-set fence before beginning assembly and immediately
-- before delivery. Staging and completion repeat the same predicate inside
-- their own transactions, so a caller cannot bypass it through call ordering.
CREATE OR REPLACE FUNCTION public.check_dwca_export_source_fence(
    p_job_id UUID,
    p_claim_token UUID,
    p_expected_phase TEXT
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_job_id IS NULL
       OR p_claim_token IS NULL
       OR p_expected_phase IS NULL
       OR p_expected_phase NOT IN ('assembling', 'delivering') THEN
        RAISE EXCEPTION 'invalid_dwca_export_source_fence'
            USING ERRCODE = '22023';
    END IF;

    PERFORM 1
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
      AND source_state.purged_at IS NULL
    FOR SHARE OF jobs, claims, work, source_state;

    IF NOT FOUND THEN
        RETURN 'claim_lost';
    END IF;

    IF NOT internal.dwca_export_source_is_current(p_job_id) THEN
        RETURN 'source_snapshot_changed';
    END IF;

    RETURN 'current';
END;
$$;

COMMENT ON FUNCTION public.check_dwca_export_source_fence(
    UUID, UUID, TEXT
) IS
    'Service-only full-membership privacy fence run before DwC-A assembly and delivery.';

REVOKE ALL ON FUNCTION public.check_dwca_export_source_fence(
    UUID, UUID, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_dwca_export_source_fence(
    UUID, UUID, TEXT
) TO service_role;

-- Preserve the existing claim DTO while sourcing a staged delivery URL from
-- private work state. This makes the rollout compatible with both the current
-- worker and the hardened worker without exposing the URL through the
-- user-readable processing job.
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
        COALESCE(job_row.file_url, work_row.delivery_file_url),
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

COMMENT ON FUNCTION public.claim_export_job_step(UUID, UUID) IS
    'Leases one bounded export step; staged signed URLs are returned from private work state and never exposed on processing jobs.';

REVOKE ALL ON FUNCTION public.claim_export_job_step(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_export_job_step(UUID, UUID)
    TO service_role;

-- Accept an uploaded archive only if every immutable source member still
-- satisfies its current scope-aware privacy eligibility. SQLSTATE 55001 is a
-- stable worker signal; no provider or schema detail crosses the RPC boundary.
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
SET statement_timeout = '10s'
AS $$
DECLARE
    job_row public.export_jobs%ROWTYPE;
    work_row internal.export_job_work%ROWTYPE;
    expected_object_key TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_job_id IS NULL
       OR p_claim_token IS NULL
       OR p_archive_object_key IS NULL
       OR p_file_url IS NULL
       OR pg_catalog.CHAR_LENGTH(p_file_url) NOT BETWEEN 1 AND 4096
       OR p_file_url !~ '^https://' THEN
        RAISE EXCEPTION 'invalid_export_archive'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.*
    INTO job_row
    FROM public.export_jobs AS jobs
    INNER JOIN internal.export_job_claims AS claims
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
      AND work.phase = 'assembling'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    PERFORM 1
    FROM internal.export_job_source_state AS source_state
    WHERE source_state.job_id = p_job_id
      AND source_state.purged_at IS NULL
    FOR SHARE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    expected_object_key :=
        'exports/' || job_row.user_id::TEXT || '/' || job_row.id::TEXT || '/'
        || p_claim_token::TEXT || '.zip';

    IF p_archive_object_key IS DISTINCT FROM expected_object_key THEN
        RAISE EXCEPTION 'invalid_export_archive'
            USING ERRCODE = '22023';
    END IF;

    IF NOT internal.dwca_export_source_is_current(p_job_id) THEN
        RAISE EXCEPTION 'dwca_export_source_snapshot_changed'
            USING ERRCODE = '55001';
    END IF;

    UPDATE public.export_jobs AS jobs
    SET archive_object_key = p_archive_object_key,
        file_url = NULL,
        archive_ready_at = pg_catalog.NOW()
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing';

    UPDATE internal.export_job_work AS work
    SET phase = 'delivering',
        delivery_file_url = p_file_url,
        next_step_at = pg_catalog.NOW(),
        retry_count = 0,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE work.job_id = p_job_id
      AND work.phase = work_row.phase;

    DELETE FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.stage_prepared_export_archive(
    UUID, UUID, TEXT, TEXT
) IS
    'Stages an attempt-scoped DwC-A archive and private delivery URL only after atomically revalidating every creation-time privacy member.';

REVOKE ALL ON FUNCTION public.stage_prepared_export_archive(
    UUID, UUID, TEXT, TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.stage_prepared_export_archive(
    UUID, UUID, TEXT, TEXT
) TO service_role;

-- Completion repeats the full source fence. Delivery also checks before its
-- external email call; this database transition prevents a delayed or replayed
-- worker from publishing a job after a concurrent privacy revocation.
CREATE OR REPLACE FUNCTION public.complete_prepared_export_job(
    p_job_id UUID,
    p_claim_token UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    job_row public.export_jobs%ROWTYPE;
    work_row internal.export_job_work%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();

    SELECT jobs.*
    INTO job_row
    FROM public.export_jobs AS jobs
    INNER JOIN internal.export_job_claims AS claims
        ON claims.job_id = jobs.id
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing'
      AND jobs.archive_object_key IS NOT NULL
      AND jobs.archive_ready_at IS NOT NULL
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
      AND work.phase = 'delivering'
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF work_row.delivery_file_url IS NULL THEN
        RETURN FALSE;
    END IF;

    PERFORM 1
    FROM internal.export_job_source_state AS source_state
    WHERE source_state.job_id = p_job_id
      AND source_state.purged_at IS NULL
    FOR SHARE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF NOT internal.dwca_export_source_is_current(p_job_id) THEN
        RAISE EXCEPTION 'dwca_export_source_snapshot_changed'
            USING ERRCODE = '55001';
    END IF;

    -- This intermediate update and the completed transition are part of one
    -- transaction. Other sessions can never observe a processing row carrying
    -- the signed URL.
    UPDATE public.export_jobs AS jobs
    SET file_url = work_row.delivery_file_url
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing';

    UPDATE public.export_jobs AS jobs
    SET status = 'completed',
        completed_at = pg_catalog.NOW()
    WHERE jobs.id = p_job_id
      AND jobs.status = 'processing';

    UPDATE internal.export_job_work AS work
    SET phase = 'completed',
        delivery_file_url = NULL,
        updated_at = pg_catalog.NOW()
    WHERE work.job_id = p_job_id
      AND work.phase = work_row.phase;

    DELETE FROM internal.export_job_claims AS claims
    WHERE claims.job_id = p_job_id
      AND claims.claim_token = p_claim_token;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.complete_prepared_export_job(UUID, UUID) IS
    'Completes a delivered DwC-A job only after atomically revalidating every creation-time privacy member.';

REVOKE ALL ON FUNCTION public.complete_prepared_export_job(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_prepared_export_job(UUID, UUID)
    TO service_role;

-- The public-web detail RPC now carries its own canonical card-visibility
-- predicate. It remains safe even if a future caller invokes detail without
-- first fetching a card.
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
    INNER JOIN public.explore_projected_post_cards(
        NULL::UUID
    ) AS canonical_post
        ON canonical_post.post_id = detail.post_id
    WHERE canonical_post.post_id = p_target_post_id
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_public_web_explore_post_detail(UUID) IS
    'Service-only public-web detail projection that independently requires the canonical anonymous moderation, publication, media-health, tombstone, and block visibility boundary.';

REVOKE ALL ON FUNCTION public.get_public_web_explore_post_detail(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_web_explore_post_detail(UUID)
    TO service_role;

-- Page rendering receives card and detail from one database statement and one
-- MVCC snapshot. This removes the web layer's check-then-fetch race while
-- retaining the independently safe card and detail routines for other callers.
CREATE OR REPLACE FUNCTION public.get_public_web_explore_post_page(
    p_target_post_id UUID
)
RETURNS TABLE(
    post_payload JSONB,
    detail_payload JSONB
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
        pg_catalog.TO_JSONB(post_row),
        CASE
            WHEN detail_row.post_id IS NULL THEN NULL::JSONB
            ELSE pg_catalog.TO_JSONB(detail_row)
        END
    FROM public.get_public_web_explore_posts(
        p_target_post_id,
        1
    ) AS post_row
    LEFT JOIN LATERAL public.get_public_web_explore_post_detail(
        p_target_post_id
    ) AS detail_row
        ON TRUE
    LIMIT 1;
END;
$$;

COMMENT ON FUNCTION public.get_public_web_explore_post_page(UUID) IS
    'Returns one canonical anonymous Explore card and its independently gated detail from a single MVCC statement to the server-only public web application.';

REVOKE ALL ON FUNCTION public.get_public_web_explore_post_page(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_public_web_explore_post_page(UUID)
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.check_dwca_export_source_fence(uuid,uuid,text)',
        'Revalidates every immutable DwC-A source member before assembly and delivery.'
    ),
    (
        'service_role',
        'public.get_public_web_explore_post_page(uuid)',
        'Returns one canonical public Explore card and detail from one server-only MVCC snapshot.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

-- Keep the existing allowlist descriptions aligned with the strengthened
-- contracts after CREATE OR REPLACE preserves their signatures.
UPDATE internal.privileged_routine_grants AS grants
SET purpose = CASE grants.routine_signature
    WHEN 'public.claim_export_job_step(uuid,uuid)' THEN
        'Leases one bounded DwC-A step and returns staged delivery URLs only from private work state.'
    WHEN 'public.stage_prepared_export_archive(uuid,uuid,text,text)' THEN
        'Stages a bounded DwC-A archive and private delivery URL only after full-membership privacy revalidation.'
    WHEN 'public.complete_prepared_export_job(uuid,uuid)' THEN
        'Completes a DwC-A export only after full-membership privacy revalidation.'
    WHEN 'public.get_public_web_explore_post_detail(uuid)' THEN
        'Returns independently canonical moderation/publication-gated Explore detail to the server-only public web application.'
    ELSE grants.purpose
END
WHERE grants.role_name = 'service_role'
  AND grants.routine_signature IN (
      'public.claim_export_job_step(uuid,uuid)',
      'public.stage_prepared_export_archive(uuid,uuid,text,text)',
      'public.complete_prepared_export_job(uuid,uuid)',
      'public.get_public_web_explore_post_detail(uuid)'
  );

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;
