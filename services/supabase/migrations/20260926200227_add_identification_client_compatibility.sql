-- Route-specific compatibility is independent of the global entitlement cutoff.
-- Zero preserves every existing Gemini lane, including schema-first clients.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

ALTER TABLE internal.identification_provider_bindings
    ADD COLUMN minimum_client_protocol INTEGER NOT NULL DEFAULT 0
        CHECK (minimum_client_protocol BETWEEN 0 AND 1000);
ALTER TABLE internal.identification_provider_attempts
    ADD COLUMN minimum_client_protocol INTEGER
        CHECK (minimum_client_protocol BETWEEN 0 AND 1000),
    ADD COLUMN accepted_client_protocol INTEGER
        CHECK (accepted_client_protocol BETWEEN 1 AND 3);

-- A protocol is a client compatibility claim, never identity or permission.
-- Internal workers cannot create such a claim on behalf of an older client.
CREATE FUNCTION internal.require_identification_client_protocol(
    p_user_id UUID,
    p_operation TEXT,
    p_original_analysis_id UUID,
    p_input_profile TEXT,
    p_client_protocol INTEGER,
    p_internal_replay BOOLEAN,
    p_minimum_client_protocol INTEGER
)
RETURNS INTEGER
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    accepted_protocol INTEGER;
BEGIN
    IF p_minimum_client_protocol IS NULL
       OR p_minimum_client_protocol NOT BETWEEN 0 AND 1000
       OR p_internal_replay IS NULL THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;

    IF p_internal_replay THEN
        -- Use the original client reservation's current generation, scoped to
        -- the same owner, operation, observation and complete-input profile.
        -- A replay-derived request ID or legacy reservation-level COALESCE of
        -- client_protocol is not evidence of this generation's capability.
        SELECT saved.accepted_client_protocol INTO accepted_protocol
        FROM internal.ai_quota_reservations AS source
        JOIN internal.identification_provider_attempts AS saved
          ON saved.reservation_id = source.id
         AND saved.attempt_count = source.attempt_count
        WHERE source.user_id = p_user_id
          AND source.operation = p_operation
          AND source.request_id = p_original_analysis_id
          AND source.original_analysis_id = p_original_analysis_id
          AND saved.operation = p_operation
          AND saved.input_profile IS NOT DISTINCT FROM p_input_profile;
    ELSIF p_client_protocol BETWEEN 1 AND 3 THEN
        accepted_protocol := p_client_protocol;
    END IF;

    IF p_minimum_client_protocol > 0 AND (
        accepted_protocol IS NULL
        OR accepted_protocol < p_minimum_client_protocol
        OR accepted_protocol > 3
    ) THEN
        RAISE EXCEPTION 'client_update_required' USING ERRCODE = 'P0001';
    END IF;
    RETURN accepted_protocol;
END;
$function$;
REVOKE ALL ON FUNCTION internal.require_identification_client_protocol(UUID, TEXT, UUID, TEXT, INTEGER, BOOLEAN, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;

-- Keep both service-only RPC ABIs and their existing locks/accounting intact.
-- Guard every source replacement so schema drift stops migration replay.
DO $patch$
DECLARE
    signature TEXT;
    definition TEXT;
    fragment TEXT;
    replacement TEXT;
    profile_expression TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)'
    ] LOOP
        definition := pg_catalog.PG_GET_FUNCTIONDEF(pg_catalog.TO_REGPROCEDURE(signature));
        profile_expression := CASE WHEN signature LIKE '%,text)' THEN 'p_input_profile' ELSE 'NULL::TEXT' END;
        FOR fragment, replacement IN SELECT * FROM (VALUES
            ('attempt internal.identification_provider_attempts%ROWTYPE;',
             'attempt internal.identification_provider_attempts%ROWTYPE; accepted_protocol INTEGER;'),
            ('PERFORM internal.require_identification_processor_consent(p_user_id, assignment.processor_permission);',
             'accepted_protocol := internal.require_identification_client_protocol(p_user_id, p_operation, p_original_analysis_id, '
             || profile_expression || ', p_client_protocol, p_internal_replay, assignment.minimum_client_protocol);'
             || E'\n        PERFORM internal.require_identification_processor_consent(p_user_id, assignment.processor_permission);'),
            ('policy_version, provider, binding, processor_permission',
             'policy_version, provider, binding, processor_permission, minimum_client_protocol, accepted_client_protocol'),
            ('assignment.provider, assignment.binding, assignment.processor_permission',
             'assignment.provider, assignment.binding, assignment.processor_permission, assignment.minimum_client_protocol, accepted_protocol'),
            ('OR attempt.processor_permission IS DISTINCT FROM assignment.processor_permission THEN',
             'OR attempt.processor_permission IS DISTINCT FROM assignment.processor_permission'
             || E'\n           OR attempt.minimum_client_protocol IS DISTINCT FROM assignment.minimum_client_protocol'
             || E'\n           OR attempt.accepted_client_protocol IS DISTINCT FROM accepted_protocol THEN'),
            ('IF attempt.reservation_id IS NOT NULL THEN',
             'IF attempt.reservation_id IS NOT NULL THEN'
             || E'\n        IF NOT admitted.is_replay AND (attempt.minimum_client_protocol IS NULL'
             || E'\n            OR attempt.minimum_client_protocol IS DISTINCT FROM assignment.minimum_client_protocol'
             || E'\n            OR attempt.accepted_client_protocol IS DISTINCT FROM accepted_protocol) THEN'
             || E'\n            RAISE EXCEPTION ''ai_provider_assignment_unavailable'' USING ERRCODE = ''P0001'';'
             || E'\n        END IF;')
        ) AS edits(source_text, replacement_text) LOOP
            IF definition IS NULL OR
                (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, fragment, '')))
                    / pg_catalog.LENGTH(fragment) <> 1 THEN
                RAISE EXCEPTION 'identification compatibility source drift: %', signature;
            END IF;
            definition := pg_catalog.REPLACE(definition, fragment, replacement);
        END LOOP;
        EXECUTE definition;
    END LOOP;
END;
$patch$;

COMMENT ON COLUMN internal.identification_provider_bindings.minimum_client_protocol IS
    'App-owned route compatibility requirement. Zero adds no cutoff; every enabled Gemini row remains zero. Does not grant consent or activate a provider.';
COMMENT ON COLUMN internal.identification_provider_attempts.minimum_client_protocol IS
    'Immutable requirement for this admitted generation. Historical unknown remains null; replay does not reinterpret it.';
COMMENT ON COLUMN internal.identification_provider_attempts.accepted_client_protocol IS
    'Recognized original-client capability claim for this generation; never inferred from a worker header. Null means unknown, not compatible.';
NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
