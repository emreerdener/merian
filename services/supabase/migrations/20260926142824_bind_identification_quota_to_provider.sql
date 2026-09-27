-- Establish provider-bound identification admission without enabling another
-- provider. Existing quota RPCs, policy rows, consent receipts and dispatch stay
-- Gemini-only. A new metered retry gets a new immutable attempt snapshot.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

CREATE TABLE internal.identification_provider_bindings (
    operation TEXT NOT NULL CHECK (operation IN ('scan_identification', 'scan_audio_identification')),
    effective_plan TEXT NOT NULL CHECK (effective_plan IN ('free', 'pro_trial', 'pro_complimentary', 'pro_paid')),
    model TEXT NOT NULL CHECK (model IN ('gemini-2.5-flash', 'gemini-2.5-pro')),
    policy_version BIGINT NOT NULL CHECK (policy_version > 0),
    provider TEXT NOT NULL CHECK (provider = 'gemini'),
    binding TEXT NOT NULL CHECK (binding = 'gemini_baseline_v1'),
    processor_permission TEXT NOT NULL CHECK (processor_permission = 'google_gemini'),
    PRIMARY KEY (operation, effective_plan, model, policy_version)
);

INSERT INTO internal.identification_provider_bindings (
    operation, effective_plan, model, policy_version,
    provider, binding, processor_permission
)
SELECT policies.operation, policies.effective_plan, policies.model,
    policies.policy_version, 'gemini', 'gemini_baseline_v1', 'google_gemini'
FROM internal.ai_quota_policies AS policies
WHERE policies.operation IN ('scan_identification', 'scan_audio_identification')
  AND policies.allowed AND policies.enabled;

CREATE TABLE internal.identification_provider_attempts (
    reservation_id UUID NOT NULL REFERENCES internal.ai_quota_reservations(id) ON DELETE CASCADE,
    attempt_count INTEGER NOT NULL CHECK (attempt_count > 0),
    operation TEXT NOT NULL CHECK (operation IN ('scan_identification', 'scan_audio_identification')),
    effective_plan TEXT NOT NULL CHECK (effective_plan IN ('free', 'pro_trial', 'pro_complimentary', 'pro_paid')),
    model TEXT NOT NULL CHECK (model IN ('gemini-2.5-flash', 'gemini-2.5-pro')),
    policy_version BIGINT NOT NULL CHECK (policy_version > 0),
    provider TEXT NOT NULL CHECK (provider = 'gemini'),
    binding TEXT NOT NULL CHECK (binding = 'gemini_baseline_v1'),
    processor_permission TEXT NOT NULL CHECK (processor_permission = 'google_gemini'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (reservation_id, attempt_count)
);

ALTER TABLE internal.identification_provider_bindings ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.identification_provider_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.identification_provider_bindings,
    internal.identification_provider_attempts FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.identification_provider_bindings IS
    'Reviewed exact identification quota assignments. No API access or client-selected provider; only Gemini is qualified by this migration.';
COMMENT ON TABLE internal.identification_provider_attempts IS
    'Immutable recipient/binding evidence per metered reservation generation; retained with the existing quota reservation lifetime, not permanent scan provenance or a generation-profile digest.';

CREATE FUNCTION internal.require_current_ai_consent(p_user_id UUID, p_processor_permission TEXT)
RETURNS VOID
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    IF p_processor_permission IS DISTINCT FROM 'google_gemini' THEN
        RAISE EXCEPTION 'ai_consent_required' USING ERRCODE = 'P0001';
    END IF;
    PERFORM internal.require_current_ai_consent(p_user_id);
END;
$function$;
REVOKE ALL ON FUNCTION internal.require_current_ai_consent(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.reserve_identification_quota(
    p_user_id UUID,
    p_operation TEXT,
    p_request_id UUID,
    p_ip_hash TEXT,
    p_original_analysis_id UUID,
    p_flash_fallback_eligible BOOLEAN,
    p_client_protocol INTEGER,
    p_internal_replay BOOLEAN
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
    processor_permission TEXT
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
    IF p_operation IS NULL OR p_operation NOT IN ('scan_identification', 'scan_audio_identification') THEN
        RAISE EXCEPTION 'ai_quota_invalid_request' USING ERRCODE = '22023';
    END IF;

    -- The established user/reservation locks, consent, entitlement, counters and
    -- idempotency remain authoritative. Any failure below rolls them back too.
    SELECT quota.* INTO STRICT admitted
    FROM public.reserve_ai_quota(
        p_user_id, p_operation, p_request_id, p_ip_hash,
        p_original_analysis_id, p_flash_fallback_eligible,
        p_client_protocol, p_internal_replay
    ) AS quota;

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
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
        END IF;
        PERFORM internal.require_current_ai_consent(p_user_id, assignment.processor_permission);
        INSERT INTO internal.identification_provider_attempts AS saved (
            reservation_id, attempt_count, operation, effective_plan, model,
            policy_version, provider, binding, processor_permission
        ) VALUES (
            admitted.reservation_id, admitted.attempt_count, p_operation,
            admitted.effective_plan, admitted.model, admitted.policy_version,
            assignment.provider, assignment.binding, assignment.processor_permission
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
           OR attempt.policy_version IS DISTINCT FROM admitted.policy_version THEN
            RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
        END IF;
        PERFORM internal.require_current_ai_consent(p_user_id, attempt.processor_permission);
    ELSIF NOT admitted.is_replay THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
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
        attempt.provider, attempt.binding, attempt.processor_permission;
END;
$function$;

REVOKE ALL ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_identification_quota(UUID, TEXT, UUID, TEXT, UUID, BOOLEAN, INTEGER, BOOLEAN)
    TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('service_role', 'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
    'Atomic identification quota reservation and immutable provider-recipient assignment per admitted attempt.');

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
