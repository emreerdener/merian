-- Latency-critical scan ingestion primitives.
--
-- These service-role-only RPCs collapse the pre/post inference database work
-- into one round trip. Deferred environmental context is staged durably and
-- merged whether it arrives before or after the scan row is inserted.

CREATE OR REPLACE FUNCTION public.begin_scan_ingestion(
    p_scan_id TEXT,
    p_user_id UUID,
    p_endpoint TEXT,
    p_request_payload JSONB,
    p_media_counts JSONB DEFAULT '{}'::JSONB,
    p_media_object_keys JSONB DEFAULT '{}'::JSONB,
    p_storage_keys TEXT[] DEFAULT '{}'::TEXT[],
    p_manifest_checksum TEXT DEFAULT NULL,
    p_payload_checksum TEXT DEFAULT NULL,
    p_resumable BOOLEAN DEFAULT TRUE,
    p_inline_media_redacted BOOLEAN DEFAULT FALSE,
    p_redacted_media_counts JSONB DEFAULT '{}'::JSONB,
    p_payload_schema_version INTEGER DEFAULT 1,
    p_lease_seconds INTEGER DEFAULT 300
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    resolved_upload_session_ids UUID[] := '{}'::UUID[];
    lease_seconds INTEGER := GREATEST(COALESCE(p_lease_seconds, 300), 30);
    scan_id_uuid UUID;
    manifest_payload JSONB;
    resolved_manifest_checksum TEXT;
    resolved_payload_checksum TEXT;
    stored_payload JSONB;
BEGIN
    IF COALESCE(BTRIM(p_scan_id), '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'scan_id must be a UUID';
    END IF;
    scan_id_uuid := p_scan_id::UUID;

    SELECT COALESCE(ARRAY_AGG(DISTINCT asset.upload_session_id ORDER BY asset.upload_session_id), '{}'::UUID[])
      INTO resolved_upload_session_ids
     FROM public.scan_media_assets AS asset
     WHERE asset.user_id = p_user_id
       AND asset.client_scan_id = scan_id_uuid
       AND asset.source = 'capture_upload'
       AND asset.storage_key = ANY(COALESCE(p_storage_keys, '{}'::TEXT[]));

    -- The caller has not seen the upload sessions yet. Canonicalize both
    -- checksums only after the lookup so the ledger always describes the
    -- payload actually stored by this atomic RPC. The checksum parameters are
    -- retained solely for rolling-client signature compatibility.
    manifest_payload := JSONB_BUILD_OBJECT(
        'mediaCounts', COALESCE(p_media_counts, '{}'::JSONB),
        'mediaObjectKeys', COALESCE(p_media_object_keys, '{}'::JSONB),
        'uploadSessionIds', TO_JSONB(resolved_upload_session_ids)
    );
    resolved_manifest_checksum := ENCODE(
        SHA256(CONVERT_TO(manifest_payload::TEXT, 'UTF8')),
        'hex'
    );

    stored_payload := JSONB_SET(
        JSONB_SET(
            COALESCE(p_request_payload, '{}'::JSONB),
            '{uploadSessionIds}',
            TO_JSONB(resolved_upload_session_ids),
            TRUE
        ),
        '{manifestChecksum}',
        TO_JSONB(resolved_manifest_checksum),
        TRUE
    );
    resolved_payload_checksum := ENCODE(
        SHA256(CONVERT_TO(stored_payload::TEXT, 'UTF8')),
        'hex'
    );

    INSERT INTO public.scan_ingestion_jobs (
        scan_id, user_id, endpoint, status, stage, attempt_count,
        media_counts, media_object_keys, upload_session_ids,
        manifest_checksum, locked_at, lock_expires_at, retry_after,
        last_error, completed_at, updated_at
    ) VALUES (
        p_scan_id, p_user_id,
        COALESCE(NULLIF(BTRIM(p_endpoint), ''), 'identify-multimodal'),
        'processing', 'ai_inference_started', 1,
        COALESCE(p_media_counts, '{}'::JSONB),
        COALESCE(p_media_object_keys, '{}'::JSONB),
        resolved_upload_session_ids,
        resolved_manifest_checksum,
        NOW(), NOW() + MAKE_INTERVAL(secs => lease_seconds),
        NULL, NULL, NULL, NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE SET
        endpoint = EXCLUDED.endpoint,
        status = CASE WHEN scan_ingestion_jobs.status = 'complete' THEN 'complete' ELSE 'processing' END,
        stage = CASE WHEN scan_ingestion_jobs.status = 'complete' THEN scan_ingestion_jobs.stage ELSE 'ai_inference_started' END,
        attempt_count = CASE WHEN scan_ingestion_jobs.status = 'complete' THEN scan_ingestion_jobs.attempt_count ELSE scan_ingestion_jobs.attempt_count + 1 END,
        media_counts = EXCLUDED.media_counts,
        media_object_keys = EXCLUDED.media_object_keys,
        upload_session_ids = EXCLUDED.upload_session_ids,
        manifest_checksum = COALESCE(EXCLUDED.manifest_checksum, scan_ingestion_jobs.manifest_checksum),
        locked_at = CASE WHEN scan_ingestion_jobs.status = 'complete' THEN scan_ingestion_jobs.locked_at ELSE EXCLUDED.locked_at END,
        lock_expires_at = CASE WHEN scan_ingestion_jobs.status = 'complete' THEN scan_ingestion_jobs.lock_expires_at ELSE EXCLUDED.lock_expires_at END,
        retry_after = CASE WHEN scan_ingestion_jobs.status = 'complete' THEN scan_ingestion_jobs.retry_after ELSE NULL END,
        last_error = CASE WHEN scan_ingestion_jobs.status = 'complete' THEN scan_ingestion_jobs.last_error ELSE NULL END,
        updated_at = NOW();

    INSERT INTO public.scan_ingestion_intents (
        scan_id, user_id, endpoint, payload_schema_version, request_payload,
        media_counts, media_object_keys, upload_session_ids,
        manifest_checksum, payload_checksum, resumable,
        inline_media_redacted, redacted_media_counts, claimed_at, updated_at
    ) VALUES (
        p_scan_id, p_user_id,
        COALESCE(NULLIF(BTRIM(p_endpoint), ''), 'identify-multimodal'),
        GREATEST(COALESCE(p_payload_schema_version, 1), 1),
        stored_payload,
        COALESCE(p_media_counts, '{}'::JSONB),
        COALESCE(p_media_object_keys, '{}'::JSONB),
        resolved_upload_session_ids,
        resolved_manifest_checksum,
        resolved_payload_checksum,
        COALESCE(p_resumable, TRUE),
        COALESCE(p_inline_media_redacted, FALSE),
        COALESCE(p_redacted_media_counts, '{}'::JSONB),
        NOW(), NOW()
    )
    ON CONFLICT (user_id, scan_id) DO UPDATE SET
        endpoint = EXCLUDED.endpoint,
        payload_schema_version = EXCLUDED.payload_schema_version,
        request_payload = EXCLUDED.request_payload,
        media_counts = EXCLUDED.media_counts,
        media_object_keys = EXCLUDED.media_object_keys,
        upload_session_ids = EXCLUDED.upload_session_ids,
        manifest_checksum = COALESCE(EXCLUDED.manifest_checksum, scan_ingestion_intents.manifest_checksum),
        payload_checksum = COALESCE(EXCLUDED.payload_checksum, scan_ingestion_intents.payload_checksum),
        resumable = EXCLUDED.resumable,
        inline_media_redacted = EXCLUDED.inline_media_redacted,
        redacted_media_counts = EXCLUDED.redacted_media_counts,
        claimed_at = NOW(),
        updated_at = NOW();

    RETURN JSONB_BUILD_OBJECT(
        'upload_session_ids', TO_JSONB(resolved_upload_session_ids),
        'manifest_checksum', resolved_manifest_checksum,
        'payload_checksum', resolved_payload_checksum,
        'stage', 'ai_inference_started'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.begin_scan_ingestion(
    TEXT, UUID, TEXT, JSONB, JSONB, JSONB, TEXT[], TEXT, TEXT,
    BOOLEAN, BOOLEAN, JSONB, INTEGER, INTEGER
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.begin_scan_ingestion(
    TEXT, UUID, TEXT, JSONB, JSONB, JSONB, TEXT[], TEXT, TEXT,
    BOOLEAN, BOOLEAN, JSONB, INTEGER, INTEGER
) TO service_role;

CREATE OR REPLACE FUNCTION public.hydrate_identification_dictionary(
    p_primary_scientific_name TEXT,
    p_candidate_scientific_names TEXT[] DEFAULT '{}'::TEXT[]
)
RETURNS JSONB
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH primary_species AS (
        SELECT TO_JSONB(species) AS value
          FROM (
              SELECT id, common_names, alternative_common_names, kingdom,
                     phylum, class, "order", family, genus,
                     wikipedia_overview, hazard_type, reference_image_url,
                     wikipedia_url, iucn_red_list_status, habitat_description,
                     gbif_taxon_key, group_tags
                FROM public.species_dictionary
               WHERE scientific_name = NULLIF(BTRIM(p_primary_scientific_name), '')
               LIMIT 1
          ) AS species
    ), candidate_names AS (
        SELECT COALESCE(
            JSONB_OBJECT_AGG(dictionary.scientific_name, dictionary.common_names ->> 'en')
                FILTER (WHERE NULLIF(BTRIM(dictionary.common_names ->> 'en'), '') IS NOT NULL),
            '{}'::JSONB
        ) AS value
          FROM public.species_dictionary AS dictionary
         WHERE dictionary.scientific_name = ANY(COALESCE(p_candidate_scientific_names, '{}'::TEXT[]))
    )
    SELECT JSONB_BUILD_OBJECT(
        'primary', (SELECT value FROM primary_species),
        'candidate_common_names', (SELECT value FROM candidate_names)
    );
$$;

REVOKE ALL ON FUNCTION public.hydrate_identification_dictionary(TEXT, TEXT[])
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hydrate_identification_dictionary(TEXT, TEXT[])
    TO service_role;

CREATE TABLE IF NOT EXISTS public.scan_deferred_context_updates (
    -- A first anonymous scan may claim ingestion before the background ghost-
    -- user upsert commits, so this owner key intentionally has no users FK.
    user_id UUID NOT NULL,
    scan_id UUID NOT NULL,
    context JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, scan_id),
    CONSTRAINT scan_deferred_context_updates_context_object
        CHECK (JSONB_TYPEOF(context) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_scan_deferred_context_updates_created
    ON public.scan_deferred_context_updates(created_at);

ALTER TABLE public.scan_deferred_context_updates ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.merge_staged_scan_context()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    staged JSONB;
BEGIN
    SELECT context INTO staged
      FROM public.scan_deferred_context_updates
     WHERE user_id = NEW.user_id AND scan_id = NEW.id;

    IF staged IS NULL THEN
        RETURN NEW;
    END IF;

    NEW.gps_elevation := COALESCE((staged ->> 'gps_elevation')::DOUBLE PRECISION, NEW.gps_elevation);
    NEW.weather_condition := COALESCE(NULLIF(BTRIM(staged ->> 'weather_condition'), ''), NEW.weather_condition);
    NEW.weather_temperature_f := COALESCE((staged ->> 'weather_temperature_f')::DOUBLE PRECISION, NEW.weather_temperature_f);
    NEW.semantic_location := COALESCE(NULLIF(BTRIM(staged ->> 'semantic_location'), ''), NEW.semantic_location);

    DELETE FROM public.scan_deferred_context_updates
     WHERE user_id = NEW.user_id AND scan_id = NEW.id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS merge_staged_scan_context_before_insert ON public.scans;
CREATE TRIGGER merge_staged_scan_context_before_insert
BEFORE INSERT ON public.scans
FOR EACH ROW EXECUTE FUNCTION public.merge_staged_scan_context();

CREATE OR REPLACE FUNCTION public.apply_or_stage_scan_context(
    p_scan_id UUID,
    p_user_id UUID,
    p_context JSONB
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    applied BOOLEAN := FALSE;
BEGIN
    IF JSONB_TYPEOF(COALESCE(p_context, '{}'::JSONB)) <> 'object' THEN
        RAISE EXCEPTION 'context must be a JSON object';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.scans WHERE id = p_scan_id AND user_id = p_user_id
        UNION ALL
        SELECT 1 FROM public.scan_ingestion_jobs WHERE scan_id = p_scan_id::TEXT AND user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'scan ingestion not found';
    END IF;

    INSERT INTO public.scan_deferred_context_updates (user_id, scan_id, context, updated_at)
    VALUES (p_user_id, p_scan_id, COALESCE(p_context, '{}'::JSONB), NOW())
    ON CONFLICT (user_id, scan_id) DO UPDATE SET
        context = scan_deferred_context_updates.context || EXCLUDED.context,
        updated_at = NOW();

    UPDATE public.scans
       SET gps_elevation = COALESCE((p_context ->> 'gps_elevation')::DOUBLE PRECISION, gps_elevation),
           weather_condition = COALESCE(NULLIF(BTRIM(p_context ->> 'weather_condition'), ''), weather_condition),
           weather_temperature_f = COALESCE((p_context ->> 'weather_temperature_f')::DOUBLE PRECISION, weather_temperature_f),
           semantic_location = COALESCE(NULLIF(BTRIM(p_context ->> 'semantic_location'), ''), semantic_location)
     WHERE id = p_scan_id AND user_id = p_user_id;

    applied := FOUND;
    IF applied THEN
        DELETE FROM public.scan_deferred_context_updates
         WHERE user_id = p_user_id AND scan_id = p_scan_id;
    END IF;
    RETURN applied;
END;
$$;

REVOKE ALL ON TABLE public.scan_deferred_context_updates FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.merge_staged_scan_context() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_or_stage_scan_context(UUID, UUID, JSONB)
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON TABLE public.scan_deferred_context_updates TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_or_stage_scan_context(UUID, UUID, JSONB)
    TO service_role;

COMMENT ON FUNCTION public.begin_scan_ingestion IS
  'Service-role-only atomic lookup, ingestion claim, sanitized intent record, and inference-start transition.';
COMMENT ON FUNCTION public.hydrate_identification_dictionary IS
  'Service-role-only one-round-trip primary species cache and candidate English-name hydration.';
COMMENT ON TABLE public.scan_deferred_context_updates IS
  'Short-lived late WeatherKit and reverse-geocoding context staged until its owner scan is inserted.';

NOTIFY pgrst, 'reload schema';
