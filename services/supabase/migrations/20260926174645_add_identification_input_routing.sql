-- Server-owned complete-input routing; every enabled assignment remains Gemini.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

DO $migration$
DECLARE
    signature TEXT;
    arguments TEXT;
    call_arguments TEXT;
    definition TEXT;
    core_definition TEXT;
    result_type TEXT;
    consent_fragment CONSTANT TEXT := 'PERFORM internal.require_current_ai_consent(p_user_id);';
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'uuid,text,uuid,text', 'uuid,text,uuid,text,uuid,boolean,integer,boolean'
    ] LOOP
        SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine.oid),
               pg_catalog.PG_GET_FUNCTION_ARGUMENTS(routine.oid),
               pg_catalog.PG_GET_FUNCTION_RESULT(routine.oid)
        INTO STRICT definition, arguments, result_type
        FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid = pg_catalog.TO_REGPROCEDURE('public.reserve_ai_quota(' || signature || ')');
        IF (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, consent_fragment, '')))
               / pg_catalog.LENGTH(consent_fragment) <> 1
           OR pg_catalog.STRPOS(definition, 'PERFORM internal.require_service_role();') = 0
           OR pg_catalog.STRPOS(definition, 'SECURITY DEFINER') = 0 THEN
            RAISE EXCEPTION 'identification_quota_core_source_drift' USING ERRCODE = '55000';
        END IF;
        -- Retain the established entitlement/user/reservation/counter locks and
        -- all quota math. The eight-argument core delegates only to the private
        -- four-argument core; no nested unconditional recipient check remains.
        core_definition := pg_catalog.REPLACE(definition,
            'public.reserve_ai_quota(', 'internal.reserve_ai_quota_core(');
        core_definition := pg_catalog.REPLACE(core_definition, consent_fragment, '');
        core_definition := pg_catalog.REPLACE(core_definition, 'SECURITY DEFINER', 'SECURITY INVOKER');
        EXECUTE core_definition;
        EXECUTE 'REVOKE ALL ON FUNCTION internal.reserve_ai_quota_core(' || signature || ') FROM PUBLIC, anon, authenticated, service_role';

        call_arguments := 'p_user_id, p_operation, p_request_id, p_ip_hash';
        IF signature <> 'uuid,text,uuid,text' THEN
            call_arguments := call_arguments || ', p_original_analysis_id, p_flash_fallback_eligible, p_client_protocol, p_internal_replay';
        END IF;
        EXECUTE pg_catalog.FORMAT(
            'CREATE OR REPLACE FUNCTION public.reserve_ai_quota(%s) RETURNS %s
             LANGUAGE plpgsql SECURITY DEFINER SET search_path = '''' SET statement_timeout = ''5s''
             AS $function$ BEGIN
                 PERFORM internal.require_service_role();
                 PERFORM internal.require_current_ai_consent(p_user_id);
                 RETURN QUERY SELECT quota.* FROM internal.reserve_ai_quota_core(%s) AS quota;
             END; $function$', arguments, result_type, call_arguments);
    END LOOP;
END;
$migration$;

ALTER TABLE internal.identification_provider_bindings
    ADD COLUMN input_profile TEXT NOT NULL DEFAULT 'legacy_v1';
ALTER TABLE internal.identification_provider_attempts
    ADD COLUMN input_profile TEXT;
ALTER TABLE internal.identification_provider_bindings
    ADD CONSTRAINT identification_provider_bindings_input_profile_check
    CHECK (input_profile IN ('legacy_v1', 'description_compat_v1', 'vision_compat_v1', 'audio_compat_v1', 'multimodal_text_v1', 'multimodal_photo_v1', 'multimodal_audio_v1', 'multimodal_photo_audio_v1', 'multimodal_video_frames_v1', 'multimodal_video_audio_v1'));
ALTER TABLE internal.identification_provider_attempts
    ADD CONSTRAINT identification_provider_attempts_input_profile_check
    CHECK (input_profile IN ('legacy_v1', 'description_compat_v1', 'vision_compat_v1', 'audio_compat_v1', 'multimodal_text_v1', 'multimodal_photo_v1', 'multimodal_audio_v1', 'multimodal_photo_audio_v1', 'multimodal_video_frames_v1', 'multimodal_video_audio_v1'));
ALTER TABLE internal.identification_provider_bindings
    DROP CONSTRAINT identification_provider_bindings_pkey,
    ADD PRIMARY KEY (operation, effective_plan, model, policy_version, input_profile);

INSERT INTO internal.identification_provider_bindings (
    operation, effective_plan, model, policy_version, provider, binding, processor_permission, input_profile
)
SELECT bindings.operation, bindings.effective_plan, bindings.model, bindings.policy_version,
       bindings.provider, bindings.binding, bindings.processor_permission, profiles.input_profile
FROM internal.identification_provider_bindings AS bindings
CROSS JOIN (VALUES
    ('description_compat_v1'),
    ('vision_compat_v1'),
    ('audio_compat_v1'),
    ('multimodal_text_v1'),
    ('multimodal_photo_v1'),
    ('multimodal_audio_v1'),
    ('multimodal_photo_audio_v1'),
    ('multimodal_video_frames_v1'),
    ('multimodal_video_audio_v1')
) AS profiles(input_profile)
WHERE bindings.input_profile = 'legacy_v1'
  AND ((bindings.operation = 'scan_audio_identification') = (profiles.input_profile = 'audio_compat_v1'));

-- Old workers retain their exact eight-argument ABI and legacy policy lane.
DO $migration$
DECLARE
    definition TEXT;
    source_fragment CONSTANT TEXT := 'AND bindings.policy_version = admitted.policy_version';
BEGIN
    definition := pg_catalog.PG_GET_FUNCTIONDEF('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::regprocedure);
    IF pg_catalog.STRPOS(definition, source_fragment) = 0 THEN
        RAISE EXCEPTION 'identification_legacy_binding_source_drift' USING ERRCODE = '55000';
    END IF;
    EXECUTE pg_catalog.REPLACE(definition, source_fragment,
        source_fragment || ' AND bindings.input_profile = ''legacy_v1''');
END;
$migration$;

CREATE FUNCTION public.reserve_identification_quota(
    p_user_id UUID,
    p_operation TEXT,
    p_request_id UUID,
    p_ip_hash TEXT,
    p_original_analysis_id UUID,
    p_flash_fallback_eligible BOOLEAN,
    p_client_protocol INTEGER,
    p_internal_replay BOOLEAN,
    p_input_profile TEXT
)
RETURNS TABLE (
    reservation_id UUID,
    request_id UUID,
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    reservation_state TEXT,
    is_replay BOOLEAN,
    attempt_count INTEGER,
    model TEXT,
    effective_plan TEXT,
    effective_tier TEXT,
    subscription_tier TEXT,
    trial_active BOOLEAN,
    entitlement_version BIGINT,
    policy_version BIGINT,
    daily_limit INTEGER,
    daily_remaining INTEGER,
    original_analysis_id UUID,
    complimentary_client_scan_id UUID,
    flash_fallback_used BOOLEAN,
    scans_remaining INTEGER,
    scans_available_to_start INTEGER,
    in_flight_count INTEGER,
    provider TEXT,
    binding TEXT,
    processor_permission TEXT,
    input_profile TEXT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    admitted RECORD;
    assignment internal.identification_provider_bindings%ROWTYPE;
    attempt internal.identification_provider_attempts%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    IF p_operation IS NULL OR p_operation NOT IN ('scan_identification', 'scan_audio_identification')
       OR p_input_profile IS NULL OR p_input_profile NOT IN ('description_compat_v1', 'vision_compat_v1', 'audio_compat_v1', 'multimodal_text_v1', 'multimodal_photo_v1', 'multimodal_audio_v1', 'multimodal_photo_audio_v1', 'multimodal_video_frames_v1', 'multimodal_video_audio_v1')
       OR ((p_operation = 'scan_audio_identification') <> (p_input_profile = 'audio_compat_v1')) THEN
        RAISE EXCEPTION 'ai_quota_invalid_request' USING ERRCODE = '22023';
    END IF;

    -- The established user/reservation locks, entitlement, counters and
    -- idempotency remain authoritative. Any failure below rolls them back too.
    SELECT quota.* INTO STRICT admitted
    FROM internal.reserve_ai_quota_core(
        p_user_id, p_operation, p_request_id, p_ip_hash,
        p_original_analysis_id, p_flash_fallback_eligible,
        p_client_protocol, p_internal_replay
    ) AS quota;

    -- A request identifier cannot change its complete-input class on a metered
    -- retry. Historical attempts without a profile remain unknown.
    IF NOT admitted.is_replay AND EXISTS (SELECT 1 FROM internal.identification_provider_attempts AS saved
        WHERE saved.reservation_id = admitted.reservation_id
          AND saved.input_profile IS NOT NULL
          AND saved.input_profile IS DISTINCT FROM p_input_profile) THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;

    SELECT saved.* INTO attempt
    FROM internal.identification_provider_attempts AS saved
    WHERE saved.reservation_id = admitted.reservation_id
      AND saved.attempt_count = admitted.attempt_count;

    IF NOT FOUND AND NOT admitted.is_replay THEN
        SELECT bindings.* INTO assignment
        FROM internal.identification_provider_bindings AS bindings
        WHERE bindings.operation = p_operation
          AND bindings.effective_plan = admitted.effective_plan
          AND bindings.model = admitted.model
          AND bindings.policy_version = admitted.policy_version
          AND bindings.input_profile = p_input_profile
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
        END IF;
        PERFORM internal.require_current_ai_consent(p_user_id, assignment.processor_permission);
        INSERT INTO internal.identification_provider_attempts AS saved (
            reservation_id, attempt_count, operation, effective_plan, model,
            policy_version, provider, binding, processor_permission, input_profile
        ) VALUES (
            admitted.reservation_id, admitted.attempt_count, p_operation,
            admitted.effective_plan, admitted.model, admitted.policy_version,
            assignment.provider, assignment.binding, assignment.processor_permission, p_input_profile
        ) ON CONFLICT ON CONSTRAINT identification_provider_attempts_pkey DO NOTHING;
        SELECT saved.* INTO STRICT attempt
        FROM internal.identification_provider_attempts AS saved
        WHERE saved.reservation_id = admitted.reservation_id
          AND saved.attempt_count = admitted.attempt_count;
        IF attempt.provider IS DISTINCT FROM assignment.provider
           OR attempt.binding IS DISTINCT FROM assignment.binding
           OR attempt.processor_permission IS DISTINCT FROM assignment.processor_permission THEN
            RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF attempt.reservation_id IS NOT NULL THEN
        IF attempt.operation IS DISTINCT FROM p_operation
           OR attempt.effective_plan IS DISTINCT FROM admitted.effective_plan
           OR attempt.model IS DISTINCT FROM admitted.model
           OR attempt.policy_version IS DISTINCT FROM admitted.policy_version
           OR (NOT admitted.is_replay AND attempt.input_profile IS DISTINCT FROM p_input_profile) THEN
            RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
        END IF;
        PERFORM internal.require_current_ai_consent(p_user_id, attempt.processor_permission);
    ELSIF NOT admitted.is_replay THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    ELSE
        PERFORM internal.require_current_ai_consent(p_user_id);
    END IF;

    -- A still-running or committed legacy reservation has no snapshot. Keep it
    -- a non-dispatchable replay; never manufacture historical provider evidence.
    RETURN QUERY SELECT
        admitted.reservation_id, admitted.request_id, admitted.lease_token,
        admitted.lease_expires_at, admitted.reservation_state, admitted.is_replay,
        admitted.attempt_count, admitted.model, admitted.effective_plan,
        admitted.effective_tier, admitted.subscription_tier, admitted.trial_active,
        admitted.entitlement_version, admitted.policy_version, admitted.daily_limit,
        admitted.daily_remaining, admitted.original_analysis_id,
        admitted.complimentary_client_scan_id, admitted.flash_fallback_used,
        admitted.scans_remaining, admitted.scans_available_to_start, admitted.in_flight_count,
        attempt.provider, attempt.binding, attempt.processor_permission, attempt.input_profile;
END;
$function$;

REVOKE ALL ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN, TEXT)
    TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('service_role', 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)',
    'Atomic complete-input identification routing and recipient consent; no client provider selector.');

COMMENT ON COLUMN internal.identification_provider_attempts.input_profile IS
    'Server-derived complete-input class per attempt; historical attempts stay null. Not a user provider choice.';
COMMENT ON COLUMN internal.identification_provider_bindings.input_profile IS
    'Reviewed server routing lane. legacy_v1 preserves older workers; all current rows remain Gemini.';
NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
