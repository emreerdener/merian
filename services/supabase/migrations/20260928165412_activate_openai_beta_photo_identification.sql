-- Deploy and verify the enabled OpenAI Function bundle before this migration.
-- Beta photo processing defers a new opt-in; explicit withdrawals remain binding.
-- No consent evidence, quota policy, immutable attempt, or other modality changes.
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
DECLARE
    stream_head_event_kind TEXT;
BEGIN
    IF p_user_id IS NULL OR p_processor_permission IS NULL
       OR p_processor_permission NOT IN ('google_gemini', 'openai') THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;

    -- Preserve ordinary required-consent and account eligibility for every scan.
    PERFORM internal.require_current_ai_consent(p_user_id);
    IF p_processor_permission = 'google_gemini' THEN
        RETURN;
    END IF;

    SELECT events.event_kind INTO stream_head_event_kind
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id AND events.provider = 'openai'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    -- Absence is beta eligibility, never a grant. An all-version withdrawal
    -- still denies, including one made before the current disclosure version.
    IF stream_head_event_kind = 'revoked' THEN
        RAISE EXCEPTION 'ai_openai_consent_required' USING ERRCODE = 'P0001';
    END IF;
END;
$function$;
REVOKE ALL ON FUNCTION internal.require_identification_processor_consent(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION internal.require_identification_processor_consent(UUID, TEXT) IS
    'Beta identification policy: ordinary required consent remains required; OpenAI needs no new opt-in but an explicit all-version withdrawal denies. Does not select providers or write consent evidence. The strict receipt validator remains unchanged.';

UPDATE internal.identification_provider_bindings
SET provider = 'openai',
    binding = 'openai_photo_v1',
    processor_permission = 'openai',
    provider_model = 'gpt-6-sol',
    minimum_identification_protocol = 4
WHERE operation = 'scan_identification'
  AND input_profile = 'multimodal_photo_v1';

COMMENT ON COLUMN internal.identification_provider_bindings.provider_model IS
    'Reviewed execution model per complete-input profile. Photos use gpt-6-sol; other profiles retain Gemini with NULL here. model remains the unchanged quota-policy lookup key. Existing attempts keep their immutable provider snapshot.';

RESET lock_timeout;
RESET statement_timeout;
