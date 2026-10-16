-- Preserve the legacy service ABI while closing the permanent initial-ID namespace.
-- The private core remains available to the authorized atomic-admission owner.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.reserve_ai_quota(
    p_user_id UUID,
    p_operation TEXT,
    p_request_id UUID,
    p_ip_hash TEXT
)
RETURNS TABLE (
    reservation_id UUID, request_id UUID, lease_token UUID,
    lease_expires_at TIMESTAMPTZ, reservation_state TEXT, is_replay BOOLEAN,
    attempt_count INTEGER, model TEXT, effective_plan TEXT, effective_tier TEXT,
    subscription_tier TEXT, trial_active BOOLEAN, entitlement_version BIGINT,
    policy_version BIGINT, daily_limit INTEGER, daily_remaining INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.require_current_ai_consent(p_user_id);

    -- Keep the core's validation/error precedence before taking additional locks.
    IF p_user_id IS NULL
       OR p_request_id IS NULL
       OR p_operation IS NULL
       OR p_operation !~ '^[a-z][a-z0-9_]{2,63}$'
       OR p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'ai_quota_invalid_request' USING ERRCODE = '22023';
    END IF;

    -- The post-lock fence read must observe a competing committed insertion.
    -- Direct callers may not silently retain a pre-lock repeatable-read snapshot.
    IF pg_catalog.current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'ai_quota_isolation_unsupported' USING ERRCODE = '55000';
    END IF;

    PERFORM users.id FROM public.users AS users WHERE users.id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable' USING ERRCODE = 'P0001';
    END IF;
    -- Admission/cancellation use the same owner-before-scan order. Acquire this
    -- outer scope before entering the core's quota-key/counter lock sequence.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('merian-scan-ingestion:' || p_request_id::TEXT, 0::BIGINT)
    );
    IF EXISTS (
        SELECT 1 FROM internal.initial_analysis_operation_fences AS fences
        WHERE fences.scan_id = p_request_id
    ) THEN
        RAISE EXCEPTION 'initial_analysis_admission_required' USING ERRCODE = '55000';
    END IF;

    RETURN QUERY SELECT quota.*
    FROM internal.reserve_ai_quota_core(p_user_id, p_operation, p_request_id, p_ip_hash) AS quota;
END;
$function$;

REVOKE ALL ON FUNCTION public.reserve_ai_quota(UUID,TEXT,UUID,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_ai_quota(UUID,TEXT,UUID,TEXT) TO service_role;

RESET statement_timeout;
RESET lock_timeout;
