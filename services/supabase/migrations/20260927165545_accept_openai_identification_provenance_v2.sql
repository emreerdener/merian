-- Add dual-read metadata support before any OpenAI assignment is enabled.
-- Existing CHECKs, immutable recovery triggers, privileges and rows stay intact.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION internal.identification_provenance_is_valid(p_value JSONB)
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
    ] <> '{}'::JSONB OR p_value -> 'version' NOT IN ('1'::JSONB, '2'::JSONB) THEN RETURN FALSE; END IF;

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
    IF p_value -> 'version' = '2'::JSONB THEN
        IF p_value ->> 'provider' <> 'openai'
           OR NOT generation ?& ARRAY['max_output_tokens', 'reasoning_effort', 'image_detail']
           OR generation - ARRAY['max_output_tokens', 'reasoning_effort', 'image_detail'] <> '{}'::JSONB
           OR pg_catalog.JSONB_TYPEOF(generation -> 'max_output_tokens') <> 'number'
           OR generation ->> 'max_output_tokens' !~ '^[1-9][0-9]{0,8}$' THEN RETURN FALSE; END IF;
        FOREACH key IN ARRAY ARRAY['reasoning_effort', 'image_detail'] LOOP
            IF pg_catalog.JSONB_TYPEOF(generation -> key) <> 'string'
               OR generation ->> key !~ '^[a-z][a-z0-9_.-]{0,79}$' THEN RETURN FALSE; END IF;
        END LOOP;
        RETURN TRUE;
    END IF;

    -- Version 1 is unchanged, including its exact Gemini generation shape.
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

RESET lock_timeout;
RESET statement_timeout;
