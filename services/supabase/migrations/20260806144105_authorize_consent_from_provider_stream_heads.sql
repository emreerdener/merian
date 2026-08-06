-- Consent authority belongs to the single account/provider stream head, not
-- to the newest event within a selected disclosure version. Revocations are
-- deliberately accepted and rebased across disclosure versions by the causal
-- append RPC, so every authorization consumer must inspect that all-version
-- head before considering rollout compatibility for a grant.

SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION internal.require_current_ai_consent(
    p_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    stream_head_event_kind TEXT;
    stream_head_disclosure_version TEXT;
    enforcement_mode TEXT;
    has_current_adult_receipt BOOLEAN;
    has_current_terms_receipt BOOLEAN;
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT events.event_kind, events.disclosure_version
    INTO stream_head_event_kind, stream_head_disclosure_version
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id
      AND events.provider = 'google_gemini'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    -- A missing event, a revocation from any disclosure version, or any future
    -- non-grant event closes the provider gate before compatibility is checked.
    IF stream_head_event_kind IS DISTINCT FROM 'granted' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Rollout compatibility is relevant only after the provider-wide head has
    -- been proven to be a grant. A revocation must not depend on configuration
    -- lookup health or on any disclosure-version branch.
    SELECT config.enforcement_mode
    INTO STRICT enforcement_mode
    FROM internal.ai_consent_rollout_config AS config
    WHERE config.config_key = 'current';

    SELECT EXISTS (
        SELECT 1
        FROM public.user_adult_eligibility_receipts AS receipts
        WHERE receipts.user_id = p_user_id
          AND receipts.policy_version = '2026-08-03'
    ), EXISTS (
        SELECT 1
        FROM public.user_terms_acceptance_receipts AS receipts
        WHERE receipts.user_id = p_user_id
          AND receipts.terms_version = '2026-08-03'
    )
    INTO has_current_adult_receipt, has_current_terms_receipt;

    IF stream_head_disclosure_version = '2026-08-04.1' THEN
        IF has_current_adult_receipt AND has_current_terms_receipt THEN
            RETURN;
        END IF;
    ELSIF stream_head_disclosure_version = '2026-08-03.1' THEN
        IF enforcement_mode <> 'strict_2026_08_04'
           AND has_current_adult_receipt
           AND has_current_terms_receipt THEN
            RETURN;
        END IF;
    ELSIF stream_head_disclosure_version = '2026-08-03' THEN
        IF enforcement_mode = 'legacy_compatible'
           AND EXISTS (
               SELECT 1
               FROM public.user_terms_acceptance_receipts AS receipts
               WHERE receipts.user_id = p_user_id
                 AND receipts.terms_version = '2026-08-02'
           ) THEN
            RETURN;
        END IF;
    END IF;

    -- Unknown/future disclosure versions fail closed until their complete
    -- evidence bundle and rollout policy are reviewed here.
    RAISE EXCEPTION 'ai_consent_required'
        USING ERRCODE = 'P0001';
END;
$function$;

REVOKE ALL ON FUNCTION internal.require_current_ai_consent(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION internal.require_current_ai_consent(UUID) IS
    'Fails closed unless the all-version Gemini provider stream head is a grant whose exact disclosure and receipt bundle is allowed by the owner-controlled rollout mode.';

RESET statement_timeout;
