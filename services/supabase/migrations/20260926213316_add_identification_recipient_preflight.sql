-- Read-only recipient discovery; no quota, hold, consent or provider mutation.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

CREATE FUNCTION public.get_my_identification_preflight(
    p_operation TEXT,
    p_input_profile TEXT,
    p_flash_fallback_eligible BOOLEAN,
    p_original_analysis_id UUID,
    p_client_protocol INTEGER
)
RETURNS TABLE (
    input_profile TEXT,
    decision TEXT,
    processor_permission TEXT,
    minimum_client_protocol INTEGER
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    caller_id UUID := (SELECT auth.uid());
    entitlement RECORD;
    rollout internal.entitlement_rollout_config%ROWTYPE;
    policy internal.ai_quota_policies%ROWTYPE;
    assignment internal.identification_provider_bindings%ROWTYPE;
    resolved_plan TEXT;
    required_protocol INTEGER;
    result_decision TEXT := 'ready';
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
    END IF;
    IF p_operation IS NULL OR p_operation NOT IN ('scan_identification', 'scan_audio_identification')
       OR p_input_profile IS NULL OR p_input_profile NOT IN ('description_compat_v1', 'vision_compat_v1', 'audio_compat_v1', 'multimodal_text_v1', 'multimodal_photo_v1', 'multimodal_audio_v1', 'multimodal_photo_audio_v1', 'multimodal_video_frames_v1', 'multimodal_video_audio_v1')
       OR ((p_operation = 'scan_audio_identification') <> (p_input_profile = 'audio_compat_v1'))
       OR p_flash_fallback_eligible IS NULL OR p_original_analysis_id IS NULL
       OR (p_client_protocol IS NOT NULL AND p_client_protocol NOT BETWEEN 1 AND 1000) THEN
        RAISE EXCEPTION 'identification_preflight_invalid_request' USING ERRCODE = '22023';
    END IF;

    SELECT config.* INTO STRICT rollout
    FROM internal.entitlement_rollout_config AS config WHERE config.config_key = 'current';
    -- Public Identify applies this global gate before result recovery and
    -- entitlement. Preserve its order independently of per-binding minima.
    IF rollout.required_client_protocol > 0 AND (p_client_protocol IS NULL
        OR p_client_protocol < rollout.required_client_protocol OR p_client_protocol > 3) THEN
        RETURN QUERY SELECT p_input_profile, 'client_update_required'::TEXT,
            NULL::TEXT, rollout.required_client_protocol;
        RETURN;
    END IF;

    -- A duplicate may retrieve a stored result or a non-dispatchable conflict.
    -- It must never reinterpret old/unknown recipient evidence as a new grant.
    IF EXISTS (SELECT 1 FROM internal.ai_quota_reservations AS reservation
        WHERE reservation.user_id = caller_id
          AND reservation.operation = p_operation
          AND reservation.request_id = p_original_analysis_id
          AND (reservation.state = 'committed' OR
              (reservation.state = 'reserved' AND reservation.lease_expires_at > pg_catalog.CLOCK_TIMESTAMP()))) THEN
        RETURN QUERY SELECT p_input_profile, 'recovery_only'::TEXT, NULL::TEXT, NULL::INTEGER;
        RETURN;
    END IF;

    SELECT resolved.* INTO STRICT entitlement
    FROM internal.resolve_effective_entitlement(caller_id) AS resolved;

    IF entitlement.current_plan IN ('pro_paid', 'pro_trial') THEN
        resolved_plan := entitlement.current_plan;
    ELSIF rollout.entitlement_mode = 'legacy_trial' THEN
        resolved_plan := 'free';
    ELSIF EXISTS (SELECT 1 FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = caller_id AND usage.client_scan_id = p_original_analysis_id
          AND usage.state IN ('held', 'consumed'))
        OR entitlement.scans_available_to_start > 0 THEN
        resolved_plan := 'pro_complimentary';
    ELSIF p_flash_fallback_eligible THEN
        resolved_plan := 'free';
    ELSE
        RAISE EXCEPTION 'ai_entitlement_required' USING ERRCODE = 'P0001';
    END IF;

    SELECT policies.* INTO policy FROM internal.ai_quota_policies AS policies
    WHERE policies.operation = p_operation AND policies.effective_plan = resolved_plan;
    IF NOT FOUND OR NOT policy.enabled THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy.allowed THEN
        RAISE EXCEPTION 'ai_entitlement_required' USING ERRCODE = 'P0001';
    END IF;
    SELECT bindings.* INTO assignment FROM internal.identification_provider_bindings AS bindings
    WHERE bindings.operation = p_operation AND bindings.effective_plan = resolved_plan
      AND bindings.model = policy.model AND bindings.policy_version = policy.policy_version
      AND bindings.input_profile = p_input_profile;
    IF NOT FOUND OR assignment.processor_permission NOT IN ('google_gemini', 'openai') THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;

    required_protocol := GREATEST(assignment.minimum_client_protocol, rollout.required_client_protocol);
    BEGIN
        PERFORM internal.require_identification_client_protocol(caller_id, p_operation,
            p_original_analysis_id, p_input_profile, p_client_protocol, FALSE, required_protocol);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
        result_decision := 'client_update_required';
    END;
    IF result_decision = 'ready' THEN
        BEGIN
            PERFORM internal.require_identification_processor_consent(caller_id, assignment.processor_permission);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM NOT IN ('ai_consent_required', 'ai_openai_consent_required') THEN RAISE; END IF;
            result_decision := 'permission_required';
        END;
    END IF;
    RETURN QUERY SELECT p_input_profile, result_decision, assignment.processor_permission, required_protocol;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_my_identification_preflight(TEXT, TEXT, BOOLEAN, UUID, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_identification_preflight(TEXT, TEXT, BOOLEAN, UUID, INTEGER) TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('authenticated', 'public.get_my_identification_preflight(text,text,boolean,uuid,integer)',
    'Caller-bound read-only assigned recipient check for a complete observation shape; not quota or disclosure authority.');

-- Preserve the old eight/nine-argument ABIs. The new overload is the reviewed
-- nine-argument implementation plus one denial-only recipient expectation.
DO $migration$
DECLARE
    definition TEXT;
    arguments TEXT;
    fragment TEXT;
    replacement TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine.oid), pg_catalog.PG_GET_FUNCTION_ARGUMENTS(routine.oid)
    INTO STRICT definition, arguments FROM pg_catalog.pg_proc AS routine
    WHERE routine.oid = 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)'::regprocedure;
    FOR fragment, replacement IN SELECT * FROM (VALUES
        (arguments, arguments || ', p_expected_processor_permission text'),
        ('PERFORM internal.require_service_role();',
         'PERFORM internal.require_service_role();'
         || E'\n    IF p_expected_processor_permission IS NULL OR p_expected_processor_permission NOT IN (''google_gemini'', ''openai'', ''recovery_only'') THEN'
         || E'\n        RAISE EXCEPTION ''ai_quota_invalid_request'' USING ERRCODE = ''22023'';'
         || E'\n    END IF;'),
        ('PERFORM internal.require_identification_processor_consent(p_user_id, assignment.processor_permission);',
         'IF p_expected_processor_permission IS DISTINCT FROM assignment.processor_permission THEN'
         || E'\n            RAISE EXCEPTION ''ai_identification_preflight_changed'' USING ERRCODE = ''P0001'';'
         || E'\n        END IF;'
         || E'\n        PERFORM internal.require_identification_processor_consent(p_user_id, assignment.processor_permission);')
    ) AS edits(source_text, replacement_text) LOOP
        IF definition IS NULL OR
            (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, fragment, '')))
                / pg_catalog.LENGTH(fragment) <> 1 THEN
            RAISE EXCEPTION 'identification preflight source drift';
        END IF;
        definition := pg_catalog.REPLACE(definition, fragment, replacement);
    END LOOP;
    EXECUTE definition;
END;
$migration$;
REVOKE ALL ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN, TEXT, TEXT) TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('service_role', 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text)',
    'Atomic identification admission with a denial-only expected recipient; never a provider selector.');

COMMENT ON FUNCTION public.get_my_identification_preflight(TEXT, TEXT, BOOLEAN, UUID, INTEGER) IS
    'Advisory assigned-recipient preflight; no allowance promise or dispatch authority. Profile/Flash flags are hints; final admission re-derives them. Active reservations are recovery-only with no inferred recipient.';
COMMENT ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN, TEXT, TEXT) IS
    'Recipient expectation only denies fresh assignment drift. recovery_only cannot admit new work. Saved replays retain their prior non-dispatchable semantics.';
NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
