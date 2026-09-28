-- Dormant visual-provider admission. No assignment, quota policy, consent or
-- rollout row changes. Existing entitlement protocol remains 3.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

ALTER TABLE internal.identification_provider_bindings
    ADD COLUMN provider_model TEXT,
    ADD COLUMN minimum_identification_protocol INTEGER NOT NULL DEFAULT 0
        CHECK (minimum_identification_protocol IN (0, 4)),
    DROP CONSTRAINT identification_provider_bindings_provider_check,
    DROP CONSTRAINT identification_provider_bindings_binding_check,
    DROP CONSTRAINT identification_provider_bindings_processor_permission_check,
    ADD CONSTRAINT identification_provider_bindings_recipient_tuple CHECK (
        (provider = 'gemini' AND binding = 'gemini_baseline_v1'
            AND processor_permission = 'google_gemini' AND provider_model IS NULL
            AND minimum_identification_protocol = 0)
        OR (provider = 'openai' AND binding = 'openai_photo_v1'
            AND processor_permission = 'openai' AND provider_model IS NOT NULL
            AND provider_model = 'gpt-6-sol' AND operation = 'scan_identification'
            AND input_profile = 'multimodal_photo_v1'
            AND minimum_identification_protocol = 4)
    );
ALTER TABLE internal.identification_provider_attempts
    ADD COLUMN provider_model TEXT,
    ADD COLUMN minimum_identification_protocol INTEGER
        CHECK (minimum_identification_protocol IN (0, 4)),
    ADD COLUMN accepted_identification_protocol INTEGER
        CHECK (accepted_identification_protocol = 4),
    DROP CONSTRAINT identification_provider_attempts_provider_check,
    DROP CONSTRAINT identification_provider_attempts_binding_check,
    DROP CONSTRAINT identification_provider_attempts_processor_permission_check,
    ADD CONSTRAINT identification_provider_attempts_recipient_tuple CHECK (
        (provider = 'gemini' AND binding = 'gemini_baseline_v1'
            AND processor_permission = 'google_gemini' AND provider_model IS NULL
            AND ((minimum_identification_protocol IS NULL AND accepted_identification_protocol IS NULL)
                OR (minimum_identification_protocol IS NOT NULL AND minimum_identification_protocol = 0)))
        OR (provider = 'openai' AND binding = 'openai_photo_v1'
            AND processor_permission = 'openai' AND provider_model IS NOT NULL
            AND provider_model = 'gpt-6-sol' AND operation = 'scan_identification'
            AND input_profile IS NOT NULL AND input_profile = 'multimodal_photo_v1'
            AND minimum_identification_protocol IS NOT NULL
            AND minimum_identification_protocol = 4
            AND accepted_identification_protocol IS NOT NULL
            AND accepted_identification_protocol = 4)
    );

COMMENT ON COLUMN internal.identification_provider_bindings.provider_model IS
    'Reviewed provider execution model per complete-input profile. NULL means the unchanged Gemini quota model; model remains the quota-policy lookup key. No current row selects OpenAI.';
COMMENT ON COLUMN internal.identification_provider_attempts.provider_model IS
    'Immutable execution model for this generation, independent of its quota-policy model. NULL is allowed only for Gemini and resolves to this saved attempt model, never a current binding.';
COMMENT ON COLUMN internal.identification_provider_attempts.accepted_identification_protocol IS
    'Original-client identification capability, independent of entitlement protocol. Only 4 is recognized; unknown historical evidence remains NULL.';

CREATE FUNCTION internal.require_identification_capability(
    p_user_id UUID, p_operation TEXT, p_original_analysis_id UUID,
    p_input_profile TEXT, p_identification_protocol INTEGER,
    p_internal_replay BOOLEAN, p_minimum_identification_protocol INTEGER
) RETURNS INTEGER
LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = ''
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
    ELSIF p_identification_protocol = 4 THEN
        accepted := 4;
    END IF;
    IF p_minimum_identification_protocol = 4 AND accepted IS DISTINCT FROM 4 THEN
        RAISE EXCEPTION 'client_update_required' USING ERRCODE = 'P0001';
    END IF;
    RETURN accepted;
END;
$function$;
REVOKE ALL ON FUNCTION internal.require_identification_capability(UUID, TEXT, UUID, TEXT, INTEGER, BOOLEAN, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;

-- Extend only the latest ABI. Preserve the established quota/user locks and
-- rollback boundary: any assignment/capability/consent denial rolls back holds,
-- counters and the reservation together. The caller still cannot select a model.
DO $migration$
DECLARE definition TEXT; arguments TEXT; fragment TEXT; replacement TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine.oid), pg_catalog.PG_GET_FUNCTION_ARGUMENTS(routine.oid)
    INTO STRICT definition, arguments FROM pg_catalog.pg_proc AS routine
    WHERE routine.oid = 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text)'::regprocedure;
    FOR fragment, replacement IN SELECT * FROM (VALUES
        (arguments, arguments || ', p_identification_protocol integer'),
        ('IF p_expected_processor_permission IS NULL OR p_expected_processor_permission NOT IN',
         'IF (p_expected_processor_permission IS NULL AND p_internal_replay IS DISTINCT FROM TRUE) OR p_expected_processor_permission NOT IN'),
        ('IF p_expected_processor_permission IS DISTINCT FROM assignment.processor_permission THEN',
         'IF p_expected_processor_permission IS DISTINCT FROM assignment.processor_permission AND (p_internal_replay IS DISTINCT FROM TRUE OR p_expected_processor_permission IS NOT NULL) THEN'),
        ('attempt internal.identification_provider_attempts%ROWTYPE;',
         'attempt internal.identification_provider_attempts%ROWTYPE; accepted_capability INTEGER;'),
        ('PERFORM internal.require_identification_processor_consent(p_user_id, assignment.processor_permission);',
         'accepted_capability := internal.require_identification_capability(p_user_id, p_operation, p_original_analysis_id, p_input_profile, p_identification_protocol, p_internal_replay, assignment.minimum_identification_protocol);'
         || E'\n        PERFORM internal.require_identification_processor_consent(p_user_id, assignment.processor_permission);'),
        ('policy_version, provider, binding, processor_permission',
         'policy_version, provider, binding, processor_permission, provider_model, minimum_identification_protocol, accepted_identification_protocol'),
        ('assignment.provider, assignment.binding, assignment.processor_permission',
         'assignment.provider, assignment.binding, assignment.processor_permission, assignment.provider_model, assignment.minimum_identification_protocol, accepted_capability'),
        ('OR attempt.processor_permission IS DISTINCT FROM assignment.processor_permission',
         'OR attempt.processor_permission IS DISTINCT FROM assignment.processor_permission'
         || E'\n           OR attempt.provider_model IS DISTINCT FROM assignment.provider_model'
         || E'\n           OR attempt.minimum_identification_protocol IS DISTINCT FROM assignment.minimum_identification_protocol'
         || E'\n           OR attempt.accepted_identification_protocol IS DISTINCT FROM accepted_capability'),
        ('admitted.attempt_count, admitted.model, admitted.effective_plan,',
         'admitted.attempt_count, COALESCE(attempt.provider_model, admitted.model), admitted.effective_plan,')
    ) AS edits(source_text, replacement_text) LOOP
        IF definition IS NULL OR
            (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, fragment, '')))
                / pg_catalog.LENGTH(fragment) <> 1 THEN
            RAISE EXCEPTION 'openai identification admission source drift';
        END IF;
        definition := pg_catalog.REPLACE(definition, fragment, replacement);
    END LOOP;
    EXECUTE definition;
END;
$migration$;
REVOKE ALL ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN, TEXT, TEXT, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN, TEXT, TEXT, INTEGER) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('service_role', 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)',
    'Atomic complete-input provider assignment with independent identification capability and denial-only recipient expectation.');

-- Keep legacy signatures callable and incapable of fresh alternate-provider
-- admission. An already-running replay remains non-dispatchable and unchanged.
DO $migration$
DECLARE signature TEXT; definition TEXT; fragment TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)',
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text)'
    ] LOOP
        definition := pg_catalog.PG_GET_FUNCTIONDEF(pg_catalog.TO_REGPROCEDURE(signature));
        fragment := 'PERFORM internal.require_identification_processor_consent(p_user_id, assignment.processor_permission);';
        IF definition IS NULL OR
            (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, fragment, '')))
                / pg_catalog.LENGTH(fragment) <> 1 THEN
            RAISE EXCEPTION 'legacy identification admission source drift';
        END IF;
        EXECUTE pg_catalog.REPLACE(definition, fragment,
            'IF assignment.provider <> ''gemini'' OR assignment.minimum_identification_protocol <> 0 THEN'
            || E'\n            RAISE EXCEPTION ''client_update_required'' USING ERRCODE = ''P0001'';'
            || E'\n        END IF;\n        ' || fragment);
    END LOOP;
END;
$migration$;

-- New clients advertise both independent capabilities. The returned minimum
-- keeps the two contracts separate; older callers retain their five-argument ABI.
DO $migration$
DECLARE definition TEXT; arguments TEXT; fragment TEXT; replacement TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine.oid), pg_catalog.PG_GET_FUNCTION_ARGUMENTS(routine.oid)
    INTO STRICT definition, arguments FROM pg_catalog.pg_proc AS routine
    WHERE routine.oid = 'public.get_my_identification_preflight(text,text,boolean,uuid,integer)'::regprocedure;
    FOR fragment, replacement IN SELECT * FROM (VALUES
        (arguments, arguments || ', p_identification_protocol integer'),
        ('minimum_client_protocol integer)', 'minimum_client_protocol integer, minimum_identification_protocol integer)'),
        ('NULL::TEXT, rollout.required_client_protocol;', 'NULL::TEXT, rollout.required_client_protocol, NULL::INTEGER;'),
        ('''recovery_only''::TEXT, NULL::TEXT, NULL::INTEGER;', '''recovery_only''::TEXT, NULL::TEXT, NULL::INTEGER, NULL::INTEGER;'),
        ('p_original_analysis_id, p_input_profile, p_client_protocol, FALSE, required_protocol);',
         'p_original_analysis_id, p_input_profile, p_client_protocol, FALSE, required_protocol);'
         || E'\n        PERFORM internal.require_identification_capability(caller_id, p_operation, p_original_analysis_id, p_input_profile, p_identification_protocol, FALSE, assignment.minimum_identification_protocol);'),
        ('result_decision, assignment.processor_permission, required_protocol;',
         'result_decision, assignment.processor_permission, required_protocol, assignment.minimum_identification_protocol;')
    ) AS edits(source_text, replacement_text) LOOP
        IF definition IS NULL OR
            (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, fragment, '')))
                / pg_catalog.LENGTH(fragment) <> 1 THEN
            RAISE EXCEPTION 'identification capability preflight source drift: %', fragment;
        END IF;
        definition := pg_catalog.REPLACE(definition, fragment, replacement);
    END LOOP;
    EXECUTE definition;

    definition := pg_catalog.PG_GET_FUNCTIONDEF('public.get_my_identification_preflight(text,text,boolean,uuid,integer)'::regprocedure);
    fragment := 'required_protocol := GREATEST(assignment.minimum_client_protocol, rollout.required_client_protocol);';
    IF pg_catalog.STRPOS(definition, fragment) = 0 THEN
        RAISE EXCEPTION 'legacy preflight source drift';
    END IF;
    EXECUTE pg_catalog.REPLACE(definition, fragment,
        'IF assignment.minimum_identification_protocol > 0 THEN'
        || E'\n        RETURN QUERY SELECT p_input_profile, ''client_update_required''::TEXT, assignment.processor_permission, assignment.minimum_identification_protocol;'
        || E'\n        RETURN;\n    END IF;\n    ' || fragment);
END;
$migration$;
REVOKE ALL ON FUNCTION public.get_my_identification_preflight(TEXT, TEXT, BOOLEAN, UUID, INTEGER, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_identification_preflight(TEXT, TEXT, BOOLEAN, UUID, INTEGER, INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('authenticated', 'public.get_my_identification_preflight(text,text,boolean,uuid,integer,integer)',
    'Caller-bound read-only recipient preview with independent identification capability; no provider choice or dispatch authority.');

-- The scan trigger remains the sole successful primary-inference ledger writer.
-- Preserve native cache writes and total output (which already includes reasoning)
-- as bounded metadata. Other providers never inherit Gemini tariffs.
DO $migration$
DECLARE definition TEXT; fragment TEXT;
BEGIN
    definition := pg_catalog.PG_GET_FUNCTIONDEF('internal.trg_record_scan_ai_usage()'::regprocedure);
    fragment := 'IF NEW.llm_total_tokens IS NULL THEN RETURN NEW; END IF;';
    IF pg_catalog.STRPOS(definition, fragment) = 0 THEN RAISE EXCEPTION 'scan usage coverage source drift'; END IF;
    definition := pg_catalog.REPLACE(definition, fragment,
        'IF NEW.llm_total_tokens IS NULL AND NEW.identification_provenance ->> ''provider'' IS DISTINCT FROM ''openai'' THEN RETURN NEW; END IF;');
    fragment := 'THEN ''gemini_token_counts_v1'' ELSE NULL END);';
    IF pg_catalog.STRPOS(definition, fragment) = 0 THEN RAISE EXCEPTION 'scan usage contract source drift'; END IF;
    definition := pg_catalog.REPLACE(definition, fragment,
        'THEN ''gemini_token_counts_v1'' WHEN NEW.identification_provenance ->> ''provider'' = ''openai'''
        || E'\n        THEN ''openai_responses_tokens_v1'' ELSE NULL END);'
        || E'\n    IF NEW.identification_provenance ->> ''provider'' = ''openai'' THEN'
        || E'\n      execution_metadata := execution_metadata || pg_catalog.JSONB_BUILD_OBJECT('
        || E'\n        ''ai_cache_write_tokens'', CASE WHEN pg_catalog.JSONB_TYPEOF(NEW.llm_usage_metadata -> ''cache_write_tokens'') = ''number'''
        || E'\n          AND (NEW.llm_usage_metadata ->> ''cache_write_tokens'') ~ ''^[0-9]{1,9}$'''
        || E'\n          THEN NEW.llm_usage_metadata -> ''cache_write_tokens'' ELSE ''null''::JSONB END,'
        || E'\n        ''ai_output_tokens'', CASE WHEN pg_catalog.JSONB_TYPEOF(NEW.llm_usage_metadata -> ''output_tokens'') = ''number'''
        || E'\n          AND (NEW.llm_usage_metadata ->> ''output_tokens'') ~ ''^[0-9]{1,9}$'''
        || E'\n          THEN NEW.llm_usage_metadata -> ''output_tokens'' ELSE ''null''::JSONB END);'
        || E'\n    END IF;');
    EXECUTE definition;
END;
$migration$;

-- The original trigger predicate also skipped scans with entirely missing
-- usage. Such OpenAI results must remain visible as unpriced events.
DROP TRIGGER trg_record_scan_ai_usage ON public.scans;
CREATE TRIGGER trg_record_scan_ai_usage
AFTER INSERT OR UPDATE OF llm_total_tokens ON public.scans
FOR EACH ROW
WHEN (NEW.llm_total_tokens IS NOT NULL OR NEW.identification_provenance ->> 'provider' = 'openai')
EXECUTE FUNCTION internal.trg_record_scan_ai_usage();

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
