-- Durable, content-free result configuration. No routing, consent, confidence
-- thresholds, public Identify payload, or historical result is changed.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.identification_provenance_is_valid(p_value JSONB)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $$
DECLARE
    key TEXT;
    generation JSONB;
    number_value NUMERIC;
BEGIN
    IF p_value IS NULL THEN RETURN TRUE; END IF;
    IF pg_catalog.JSONB_TYPEOF(p_value) <> 'object'
       OR pg_catalog.OCTET_LENGTH(p_value::TEXT) > 2048 THEN RETURN FALSE; END IF;
    IF NOT p_value ?& ARRAY[
        'version', 'provider', 'binding', 'model', 'variant', 'operation',
        'policy_version', 'prompt', 'schema', 'confidence', 'diagnostic_trigger',
        'prompt_diagnostic_trigger', 'safety', 'timeout_ms', 'generation'
    ] OR p_value - ARRAY[
        'version', 'provider', 'binding', 'model', 'variant', 'operation',
        'policy_version', 'prompt', 'schema', 'confidence', 'diagnostic_trigger',
        'prompt_diagnostic_trigger', 'safety', 'timeout_ms', 'generation'
    ] <> '{}'::JSONB OR p_value -> 'version' <> '1'::JSONB THEN RETURN FALSE; END IF;

    FOREACH key IN ARRAY ARRAY[
        'provider', 'binding', 'model', 'variant', 'operation', 'prompt', 'schema', 'confidence'
    ] LOOP
        IF pg_catalog.JSONB_TYPEOF(p_value -> key) <> 'string'
           OR p_value ->> key !~ '^[a-z][a-z0-9_.-]{0,79}$' THEN RETURN FALSE; END IF;
    END LOOP;
    IF p_value ->> 'variant' NOT IN ('multimodal', 'description_compat', 'vision_compat', 'audio_compat')
       OR p_value ->> 'operation' NOT IN ('scan_identification', 'scan_audio_identification')
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'policy_version') <> 'number'
       OR p_value ->> 'policy_version' !~ '^[1-9][0-9]{0,8}$'
       OR pg_catalog.JSONB_TYPEOF(p_value -> 'timeout_ms') <> 'number'
       OR p_value ->> 'timeout_ms' !~ '^[1-9][0-9]{0,5}$' THEN RETURN FALSE; END IF;
    FOREACH key IN ARRAY ARRAY['diagnostic_trigger', 'prompt_diagnostic_trigger'] LOOP
        IF p_value -> key <> 'null'::JSONB THEN
            IF pg_catalog.JSONB_TYPEOF(p_value -> key) <> 'number' THEN RETURN FALSE; END IF;
            number_value := (p_value ->> key)::NUMERIC;
            IF number_value < 0 OR number_value > 1 THEN RETURN FALSE; END IF;
        END IF;
    END LOOP;
    IF p_value -> 'safety' <> 'null'::JSONB AND (
        pg_catalog.JSONB_TYPEOF(p_value -> 'safety') <> 'string'
        OR p_value ->> 'safety' !~ '^[a-z][a-z0-9_.-]{0,79}$'
    ) THEN RETURN FALSE; END IF;

    generation := p_value -> 'generation';
    IF pg_catalog.JSONB_TYPEOF(generation) <> 'object' THEN RETURN FALSE; END IF;
    IF NOT generation ?& ARRAY['temperature', 'seed', 'top_k', 'max_output_tokens', 'thinking_budget']
       OR generation - ARRAY['temperature', 'seed', 'top_k', 'max_output_tokens', 'thinking_budget'] <> '{}'::JSONB
       OR pg_catalog.JSONB_TYPEOF(generation -> 'temperature') <> 'number' THEN RETURN FALSE; END IF;
    number_value := (generation ->> 'temperature')::NUMERIC;
    IF number_value < 0 OR number_value > 2 THEN RETURN FALSE; END IF;
    FOREACH key IN ARRAY ARRAY['seed', 'top_k', 'max_output_tokens', 'thinking_budget'] LOOP
        IF generation -> key = 'null'::JSONB AND key <> 'max_output_tokens' THEN CONTINUE; END IF;
        IF pg_catalog.JSONB_TYPEOF(generation -> key) <> 'number'
           OR generation ->> key !~ '^(0|[1-9][0-9]{0,8})$' THEN RETURN FALSE; END IF;
        number_value := (generation ->> key)::NUMERIC;
        IF key IN ('max_output_tokens', 'top_k') AND number_value < 1 THEN RETURN FALSE; END IF;
    END LOOP;
    RETURN TRUE;
END;
$$;

-- Pure CHECK predicate, also evaluated for rolling authenticated metadata
-- updates. It reads no tables and confers no write authority.
REVOKE ALL ON FUNCTION internal.identification_provenance_is_valid(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.identification_provenance_is_valid(JSONB)
    TO anon, authenticated, service_role;

ALTER TABLE public.scans ADD COLUMN identification_provenance JSONB;
ALTER TABLE public.scan_ingestion_jobs ADD COLUMN identification_provenance JSONB;
ALTER TABLE public.scans ADD CONSTRAINT scans_identification_provenance_check
    CHECK (internal.identification_provenance_is_valid(identification_provenance));
ALTER TABLE public.scan_ingestion_jobs ADD CONSTRAINT scan_ingestion_jobs_identification_provenance_check
    CHECK (internal.identification_provenance_is_valid(identification_provenance));

COMMENT ON COLUMN public.scans.identification_provenance IS
    'Immutable server-derived configuration of the successful identification. Fixed content-free fields share the scan visibility policy; NULL means not recorded. No inference from historical scores or tiers.';
COMMENT ON COLUMN public.scan_ingestion_jobs.identification_provenance IS
    'Server-written recovery copy made atomically with the first provenance-bearing owner scan insert. Never sourced from client recovery JSON; survives quota expiry and follows existing job ownership/retention.';

-- Existing scans ACL grants clients SELECT and five metadata UPDATE columns,
-- never INSERT or arbitrary UPDATE. Do not broaden it or make SELECT * fail.
REVOKE INSERT (identification_provenance), UPDATE (identification_provenance)
    ON public.scans FROM PUBLIC, anon, authenticated;
REVOKE INSERT (identification_provenance), UPDATE (identification_provenance)
    ON public.scan_ingestion_jobs FROM PUBLIC, anon, authenticated;

CREATE FUNCTION internal.guard_scan_identification_provenance()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.identification_provenance IS DISTINCT FROM OLD.identification_provenance THEN
            RAISE EXCEPTION 'identification_provenance_immutable' USING ERRCODE = '22023';
        END IF;
    ELSIF NEW.identification_provenance IS NULL THEN
        -- Both old Edge producers and the existing client-recovery RPC omit the
        -- new field. Only an exact owner/scan server backup may fill it. The
        -- recovery RPC still owns deletion, authority and completion fences.
        SELECT jobs.identification_provenance INTO NEW.identification_provenance
        FROM public.scan_ingestion_jobs AS jobs
        WHERE jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_scan_identification_provenance()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER guard_scan_identification_provenance
BEFORE INSERT OR UPDATE OF identification_provenance ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.guard_scan_identification_provenance();

CREATE FUNCTION internal.guard_job_identification_provenance()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.identification_provenance IS NOT DISTINCT FROM OLD.identification_provenance THEN
        RETURN NEW;
    END IF;
    IF OLD.identification_provenance IS NOT NULL OR NEW.identification_provenance IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM public.scans AS scans
           WHERE scans.id::TEXT = NEW.scan_id AND scans.user_id = NEW.user_id
             AND scans.identification_provenance = NEW.identification_provenance
       ) THEN
        RAISE EXCEPTION 'identification_provenance_immutable' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_job_identification_provenance()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER guard_job_identification_provenance
BEFORE UPDATE OF identification_provenance ON public.scan_ingestion_jobs
FOR EACH ROW EXECUTE FUNCTION internal.guard_job_identification_provenance();

CREATE FUNCTION internal.copy_scan_identification_provenance()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.identification_provenance IS NULL THEN RETURN NULL; END IF;
    UPDATE public.scan_ingestion_jobs AS jobs
    SET identification_provenance = NEW.identification_provenance
    WHERE jobs.scan_id = NEW.id::TEXT AND jobs.user_id = NEW.user_id
      AND (jobs.identification_provenance IS NULL OR jobs.identification_provenance = NEW.identification_provenance);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'identification_provenance_job_mismatch' USING ERRCODE = '22023';
    END IF;
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.copy_scan_identification_provenance()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER copy_scan_identification_provenance
AFTER INSERT ON public.scans
FOR EACH ROW EXECUTE FUNCTION internal.copy_scan_identification_provenance();

RESET lock_timeout;
RESET statement_timeout;
