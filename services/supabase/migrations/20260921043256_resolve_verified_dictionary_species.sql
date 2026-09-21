SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE INDEX idx_species_dictionary_resolution_gbif_key
    ON public.species_dictionary (gbif_taxon_key) WHERE gbif_taxon_key IS NOT NULL;

-- Reuse the bounded, pruned request counters with a separate non-AI bucket.
-- These counters neither reserve provider tokens nor consume scan allowances.
CREATE FUNCTION public.admit_species_dictionary_resolution(viewer_id UUID)
RETURNS VOID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    clock_now TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    minute_start TIMESTAMPTZ;
    day_start TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();
    IF viewer_id IS NULL THEN
        RAISE EXCEPTION 'invalid_species_resolution_viewer' USING ERRCODE = '22023';
    END IF;
    minute_start := pg_catalog.TO_TIMESTAMP(pg_catalog.FLOOR(EXTRACT(EPOCH FROM clock_now) / 60) * 60);
    day_start := pg_catalog.TO_TIMESTAMP(pg_catalog.FLOOR(EXTRACT(EPOCH FROM clock_now) / 86400) * 86400);
    PERFORM internal.consume_ai_quota_counter('user_rate', viewer_id::TEXT,
        'species_dictionary_resolution', minute_start, 60, 6, 'species_resolution_rate_limited');
    PERFORM internal.consume_ai_quota_counter('user_daily', viewer_id::TEXT,
        'species_dictionary_resolution', day_start, 86400, 60, 'species_resolution_rate_limited');
    PERFORM internal.consume_ai_quota_counter('user_rate', 'system:species_dictionary_resolution',
        'species_dictionary_resolution_global', minute_start, 60, 120, 'species_resolution_rate_limited');
END;
$$;

-- Only a trusted Edge caller supplies the GBIF proof. No client-authored
-- taxonomy or display text is accepted by the authenticated HTTP endpoint.
CREATE FUNCTION public.resolve_verified_dictionary_species(taxon JSONB)
RETURNS UUID LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    canonical_name TEXT := pg_catalog.BTRIM(taxon ->> 'scientific_name');
    taxon_key INTEGER;
    resolved public.species_dictionary%ROWTYPE;
    previous_setting TEXT;
    matching_ids UUID[];
BEGIN
    PERFORM internal.require_service_role();
    IF pg_catalog.JSONB_TYPEOF(taxon) IS DISTINCT FROM 'object'
       OR taxon ->> 'rank' IS DISTINCT FROM 'SPECIES'
       OR taxon ->> 'status' IS DISTINCT FROM 'ACCEPTED'
       OR canonical_name IS NULL OR pg_catalog.LENGTH(canonical_name) NOT BETWEEN 1 AND 160
       OR pg_catalog.JSONB_TYPEOF(taxon -> 'gbif_taxon_key') IS DISTINCT FROM 'number'
       OR (taxon ->> 'gbif_taxon_key') !~ '^[1-9][0-9]{0,9}$'
       OR (taxon ->> 'gbif_taxon_key')::NUMERIC > 2147483647
       OR NOT public.species_dictionary_taxonomy_value_is_usable(taxon ->> 'kingdom') THEN
        RAISE EXCEPTION 'invalid_verified_species' USING ERRCODE = '22023';
    END IF;
    taxon_key := (taxon ->> 'gbif_taxon_key')::INTEGER;
    -- Concurrent resolver calls for accepted-name/synonym variants serialize on
    -- the GBIF identity. Do not impose uniqueness on historical curated data.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(187394, taxon_key);
    SELECT pg_catalog.ARRAY_AGG(candidate.id) INTO matching_ids FROM (
        SELECT id FROM public.species_dictionary
        WHERE gbif_taxon_key = taxon_key ORDER BY id LIMIT 2
    ) AS candidate;
    IF COALESCE(pg_catalog.ARRAY_LENGTH(matching_ids, 1), 0) > 1 THEN
        RAISE EXCEPTION 'species_resolution_ambiguous_identity' USING ERRCODE = '22023';
    END IF;
    IF pg_catalog.ARRAY_LENGTH(matching_ids, 1) = 1 THEN
        SELECT * INTO resolved FROM public.species_dictionary WHERE id = matching_ids[1];
        IF NOT resolved.is_public_biological OR EXISTS (
            SELECT 1 FROM public.species_dictionary
            WHERE scientific_name = canonical_name AND id <> resolved.id
        ) THEN
            RAISE EXCEPTION 'species_resolution_identity_conflict' USING ERRCODE = '22023';
        END IF;
        RETURN resolved.id;
    END IF;
    -- Match the worker's insert guard: reference/habitat/tag jobs are allowed,
    -- but opening one page cannot recursively generate new species/relations.
    previous_setting := pg_catalog.CURRENT_SETTING('merian.lookalike_candidate_materialization', TRUE);
    PERFORM pg_catalog.SET_CONFIG('merian.lookalike_candidate_materialization', 'on', TRUE);
    INSERT INTO public.species_dictionary (
        scientific_name, common_names, gbif_taxon_key,
        kingdom, phylum, class, "order", family, genus, native_region
    ) VALUES (
        canonical_name, '{}'::JSONB, taxon_key,
        taxon ->> 'kingdom', COALESCE(taxon ->> 'phylum', 'Unknown'),
        COALESCE(taxon ->> 'class', 'Unknown'), COALESCE(taxon ->> 'order', 'Unknown'),
        COALESCE(taxon ->> 'family', 'Unknown'), COALESCE(taxon ->> 'genus', 'Unknown'), 'Unknown'
    ) ON CONFLICT (scientific_name) DO NOTHING;
    -- Remember verified identity on legacy rows as well as new inserts. Only
    -- fill a missing key; concurrent conflicting proofs must never overwrite it.
    UPDATE public.species_dictionary SET gbif_taxon_key = taxon_key
    WHERE scientific_name = canonical_name AND is_public_biological
      AND gbif_taxon_key IS NULL;
    PERFORM pg_catalog.SET_CONFIG('merian.lookalike_candidate_materialization', COALESCE(previous_setting, ''), TRUE);
    -- Catch an independently committed legacy writer between lookup and insert.
    SELECT pg_catalog.ARRAY_AGG(candidate.id) INTO matching_ids FROM (
        SELECT id FROM public.species_dictionary
        WHERE gbif_taxon_key = taxon_key ORDER BY id LIMIT 2
    ) AS candidate;
    IF COALESCE(pg_catalog.ARRAY_LENGTH(matching_ids, 1), 0) > 1 THEN
        RAISE EXCEPTION 'species_resolution_ambiguous_identity' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO resolved FROM public.species_dictionary WHERE scientific_name = canonical_name;
    IF resolved.id IS NULL OR NOT resolved.is_public_biological
       OR resolved.gbif_taxon_key IS DISTINCT FROM taxon_key THEN
        RAISE EXCEPTION 'species_resolution_identity_conflict' USING ERRCODE = '22023';
    END IF;
    RETURN resolved.id;
END;
$$;

REVOKE ALL ON FUNCTION public.admit_species_dictionary_resolution(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.resolve_verified_dictionary_species(JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admit_species_dictionary_resolution(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.resolve_verified_dictionary_species(JSONB) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose) VALUES
    ('service_role', 'public.admit_species_dictionary_resolution(uuid)', 'Bound authenticated non-AI dictionary resolution requests.'),
    ('service_role', 'public.resolve_verified_dictionary_species(jsonb)', 'Materialize one exact GBIF-verified public species without replacing curated records.');

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
