-- Beta access is app-assigned and independent of historical OpenAI receipts.
-- Preserve ordinary required consent, receipt history, assignments, and quota.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION internal.require_identification_processor_consent(
    p_user_id UUID,
    p_processor_permission TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    IF p_user_id IS NULL OR p_processor_permission IS NULL
       OR p_processor_permission NOT IN ('google_gemini', 'openai') THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;

    -- This existing gate still checks the required account/Terms/Gemini evidence.
    PERFORM internal.require_current_ai_consent(p_user_id);
    -- OpenAI-specific collection and enforcement are deferred throughout beta.
    -- Do not create, rewrite, or interpret a receipt as a condition of beta access.
END;
$function$;
REVOKE ALL ON FUNCTION internal.require_identification_processor_consent(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION internal.require_identification_processor_consent(UUID, TEXT) IS
    'Beta identification policy: ordinary required consent remains required; OpenAI-specific consent collection and enforcement are deferred for all accounts. Historical OpenAI receipts are preserved and not used for beta admission. Provider assignment and the strict receipt validator remain unchanged.';

RESET lock_timeout;
RESET statement_timeout;
