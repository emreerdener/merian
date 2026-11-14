-- Additive Gemini generation-3 compatibility. No policy, routing, hold or saved evidence updates.

SET lock_timeout = '5s';

SET statement_timeout = '5min';

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_admitted_proof_schema()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_admitted_proof_schema()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    IF (length(definition)-length(replace(definition,'"gemini-2.5-flash","gemini-2.5-pro"','')))/length('"gemini-2.5-flash","gemini-2.5-pro"')<>2 THEN
      RAISE EXCEPTION 'Gemini admitted model enum drift'; END IF;
    definition:=replace(definition,'"gemini-2.5-flash","gemini-2.5-pro"','"gemini-2.5-flash","gemini-2.5-pro","gemini-3.8-flash"');
    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.identification_provenance_is_valid(jsonb)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$    IF p_value IS NULL THEN RETURN TRUE; END IF;$before$, ''))) / pg_catalog.length($before$    IF p_value IS NULL THEN RETURN TRUE; END IF;$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.identification_provenance_is_valid(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$    IF p_value IS NULL THEN RETURN TRUE; END IF;$before$, $after$    IF p_value IS NULL THEN RETURN TRUE; END IF;
    -- V3 configuration may precede a response. Completed-result writers separately
    -- require returned_model. The recursive call validates unchanged common V1 fields.
    IF p_value -> 'version' = '3'::JSONB THEN
        IF NOT (p_value ? 'returned_model')
            OR p_value ->> 'provider' IS DISTINCT FROM 'gemini'
            OR p_value ->> 'binding' IS DISTINCT FROM 'gemini_generation3_v1'
            OR p_value ->> 'model' IS DISTINCT FROM 'gemini-3.8-flash'
            OR p_value -> 'returned_model' NOT IN ('null'::JSONB, '"gemini-3.8-flash"'::JSONB)
            OR p_value -> 'generation' IS DISTINCT FROM '{"max_output_tokens":8192,"thinking_level":"medium"}'::JSONB
            OR p_value -> 'timeout_ms' IS DISTINCT FROM '90000'::JSONB THEN RETURN FALSE; END IF;
        RETURN internal.identification_provenance_is_valid((p_value - 'returned_model') ||
            pg_catalog.jsonb_build_object('version',1,'generation',
              '{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":null}'::JSONB));
    END IF;
$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.require_identification_capability(uuid,text,uuid,text,integer,boolean,integer)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$NOT IN (0, 4)$before$, ''))) / pg_catalog.length($before$NOT IN (0, 4)$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.require_identification_capability(uuid,text,uuid,text,integer,boolean,integer)';
    END IF;
    definition := pg_catalog.replace(definition, $before$NOT IN (0, 4)$before$, $after$NOT IN (0, 4, 7)$after$);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$IN (4, 5, 6)$before$, ''))) / pg_catalog.length($before$IN (4, 5, 6)$before$) <> 2 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.require_identification_capability(uuid,text,uuid,text,integer,boolean,integer)';
    END IF;
    definition := pg_catalog.replace(definition, $before$IN (4, 5, 6)$before$, $after$IN (4, 5, 6, 7)$after$);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$    RETURN accepted;$before$, ''))) / pg_catalog.length($before$    RETURN accepted;$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.require_identification_capability(uuid,text,uuid,text,integer,boolean,integer)';
    END IF;
    definition := pg_catalog.replace(definition, $before$    RETURN accepted;$before$, $after$    IF p_minimum_identification_protocol = 7 AND accepted IS DISTINCT FROM 7 THEN
        RAISE EXCEPTION 'client_update_required' USING ERRCODE = 'P0001';
    END IF;
    RETURN accepted;$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.require_identification_result_reader(jsonb,jsonb)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$p_provenance -> 'version' IN ('1'::JSONB, '2'::JSONB)$before$, ''))) / pg_catalog.length($before$p_provenance -> 'version' IN ('1'::JSONB, '2'::JSONB)$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.require_identification_result_reader(jsonb,jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$p_provenance -> 'version' IN ('1'::JSONB, '2'::JSONB)$before$, $after$p_provenance -> 'version' IN ('1'::JSONB, '2'::JSONB, '3'::JSONB)$after$);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$IF pg_catalog.JSONB_TYPEOF(headers) = 'object' AND ($before$, ''))) / pg_catalog.length($before$IF pg_catalog.JSONB_TYPEOF(headers) = 'object' AND ($before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.require_identification_result_reader(jsonb,jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$IF pg_catalog.JSONB_TYPEOF(headers) = 'object' AND ($before$, $after$IF pg_catalog.JSONB_TYPEOF(headers) = 'object' AND
          (p_provenance -> 'version' <> '3'::JSONB OR headers -> 'x-merian-identification-protocol' = '"7"'::JSONB) AND ($after$);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$IN ('"5"'::JSONB,'"6"'::JSONB)$before$, ''))) / pg_catalog.length($before$IN ('"5"'::JSONB,'"6"'::JSONB)$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.require_identification_result_reader(jsonb,jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$IN ('"5"'::JSONB,'"6"'::JSONB)$before$, $after$IN ('"5"'::JSONB,'"6"'::JSONB,'"7"'::JSONB)$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.admit_observation_analysis(uuid,jsonb,text)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, ''))) / pg_catalog.length($before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.admit_observation_analysis(uuid,jsonb,text)';
    END IF;
    definition := pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, $after$p_input->'identification_protocol' NOT IN ('6'::JSONB,'7'::JSONB)$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.admit_protected_observation_analysis(uuid,jsonb,text)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, ''))) / pg_catalog.length($before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.admit_protected_observation_analysis(uuid,jsonb,text)';
    END IF;
    definition := pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, $after$p_input->'identification_protocol' NOT IN ('6'::JSONB,'7'::JSONB)$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_owned_observation_reanalysis_preflight(jsonb)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$p_request->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, ''))) / pg_catalog.length($before$p_request->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: public.get_owned_observation_reanalysis_preflight(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$p_request->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, $after$p_request->'identification_protocol' NOT IN ('6'::JSONB,'7'::JSONB)$after$);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$FALSE,analysis,3,6)$before$, ''))) / pg_catalog.length($before$FALSE,analysis,3,6)$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: public.get_owned_observation_reanalysis_preflight(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$FALSE,analysis,3,6)$before$, $after$FALSE,analysis,3,(p_request->>'identification_protocol')::INTEGER)$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.retained_identification_is_valid(jsonb)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$value->'provenance_version' NOT IN ('null'::JSONB,'1'::JSONB,'2'::JSONB)$before$, ''))) / pg_catalog.length($before$value->'provenance_version' NOT IN ('null'::JSONB,'1'::JSONB,'2'::JSONB)$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.retained_identification_is_valid(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$value->'provenance_version' NOT IN ('null'::JSONB,'1'::JSONB,'2'::JSONB)$before$, $after$value->'provenance_version' NOT IN ('null'::JSONB,'1'::JSONB,'2'::JSONB,'3'::JSONB)$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.observation_video_source_fingerprint_bytes(jsonb)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, ''))) / pg_catalog.length($before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.observation_video_source_fingerprint_bytes(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, $after$p_input->'identification_protocol' NOT IN ('6'::JSONB,'7'::JSONB)$after$);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$'3','6','9','google_gemini'$before$, ''))) / pg_catalog.length($before$'3','6','9','google_gemini'$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.observation_video_source_fingerprint_bytes(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$'3','6','9','google_gemini'$before$, $after$'3',p_input->>'identification_protocol','9','google_gemini'$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_assignment_schema_v2()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_assignment_schema_v2()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.admit_audio_observation_analysis(uuid,jsonb,text)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, ''))) / pg_catalog.length($before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.admit_audio_observation_analysis(uuid,jsonb,text)';
    END IF;
    definition := pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, $after$p_input->'identification_protocol' NOT IN ('6'::JSONB,'7'::JSONB)$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.observation_source_fingerprint_bytes(jsonb)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, ''))) / pg_catalog.length($before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.observation_source_fingerprint_bytes(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$p_input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, $after$p_input->'identification_protocol' NOT IN ('6'::JSONB,'7'::JSONB)$after$);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$'3','6',CASE WHEN schema_version=2$before$, ''))) / pg_catalog.length($before$'3','6',CASE WHEN schema_version=2$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.observation_source_fingerprint_bytes(jsonb)';
    END IF;
    definition := pg_catalog.replace(definition, $before$'3','6',CASE WHEN schema_version=2$before$, $after$'3',p_input->>'identification_protocol',CASE WHEN schema_version=2$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_owned_observation_analysis_source(uuid,jsonb,integer)'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, ''))) / pg_catalog.length($before$input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: public.get_owned_observation_analysis_source(uuid,jsonb,integer)';
    END IF;
    definition := pg_catalog.replace(definition, $before$input->'identification_protocol' IS DISTINCT FROM '6'::JSONB$before$, $after$input->'identification_protocol' NOT IN ('6'::JSONB,'7'::JSONB)$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_input_schema()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_input_schema()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_preparation_candidate_schema_v2()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_preparation_candidate_schema_v2()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_media_source_candidate_schema_v2()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_media_source_candidate_schema_v2()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_media_assignment_schema()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_media_assignment_schema()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_media_response_schema()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_media_response_schema()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_qualified_schema()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 2 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_qualified_schema()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_cpm_photo_candidate_schema_v1()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_cpm_photo_candidate_schema_v1()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('internal.initial_cpm_photo_assignment_schema_v1()'::regprocedure);

    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, ''))) / pg_catalog.length($before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$) <> 1 THEN
        RAISE EXCEPTION 'Gemini compatibility source drift: internal.initial_cpm_photo_assignment_schema_v1()';
    END IF;
    definition := pg_catalog.replace(definition, $before$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":6}$before$, $after$"accepted_identification_protocol":{"type":"integer","minimum":6,"maximum":7}$after$);

    EXECUTE definition;
END;
$migration$;

ALTER TABLE internal.identification_provider_bindings DROP CONSTRAINT identification_provider_bind_minimum_identification_proto_check, ADD CONSTRAINT identification_provider_bind_minimum_identification_proto_check CHECK ((minimum_identification_protocol = ANY (ARRAY[0, 4, 7])));

ALTER TABLE internal.identification_provider_bindings DROP CONSTRAINT identification_provider_bindings_model_check, ADD CONSTRAINT identification_provider_bindings_model_check CHECK ((model = ANY (ARRAY['gemini-2.5-flash'::text, 'gemini-2.5-pro'::text, 'gemini-3.8-flash'::text])));

ALTER TABLE internal.identification_provider_bindings DROP CONSTRAINT identification_provider_bindings_recipient_tuple, ADD CONSTRAINT identification_provider_bindings_recipient_tuple CHECK ((((provider = 'gemini'::text) AND (binding = 'gemini_baseline_v1'::text) AND (processor_permission = 'google_gemini'::text) AND (provider_model IS NULL) AND (minimum_identification_protocol = 0)) OR ((provider = 'openai'::text) AND (binding = 'openai_photo_v1'::text) AND (processor_permission = 'openai'::text) AND (provider_model IS NOT NULL) AND (provider_model = 'gpt-6-sol'::text) AND (operation = 'scan_identification'::text) AND (input_profile = 'multimodal_photo_v1'::text) AND (minimum_identification_protocol = 4))) OR (provider = 'gemini' AND binding = 'gemini_generation3_v1' AND processor_permission = 'google_gemini' AND provider_model IS NOT NULL AND provider_model = 'gemini-3.8-flash' AND model = 'gemini-3.8-flash' AND minimum_identification_protocol IS NOT NULL AND minimum_identification_protocol = 7));

ALTER TABLE internal.identification_provider_attempts DROP CONSTRAINT identification_attempt_accepted_protocol_check, ADD CONSTRAINT identification_attempt_accepted_protocol_check CHECK ((accepted_identification_protocol = ANY (ARRAY[4, 5, 6, 7])));

ALTER TABLE internal.identification_provider_attempts DROP CONSTRAINT identification_provider_atte_minimum_identification_proto_check, ADD CONSTRAINT identification_provider_atte_minimum_identification_proto_check CHECK ((minimum_identification_protocol = ANY (ARRAY[0, 4, 7])));

ALTER TABLE internal.identification_provider_attempts DROP CONSTRAINT identification_provider_attempts_model_check, ADD CONSTRAINT identification_provider_attempts_model_check CHECK ((model = ANY (ARRAY['gemini-2.5-flash'::text, 'gemini-2.5-pro'::text, 'gemini-3.8-flash'::text])));

ALTER TABLE internal.identification_provider_attempts DROP CONSTRAINT identification_provider_attempts_recipient_tuple, ADD CONSTRAINT identification_provider_attempts_recipient_tuple CHECK ((((provider = 'gemini'::text) AND (binding = 'gemini_baseline_v1'::text) AND (processor_permission = 'google_gemini'::text) AND (provider_model IS NULL) AND (((minimum_identification_protocol IS NULL) AND (accepted_identification_protocol IS NULL)) OR ((minimum_identification_protocol IS NOT NULL) AND (minimum_identification_protocol = 0)))) OR ((provider = 'openai'::text) AND (binding = 'openai_photo_v1'::text) AND (processor_permission = 'openai'::text) AND (provider_model IS NOT NULL) AND (provider_model = 'gpt-6-sol'::text) AND (operation = 'scan_identification'::text) AND (input_profile IS NOT NULL) AND (input_profile = 'multimodal_photo_v1'::text) AND (minimum_identification_protocol IS NOT NULL) AND (minimum_identification_protocol = 4) AND (accepted_identification_protocol IS NOT NULL) AND (accepted_identification_protocol = ANY (ARRAY[4, 5, 6, 7])))) OR (provider = 'gemini' AND binding = 'gemini_generation3_v1' AND processor_permission = 'google_gemini' AND provider_model IS NOT NULL AND provider_model = 'gemini-3.8-flash' AND model = 'gemini-3.8-flash' AND minimum_identification_protocol IS NOT NULL AND minimum_identification_protocol = 7 AND accepted_identification_protocol IS NOT NULL AND accepted_identification_protocol = 7));

ALTER TABLE internal.ai_quota_policies DROP CONSTRAINT ai_quota_policies_model_check, ADD CONSTRAINT ai_quota_policies_model_check CHECK ((allowed AND model IN ('gemini-2.5-flash','gemini-2.5-pro','gemini-3.8-flash','gemini-3.5-flash-lite')) OR (NOT allowed AND model IS NULL));

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_owned_observation_analysis_page(jsonb,integer)'::regprocedure);
    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition,$before$p_reader NOT IN (7,8,9,10,11)$before$,''))) / pg_catalog.length($before$p_reader NOT IN (7,8,9,10,11)$before$) <> 1 THEN RAISE EXCEPTION 'Gemini reader source drift'; END IF;
    definition := pg_catalog.replace(definition,$before$p_reader NOT IN (7,8,9,10,11)$before$,$after$p_reader NOT IN (7,8,9,10,11,13)$after$);
    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition,$before$(p_reader=11 AND result_row.evidence_manifest->'schema_version'='4'::JSONB)$before$,''))) / pg_catalog.length($before$(p_reader=11 AND result_row.evidence_manifest->'schema_version'='4'::JSONB)$before$) <> 1 THEN RAISE EXCEPTION 'Gemini reader source drift'; END IF;
    definition := pg_catalog.replace(definition,$before$(p_reader=11 AND result_row.evidence_manifest->'schema_version'='4'::JSONB)$before$,$after$(p_reader IN (11,13) AND result_row.evidence_manifest->'schema_version'='4'::JSONB)$after$);
    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition,$before$    FOR result_row IN SELECT * FROM internal.observation_analysis_results$before$,''))) / pg_catalog.length($before$    FOR result_row IN SELECT * FROM internal.observation_analysis_results$before$) <> 1 THEN RAISE EXCEPTION 'Gemini reader source drift'; END IF;
    definition := pg_catalog.replace(definition,$before$    FOR result_row IN SELECT * FROM internal.observation_analysis_results$before$,$after$    IF p_reader <> 13 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=observation AND result_snapshot->'identification_provenance'->'version'='3'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
    FOR result_row IN SELECT * FROM internal.observation_analysis_results$after$);
    EXECUTE definition;
END;
$migration$;

DO $migration$
DECLARE definition TEXT;
BEGIN
    definition := pg_catalog.pg_get_functiondef('public.get_owned_observation_analysis_state(jsonb,integer)'::regprocedure);
    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition,$before$p_reader NOT IN (9,10,11)$before$,''))) / pg_catalog.length($before$p_reader NOT IN (9,10,11)$before$) <> 1 THEN RAISE EXCEPTION 'Gemini reader source drift'; END IF;
    definition := pg_catalog.replace(definition,$before$p_reader NOT IN (9,10,11)$before$,$after$p_reader NOT IN (9,10,11,13)$after$);
    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition,$before$    SELECT * INTO evidence FROM internal.observation_analysis_results$before$,''))) / pg_catalog.length($before$    SELECT * INTO evidence FROM internal.observation_analysis_results$before$) <> 1 THEN RAISE EXCEPTION 'Gemini reader source drift'; END IF;
    definition := pg_catalog.replace(definition,$before$    SELECT * INTO evidence FROM internal.observation_analysis_results$before$,$after$    IF p_reader <> 13 AND EXISTS(SELECT 1 FROM internal.observation_analysis_results
        WHERE observation_id=observation AND result_snapshot->'identification_provenance'->'version'='3'::JSONB) THEN
        RAISE EXCEPTION 'analysis_history_reader_upgrade_required' USING ERRCODE='55000';
    END IF;
    SELECT * INTO evidence FROM internal.observation_analysis_results$after$);
    EXECUTE definition;
END;
$migration$;

NOTIFY pgrst, 'reload schema';
RESET lock_timeout;
RESET statement_timeout;
