-- Dormant result foundation. No producer, provider binding, assignment, model,
-- confidence policy or app capability is activated by this migration.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.primary_identification_is_valid(p_value JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE SET search_path = ''
AS $$
DECLARE
    key TEXT;
    name TEXT;
    utf16_length INTEGER;
    trim_characters CONSTANT TEXT := U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
BEGIN
    IF p_value IS NULL THEN RETURN TRUE; END IF;
    IF pg_catalog.JSONB_TYPEOF(p_value) <> 'object'
       OR pg_catalog.OCTET_LENGTH(p_value::TEXT) > 4096
       OR NOT p_value ?& ARRAY['version', 'resolution', 'scientific_name', 'common_name']
       OR p_value - ARRAY['version', 'resolution', 'scientific_name', 'common_name'] <> '{}'::JSONB
       OR p_value -> 'version' <> '1'::JSONB
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'resolution') <> 'string'
       OR p_value ->> 'resolution' NOT IN ('species', 'genus', 'family', 'unresolved_biological', 'non_biological') THEN
        RETURN FALSE;
    END IF;
    FOREACH key IN ARRAY ARRAY['scientific_name', 'common_name'] LOOP
        IF p_value -> key = 'null'::JSONB THEN CONTINUE; END IF;
        IF pg_catalog.JSONB_TYPEOF(p_value -> key) <> 'string' THEN RETURN FALSE; END IF;
        name := p_value ->> key;
        -- Match the wire's JavaScript string bounds, including supplementary
        -- Unicode characters, and its trim/control-character normalization.
        SELECT pg_catalog.SUM(CASE WHEN pg_catalog.ASCII(character) > 65535 THEN 2 ELSE 1 END)
        INTO utf16_length FROM pg_catalog.REGEXP_SPLIT_TO_TABLE(name, '') AS character;
        IF name = '' OR utf16_length > 255
           OR name <> pg_catalog.BTRIM(name, trim_characters)
           OR name ~ U&'[\0001-\001F\007F]' THEN RETURN FALSE; END IF;
    END LOOP;
    IF (p_value ->> 'resolution' IN ('species', 'genus', 'family') AND p_value -> 'scientific_name' = 'null'::JSONB)
       OR (p_value ->> 'resolution' = 'unresolved_biological' AND p_value -> 'scientific_name' <> 'null'::JSONB) THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.primary_identification_is_valid(JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.primary_identification_is_valid(JSONB) TO anon, authenticated, service_role;

ALTER TABLE public.scans ADD COLUMN primary_identification JSONB;
ALTER TABLE public.scan_ingestion_jobs ADD COLUMN primary_identification JSONB;
ALTER TABLE public.scans ADD CONSTRAINT scans_primary_identification_check CHECK (
    internal.primary_identification_is_valid(primary_identification)
    AND ((primary_identification IS NOT NULL) = COALESCE(identification_provenance ->> 'schema' = 'merian_identify_primary_v1', FALSE))
);
ALTER TABLE public.scan_ingestion_jobs ADD CONSTRAINT scan_ingestion_jobs_primary_identification_check CHECK (
    internal.primary_identification_is_valid(primary_identification)
    AND ((primary_identification IS NOT NULL) = COALESCE(identification_provenance ->> 'schema' = 'merian_identify_primary_v1', FALSE))
);

CREATE FUNCTION internal.primary_identification_scan_is_valid(
    p_primary JSONB, p_biological BOOLEAN, p_species_id UUID, p_candidates JSONB, p_pet JSONB
) RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE PARALLEL SAFE SET search_path = ''
AS $$
DECLARE candidate JSONB;
BEGIN
    IF p_primary IS NULL THEN RETURN TRUE; END IF;
    IF NOT internal.primary_identification_is_valid(p_primary)
       OR p_biological IS DISTINCT FROM (p_primary ->> 'resolution' <> 'non_biological') THEN RETURN FALSE; END IF;
    IF p_primary ->> 'resolution' <> 'species' THEN
        RETURN p_species_id IS NULL AND (p_candidates IS NULL OR p_candidates = 'null'::JSONB)
            AND (p_pet IS NULL OR p_pet = 'null'::JSONB);
    END IF;
    IF p_candidates IS NULL OR p_candidates = 'null'::JSONB THEN RETURN TRUE; END IF;
    IF pg_catalog.JSONB_TYPEOF(p_candidates) <> 'array' THEN RETURN FALSE; END IF;
    IF pg_catalog.JSONB_ARRAY_LENGTH(p_candidates) > 2 THEN RETURN FALSE; END IF;
    FOR candidate IN SELECT * FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_candidates) LOOP
        IF pg_catalog.JSONB_TYPEOF(candidate) <> 'object'
           OR candidate -> 'taxon_rank' IS DISTINCT FROM '"species"'::JSONB THEN RETURN FALSE; END IF;
    END LOOP;
    RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION internal.primary_identification_scan_is_valid(JSONB, BOOLEAN, UUID, JSONB, JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.primary_identification_scan_is_valid(JSONB, BOOLEAN, UUID, JSONB, JSONB) TO anon, authenticated, service_role;
ALTER TABLE public.scans ADD CONSTRAINT scans_primary_identification_subject_check CHECK (
    internal.primary_identification_scan_is_valid(primary_identification, is_biological_subject, species_id, candidates, pet_identification)
);

COMMENT ON COLUMN public.scans.primary_identification IS
    'Immutable versioned primary AI answer and labels, required only by reserved schema merian_identify_primary_v1. Observation data under existing scan visibility and retention. NULL is legacy; never infer rank from names, confidence or tier.';
COMMENT ON COLUMN public.scan_ingestion_jobs.primary_identification IS
    'Server-owned recovery copy, written atomically with provenance for the exact owner scan. Client recovery JSON cannot assert or replace this snapshot.';
REVOKE INSERT (primary_identification), UPDATE (primary_identification) ON public.scans FROM PUBLIC, anon, authenticated;
REVOKE INSERT (primary_identification), UPDATE (primary_identification) ON public.scan_ingestion_jobs FROM PUBLIC, anon, authenticated;

CREATE FUNCTION internal.guard_scan_primary_identification()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.primary_identification IS DISTINCT FROM OLD.primary_identification THEN
            RAISE EXCEPTION 'primary_identification_immutable' USING ERRCODE = '22023';
        END IF;
    ELSIF NEW.primary_identification IS NULL THEN
        SELECT jobs.primary_identification INTO NEW.primary_identification
        FROM public.scan_ingestion_jobs AS jobs
        WHERE jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_scan_primary_identification() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER guard_scan_primary_identification
BEFORE INSERT OR UPDATE OF primary_identification ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.guard_scan_primary_identification();

CREATE FUNCTION internal.guard_job_primary_identification()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NEW.primary_identification IS NOT DISTINCT FROM OLD.primary_identification THEN RETURN NEW; END IF;
    IF OLD.primary_identification IS NOT NULL OR NEW.primary_identification IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.scans AS scans WHERE scans.id::TEXT = NEW.scan_id AND scans.user_id = NEW.user_id
        AND scans.primary_identification = NEW.primary_identification
        AND scans.identification_provenance = NEW.identification_provenance
    ) THEN
        RAISE EXCEPTION 'primary_identification_immutable' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_job_primary_identification() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER guard_job_primary_identification
BEFORE UPDATE OF primary_identification ON public.scan_ingestion_jobs
FOR EACH ROW EXECUTE FUNCTION internal.guard_job_primary_identification();

-- One existing AFTER INSERT trigger writes both recovery fields in one update.
-- Separate updates would transiently violate their required schema pairing.
CREATE OR REPLACE FUNCTION internal.copy_scan_identification_provenance()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
    IF NEW.identification_provenance IS NULL THEN RETURN NULL; END IF;
    UPDATE public.scan_ingestion_jobs AS jobs
    SET identification_provenance = NEW.identification_provenance,
        primary_identification = NEW.primary_identification
    WHERE jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id
      AND (jobs.identification_provenance IS NULL OR jobs.identification_provenance = NEW.identification_provenance)
      AND (jobs.primary_identification IS NULL OR jobs.primary_identification = NEW.primary_identification);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'identification_provenance_job_mismatch' USING ERRCODE = '22023';
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.copy_scan_identification_provenance() FROM PUBLIC, anon, authenticated, service_role;

-- Recognize a future capable reader without raising today's binding minimum
-- or changing original-client evidence. PostgreSQL truncates the old unnamed
-- column constraint; resolve exactly that predicate instead of guessing a name.
DO $migration$
DECLARE constraint_name NAME;
BEGIN
    SELECT conname INTO STRICT constraint_name FROM pg_catalog.pg_constraint
    WHERE conrelid = 'internal.identification_provider_attempts'::REGCLASS AND contype = 'c'
      AND pg_catalog.PG_GET_EXPR(conbin, conrelid) = '(accepted_identification_protocol = 4)';
    EXECUTE pg_catalog.FORMAT('ALTER TABLE internal.identification_provider_attempts DROP CONSTRAINT %I', constraint_name);
END;
$migration$;
ALTER TABLE internal.identification_provider_attempts
    ADD CONSTRAINT identification_attempt_accepted_protocol_check CHECK (accepted_identification_protocol IN (4, 5)),
    DROP CONSTRAINT identification_provider_attempts_recipient_tuple,
    ADD CONSTRAINT identification_provider_attempts_recipient_tuple CHECK (
        (provider = 'gemini' AND binding = 'gemini_baseline_v1'
            AND processor_permission = 'google_gemini' AND provider_model IS NULL
            AND ((minimum_identification_protocol IS NULL AND accepted_identification_protocol IS NULL)
                OR (minimum_identification_protocol IS NOT NULL AND minimum_identification_protocol = 0)))
        OR (provider = 'openai' AND binding = 'openai_photo_v1'
            AND processor_permission = 'openai' AND provider_model IS NOT NULL
            AND provider_model = 'gpt-6-sol' AND operation = 'scan_identification'
            AND input_profile IS NOT NULL AND input_profile = 'multimodal_photo_v1'
            AND minimum_identification_protocol IS NOT NULL AND minimum_identification_protocol = 4
            AND accepted_identification_protocol IS NOT NULL AND accepted_identification_protocol IN (4, 5))
    );
COMMENT ON COLUMN internal.identification_provider_attempts.accepted_identification_protocol IS
    'Immutable original-client capability: exactly 4 or 5 is recognized; historical absence stays NULL. Replay uses this saved value, never a worker claim. Current binding minimum stays 4.';

CREATE OR REPLACE FUNCTION internal.require_identification_capability(
    p_user_id UUID, p_operation TEXT, p_original_analysis_id UUID,
    p_input_profile TEXT, p_identification_protocol INTEGER,
    p_internal_replay BOOLEAN, p_minimum_identification_protocol INTEGER
) RETURNS INTEGER LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = ''
AS $function$
DECLARE accepted INTEGER;
BEGIN
    IF p_internal_replay IS NULL OR p_minimum_identification_protocol IS NULL
       OR p_minimum_identification_protocol NOT IN (0, 4) THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;
    IF p_internal_replay THEN
        SELECT saved.accepted_identification_protocol INTO accepted
        FROM internal.ai_quota_reservations AS source
        JOIN internal.identification_provider_attempts AS saved
          ON saved.reservation_id = source.id AND saved.attempt_count = source.attempt_count
        WHERE source.user_id = p_user_id AND source.operation = p_operation
          AND source.request_id = p_original_analysis_id
          AND source.original_analysis_id = p_original_analysis_id
          AND saved.operation = p_operation
          AND saved.input_profile IS NOT DISTINCT FROM p_input_profile;
    ELSIF p_identification_protocol IN (4, 5) THEN
        accepted := p_identification_protocol;
    END IF;
    IF p_minimum_identification_protocol = 4 AND (accepted IS NULL OR accepted NOT IN (4, 5)) THEN
        RAISE EXCEPTION 'client_update_required' USING ERRCODE = 'P0001';
    END IF;
    RETURN accepted;
END;
$function$;
REVOKE ALL ON FUNCTION internal.require_identification_capability(UUID, TEXT, UUID, TEXT, INTEGER, BOOLEAN, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.require_identification_result_reader(p_provenance JSONB, p_primary JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path = ''
AS $$
DECLARE
    headers_text TEXT;
    headers JSONB;
    requires_primary BOOLEAN := p_primary IS NOT NULL OR COALESCE(p_provenance ->> 'schema' = 'merian_identify_primary_v1', FALSE);
BEGIN
    IF NOT requires_primary AND (p_provenance IS NULL OR p_provenance -> 'version' = '1'::JSONB) THEN RETURN TRUE; END IF;
    headers_text := pg_catalog.CURRENT_SETTING('request.headers', TRUE);
    IF p_provenance -> 'version' IN ('1'::JSONB, '2'::JSONB)
       AND pg_catalog.OCTET_LENGTH(headers_text) <= 32768 THEN
        BEGIN headers := NULLIF(headers_text, '')::JSONB;
        EXCEPTION WHEN invalid_text_representation THEN headers := NULL;
        END;
        IF pg_catalog.JSONB_TYPEOF(headers) = 'object' AND (
            headers -> 'x-merian-identification-protocol' = '"5"'::JSONB
            OR (NOT requires_primary AND headers -> 'x-merian-identification-protocol' = '"4"'::JSONB)
        ) THEN RETURN TRUE; END IF;
    END IF;
    RAISE SQLSTATE 'PT426' USING MESSAGE = 'client_update_required', HINT = 'Update Naturebook to read this identification.';
END;
$$;
REVOKE ALL ON FUNCTION internal.require_identification_result_reader(JSONB, JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.require_identification_result_reader(JSONB, JSONB) TO anon, authenticated;

CREATE OR REPLACE FUNCTION internal.require_identification_result_reader(p_provenance JSONB)
RETURNS BOOLEAN LANGUAGE SQL VOLATILE SECURITY INVOKER SET search_path = ''
AS $$ SELECT internal.require_identification_result_reader(p_provenance, NULL); $$;
REVOKE ALL ON FUNCTION internal.require_identification_result_reader(JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.require_identification_result_reader(JSONB) TO anon, authenticated;

DO $migration$
BEGIN
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.pg_policy
        WHERE polrelid = 'public.scans'::REGCLASS AND polcmd IN ('r', '*')) <> 2 THEN
        RAISE EXCEPTION 'unexpected_scan_reader_policies';
    END IF;
END;
$migration$;
ALTER POLICY "Users can fully read their own private scans" ON public.scans USING (
    CASE WHEN (SELECT auth.uid()) = user_id THEN
        internal.require_identification_result_reader(identification_provenance, primary_identification)
    ELSE FALSE END
);
ALTER POLICY "Anyone can read open and live scans" ON public.scans USING (
    CASE WHEN geoprivacy = 'open' AND is_live_capture = TRUE AND is_tombstoned = FALSE THEN
        internal.require_identification_result_reader(identification_provenance, primary_identification)
    ELSE FALSE END
);
COMMENT ON FUNCTION internal.require_identification_result_reader(JSONB, JSONB) IS
    'Compatibility only after existing visibility: legacy/V1 unchanged; V2 needs exact protocol 4 or 5; reserved primary results need exact 5. Does not authorize a provider, widen visibility or calibrate confidence.';
COMMENT ON FUNCTION internal.require_identification_result_reader(JSONB) IS
    'Compatibility wrapper for legacy callers; the reserved schema marker still requires protocol 5 if its primary snapshot is absent.';

RESET lock_timeout;
RESET statement_timeout;
