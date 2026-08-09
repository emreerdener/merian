SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.get_my_scan_admission_preview(
    p_flash_fallback_eligible BOOLEAN
)
RETURNS TABLE (
    decision TEXT,
    effective_plan TEXT,
    daily_limit INTEGER,
    daily_remaining INTEGER
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    caller_id UUID := (SELECT auth.uid());
    entitlement_row RECORD;
    policy_row internal.ai_quota_policies%ROWTYPE;
    resolved_plan TEXT;
    quota_window_start TIMESTAMPTZ;
    quota_count INTEGER;
    remaining_count INTEGER;
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;
    IF p_flash_fallback_eligible IS NULL THEN
        RAISE EXCEPTION 'scan_admission_preview_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    SELECT entitlement.*
    INTO entitlement_row
    FROM internal.resolve_effective_entitlement(caller_id) AS entitlement;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    IF entitlement_row.current_plan IN ('pro_paid', 'pro_trial') THEN
        resolved_plan := entitlement_row.current_plan;
    ELSIF entitlement_row.current_plan = 'pro_complimentary'
          AND entitlement_row.scans_available_to_start > 0 THEN
        resolved_plan := 'pro_complimentary';
    ELSIF p_flash_fallback_eligible THEN
        resolved_plan := 'free';
    ELSE
        RETURN QUERY
        SELECT
            'pro_required'::TEXT,
            entitlement_row.current_plan::TEXT,
            NULL::INTEGER,
            NULL::INTEGER;
        RETURN;
    END IF;

    SELECT policies.*
    INTO policy_row
    FROM internal.ai_quota_policies AS policies
    WHERE policies.operation = 'scan_identification'
      AND policies.effective_plan = resolved_plan;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_quota_policy_missing'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.enabled THEN
        RAISE EXCEPTION 'ai_quota_policy_disabled'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.allowed THEN
        RETURN QUERY
        SELECT
            'pro_required'::TEXT,
            resolved_plan,
            NULL::INTEGER,
            NULL::INTEGER;
        RETURN;
    END IF;

    IF policy_row.daily_limit IS NULL THEN
        RETURN QUERY
        SELECT
            'allowed'::TEXT,
            resolved_plan,
            NULL::INTEGER,
            NULL::INTEGER;
        RETURN;
    END IF;

    quota_window_start := pg_catalog.DATE_TRUNC(
        'day',
        pg_catalog.CLOCK_TIMESTAMP(),
        'UTC'
    );
    SELECT counters.request_count
    INTO quota_count
    FROM internal.ai_quota_counters AS counters
    WHERE counters.scope_type = 'user_daily'
      AND counters.scope_key = caller_id::TEXT
      AND counters.bucket = policy_row.daily_bucket
      AND counters.window_start = quota_window_start;

    quota_count := COALESCE(quota_count, 0);
    remaining_count := GREATEST(policy_row.daily_limit - quota_count, 0);

    RETURN QUERY
    SELECT
        CASE
            WHEN remaining_count > 0 THEN 'allowed'::TEXT
            ELSE 'daily_quota_exhausted'::TEXT
        END,
        resolved_plan,
        policy_row.daily_limit,
        remaining_count;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_scan_admission_preview(BOOLEAN)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_scan_admission_preview(BOOLEAN)
    TO authenticated;

COMMENT ON FUNCTION public.get_my_scan_admission_preview(BOOLEAN) IS
    'Caller-scoped, read-only scan admission preview for pre-capture UX. It does not reserve entitlement or quota; reserve_ai_quota remains authoritative.';

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'authenticated',
    'public.get_my_scan_admission_preview(boolean)',
    'Current-caller-only read of prospective scan entitlement and daily quota availability before Capture begins processing.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
