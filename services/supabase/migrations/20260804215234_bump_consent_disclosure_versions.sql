-- Advance only the disclosures whose displayed text changed during internal
-- testing. Adult eligibility and Terms retain their 2026-08-03 versions.
--
-- The rollout remains additive: the newest bundle is authoritative as soon as
-- an account acts on it, while prior beta bundles remain accepted according to
-- the existing owner-controlled enforcement mode. The updated cutover script
-- advances production to strict_2026_08_04 after older builds are expired.

ALTER TABLE internal.ai_consent_rollout_config
    DROP CONSTRAINT ai_consent_rollout_config_enforcement_mode_check;

ALTER TABLE internal.ai_consent_rollout_config
    ADD CONSTRAINT ai_consent_rollout_config_enforcement_mode_check
    CHECK (enforcement_mode IN (
        'legacy_compatible',
        'strict_2026_08_03',
        'strict_2026_08_04'
    ));

COMMENT ON TABLE internal.ai_consent_rollout_config IS
    'Owner-only one-way TestFlight cutover from legacy-compatible consent through the current adult/Terms/Gemini evidence bundle.';

CREATE OR REPLACE FUNCTION internal.require_current_ai_consent(
    p_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    latest_event_kind TEXT;
    prior_event_kind TEXT;
    enforcement_mode TEXT;
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT config.enforcement_mode
    INTO STRICT enforcement_mode
    FROM internal.ai_consent_rollout_config AS config
    WHERE config.config_key = 'current';

    SELECT events.event_kind
    INTO latest_event_kind
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id
      AND events.provider = 'google_gemini'
      AND events.disclosure_version = '2026-08-04.1'
    ORDER BY events.recorded_at DESC, events.id DESC
    LIMIT 1;

    IF EXISTS (
        SELECT 1
        FROM public.user_adult_eligibility_receipts AS receipts
        WHERE receipts.user_id = p_user_id
          AND receipts.policy_version = '2026-08-03'
    ) AND EXISTS (
        SELECT 1
        FROM public.user_terms_acceptance_receipts AS receipts
        WHERE receipts.user_id = p_user_id
          AND receipts.terms_version = '2026-08-03'
    ) AND latest_event_kind = 'granted' THEN
        RETURN;
    END IF;

    -- A grant, revocation, or partial bundle for the newest disclosure is the
    -- account's authoritative decision and may never fall back to older text.
    IF latest_event_kind IS NOT NULL THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    IF enforcement_mode = 'strict_2026_08_04' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Compatibility for the immediately preceding complete beta bundle.
    SELECT events.event_kind
    INTO prior_event_kind
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id
      AND events.provider = 'google_gemini'
      AND events.disclosure_version = '2026-08-03.1'
    ORDER BY events.recorded_at DESC, events.id DESC
    LIMIT 1;

    IF EXISTS (
        SELECT 1
        FROM public.user_adult_eligibility_receipts AS receipts
        WHERE receipts.user_id = p_user_id
          AND receipts.policy_version = '2026-08-03'
    ) AND EXISTS (
        SELECT 1
        FROM public.user_terms_acceptance_receipts AS receipts
        WHERE receipts.user_id = p_user_id
          AND receipts.terms_version = '2026-08-03'
    ) AND prior_event_kind = 'granted' THEN
        RETURN;
    END IF;

    IF prior_event_kind IS NOT NULL
       OR enforcement_mode = 'strict_2026_08_03' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Temporary compatibility for the oldest bundle still present in beta.
    IF NOT EXISTS (
        SELECT 1
        FROM public.user_terms_acceptance_receipts AS receipts
        WHERE receipts.user_id = p_user_id
          AND receipts.terms_version = '2026-08-02'
    ) THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT events.event_kind
    INTO prior_event_kind
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id
      AND events.provider = 'google_gemini'
      AND events.disclosure_version = '2026-08-03'
    ORDER BY events.recorded_at DESC, events.id DESC
    LIMIT 1;

    IF prior_event_kind IS DISTINCT FROM 'granted' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION internal.require_current_ai_consent(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION internal.require_current_ai_consent(UUID) IS
    'Fails closed unless the account has the newest complete adult, Terms, and Gemini consent bundle or a bundle temporarily allowed by the owner-controlled beta rollout mode.';
