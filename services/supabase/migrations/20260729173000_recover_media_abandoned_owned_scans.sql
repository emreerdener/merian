-- A completed local observation can outlive its cloud owner row when the
-- asynchronous media reconciler exhausts the last server-side staging object.
-- The authenticated app still has the durable result and original media, but
-- recover_missing_owned_scan previously allowed only replay_exhausted terminal
-- jobs. Keep recovery fail-closed while admitting the explicit
-- media_reconciliation_abandoned reason through the same service-only,
-- owner-scoped, tombstone-aware transaction.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE INDEX IF NOT EXISTS failed_scan_ingestions_user_scan_idx
    ON public.failed_scan_ingestions (user_id, scan_id);

CREATE OR REPLACE FUNCTION public.recover_missing_owned_scan(
    p_scan_id UUID,
    p_user_id UUID,
    p_recovery_scan JSONB
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    recovered RECORD;
    ingestion_job RECORD;
    inserted_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR pg_catalog.JSONB_TYPEOF(p_recovery_scan) <> 'object'
       OR pg_catalog.OCTET_LENGTH(p_recovery_scan::TEXT) > 65536 THEN
        RAISE EXCEPTION 'invalid_scan_recovery'
            USING ERRCODE = '22023';
    END IF;

    SELECT payload.*
    INTO STRICT recovered
    FROM pg_catalog.JSONB_TO_RECORD(p_recovery_scan) AS payload(
        id UUID,
        user_id UUID,
        species_id UUID,
        confirmed_species_id UUID,
        image_storage_urls TEXT[],
        "timestamp" TIMESTAMPTZ,
        gps_lat_exact DOUBLE PRECISION,
        gps_long_exact DOUBLE PRECISION,
        gps_elevation DOUBLE PRECISION,
        geoprivacy TEXT,
        weather_condition TEXT,
        weather_temperature_f DOUBLE PRECISION,
        ai_confidence_score DOUBLE PRECISION,
        ecology_type TEXT,
        is_invasive BOOLEAN,
        invasive_status_region TEXT,
        invasive_rationale TEXT,
        invasive_confidence DOUBLE PRECISION,
        is_live_capture BOOLEAN,
        is_biological_subject BOOLEAN,
        ai_reasoning TEXT,
        semantic_location TEXT,
        public_location_label TEXT,
        inference_tier TEXT,
        image_quality_score INTEGER,
        user_identification_override TEXT,
        user_confirmed_identification BOOLEAN,
        user_review_state TEXT
    );

    IF recovered.id IS DISTINCT FROM p_scan_id
       OR recovered.user_id IS DISTINCT FROM p_user_id
       OR recovered.image_storage_urls IS DISTINCT FROM '{}'::TEXT[]
       OR recovered."timestamp" IS NULL
       OR recovered.geoprivacy IS NULL
       OR recovered.geoprivacy NOT IN ('open', 'obscured', 'private')
       OR recovered.ecology_type IS NULL
       OR recovered.ecology_type NOT IN (
            'wild',
            'urban',
            'domesticated',
            'unknown'
       )
       OR recovered.user_review_state IS NULL
       OR recovered.user_review_state NOT IN (
            'unreviewed',
            'ai_confirmed',
            'user_overridden'
       )
       OR recovered.ai_confidence_score IS NULL
       OR recovered.ai_confidence_score NOT BETWEEN 0 AND 1
       OR recovered.is_invasive IS NULL
       OR recovered.is_live_capture IS NULL
       OR recovered.is_biological_subject IS NULL
       OR recovered.user_confirmed_identification IS NULL
       OR (
            recovered.gps_lat_exact IS NULL
            AND recovered.gps_long_exact IS NOT NULL
       )
       OR (
            recovered.gps_lat_exact IS NOT NULL
            AND recovered.gps_long_exact IS NULL
       )
       OR recovered.gps_lat_exact NOT BETWEEN -90 AND 90
       OR recovered.gps_long_exact NOT BETWEEN -180 AND 180
       OR recovered.gps_elevation NOT BETWEEN -500 AND 9500
       OR recovered.weather_temperature_f NOT BETWEEN -200 AND 200
       OR recovered.invasive_confidence NOT BETWEEN 0 AND 1
       OR recovered.image_quality_score NOT BETWEEN 0 AND 100
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.inference_tier, '')
       ) NOT BETWEEN 1 AND 64
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.weather_condition, '')
       ) > 200
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.invasive_status_region, '')
       ) > 500
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.invasive_rationale, '')
       ) > 2000
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.ai_reasoning, '')
       ) > 10000
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.semantic_location, '')
       ) > 1000
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(recovered.public_location_label, '')
       ) > 500
       OR pg_catalog.CHAR_LENGTH(
            COALESCE(
                recovered.user_identification_override,
                ''
            )
       ) > 500 THEN
        RAISE EXCEPTION 'invalid_scan_recovery'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || p_scan_id::TEXT,
            0::BIGINT
        )
    );

    IF EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = p_scan_id
    ) THEN
        RETURN 'deleted';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
    ) THEN
        RETURN 'already_present';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = p_scan_id
          AND scans.user_id IS DISTINCT FROM p_user_id
    ) THEN
        RETURN 'id_collision';
    END IF;

    SELECT jobs.status, jobs.terminal_reason_code
    INTO ingestion_job
    FROM public.scan_ingestion_jobs AS jobs
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN 'deferred';
    END IF;
    IF ingestion_job.status <> 'complete'
       AND NOT (
           ingestion_job.status = 'failed_terminal'
           AND (
                ingestion_job.terminal_reason_code = 'replay_exhausted'
                OR (
                    ingestion_job.terminal_reason_code =
                        'media_reconciliation_abandoned'
                    AND EXISTS (
                        SELECT 1
                        FROM public.failed_scan_ingestions AS failures
                        WHERE failures.scan_id = p_scan_id::TEXT
                          AND failures.user_id = p_user_id
                    )
                )
           )
       ) THEN
        RETURN 'deferred';
    END IF;

    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        confirmed_species_id,
        image_storage_urls,
        "timestamp",
        gps_lat_exact,
        gps_long_exact,
        gps_lat_public,
        gps_long_public,
        gps_elevation,
        geoprivacy,
        weather_condition,
        weather_temperature_f,
        ai_confidence_score,
        ecology_type,
        is_invasive,
        invasive_status_region,
        invasive_rationale,
        invasive_confidence,
        is_live_capture,
        is_biological_subject,
        ai_reasoning,
        semantic_location,
        public_location_label,
        inference_tier,
        image_quality_score,
        user_identification_override,
        user_confirmed_identification,
        user_review_state
    )
    VALUES (
        recovered.id,
        recovered.user_id,
        recovered.species_id,
        recovered.confirmed_species_id,
        '{}'::TEXT[],
        recovered."timestamp",
        recovered.gps_lat_exact,
        recovered.gps_long_exact,
        CASE
            WHEN recovered.geoprivacy = 'open'
                THEN recovered.gps_lat_exact
            ELSE NULL
        END,
        CASE
            WHEN recovered.geoprivacy = 'open'
                THEN recovered.gps_long_exact
            ELSE NULL
        END,
        recovered.gps_elevation,
        recovered.geoprivacy::public.geoprivacy_enum,
        recovered.weather_condition,
        recovered.weather_temperature_f,
        recovered.ai_confidence_score,
        recovered.ecology_type::public.ecology_type_enum,
        recovered.is_invasive,
        recovered.invasive_status_region,
        recovered.invasive_rationale,
        recovered.invasive_confidence,
        recovered.is_live_capture,
        recovered.is_biological_subject,
        recovered.ai_reasoning,
        recovered.semantic_location,
        CASE
            WHEN recovered.geoprivacy = 'private' THEN NULL
            ELSE recovered.public_location_label
        END,
        recovered.inference_tier,
        recovered.image_quality_score,
        recovered.user_identification_override,
        recovered.user_confirmed_identification,
        recovered.user_review_state::public.user_review_state
    )
    ON CONFLICT (id) DO NOTHING
    RETURNING id INTO inserted_id;

    IF inserted_id IS NULL THEN
        RETURN 'id_collision';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'merian.scan_ingestion_completion_fence',
        p_user_id::TEXT || ':' || p_scan_id::TEXT,
        TRUE
    );

    INSERT INTO public.scan_ingestion_jobs AS existing_job (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        attempt_count,
        media_counts,
        media_object_keys,
        upload_session_ids,
        locked_at,
        lock_expires_at,
        retry_after,
        last_error,
        terminal_reason_code,
        completed_at,
        updated_at
    )
    VALUES (
        p_scan_id::TEXT,
        p_user_id,
        'client-recovery',
        'complete',
        'client_recovery_complete',
        0,
        '{}'::JSONB,
        '{}'::JSONB,
        '{}'::UUID[],
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        pg_catalog.NOW(),
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE
    SET status = 'complete',
        stage = 'client_recovery_complete',
        locked_at = NULL,
        lock_expires_at = NULL,
        retry_after = NULL,
        last_error = NULL,
        terminal_reason_code = NULL,
        completed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW();

    RETURN 'recovered';
END;
$$;

REVOKE ALL ON FUNCTION public.recover_missing_owned_scan(UUID, UUID, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recover_missing_owned_scan(
    UUID,
    UUID,
    JSONB
) TO service_role;

COMMENT ON FUNCTION public.recover_missing_owned_scan(UUID, UUID, JSONB) IS
    'Service-only, per-scan-locked reconstruction of an absent authenticated-owner scan from a normalized non-media payload. Allows complete, replay_exhausted, or media_reconciliation_abandoned ledgers with exact service-written post-result dead-letter proof; deletion tombstones, active/retryable/policy/unproven/unknown terminal jobs, and ID collisions fail closed.';

RESET statement_timeout;
RESET lock_timeout;
