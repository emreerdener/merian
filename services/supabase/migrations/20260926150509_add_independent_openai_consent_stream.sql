-- Add a separate optional OpenAI consent stream without enabling OpenAI
-- identification. Existing Gemini receipts, disclosure bundles and assignments
-- retain their meaning. UI collection remains closed pending reviewed rollout.
SET lock_timeout = '10s';
SET statement_timeout = '30s';

ALTER TABLE public.user_ai_consent_events
    DROP CONSTRAINT user_ai_consent_provider_check;
ALTER TABLE public.user_ai_consent_events
    ADD CONSTRAINT user_ai_consent_provider_check
    CHECK (provider IN ('google_gemini', 'openai'));

-- Once providers share the evidence table, UUID replay must compare recipient
-- as well as the immutable payload. This is the only Gemini append change.
CREATE OR REPLACE FUNCTION public.append_user_ai_consent_event(
    p_id UUID,
    p_disclosure_version TEXT,
    p_event_kind TEXT,
    p_occurred_at TIMESTAMPTZ,
    p_disclosure_text TEXT,
    p_action_text TEXT,
    p_platform TEXT,
    p_app_version TEXT,
    p_app_build TEXT,
    p_causal_parent_id UUID DEFAULT NULL
)
RETURNS TABLE (
    accepted BOOLEAN,
    event_revision BIGINT,
    accepted_parent_id UUID,
    authoritative_revision BIGINT,
    authoritative_event_id UUID,
    recorded_at TIMESTAMPTZ
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    caller_user_id UUID := (SELECT auth.uid());
    current_event_id UUID;
    current_revision BIGINT;
    existing_user_id UUID;
    existing_provider TEXT;
    existing_revision BIGINT;
    existing_recorded_at TIMESTAMPTZ;
    existing_disclosure_version TEXT;
    existing_event_kind TEXT;
    existing_occurred_at TIMESTAMPTZ;
    existing_disclosure_text TEXT;
    existing_action_text TEXT;
    existing_platform TEXT;
    existing_app_version TEXT;
    existing_app_build TEXT;
    existing_parent_id UUID;
    existing_event_found BOOLEAN;
BEGIN
    IF caller_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;

    -- Match the public.users row-lock order used by Ghost-profile merge before
    -- taking the provider advisory lock. This prevents a reparent operation
    -- from changing the account stream between the head read and append.
    PERFORM profiles.id
    FROM public.users AS profiles
    WHERE profiles.id = caller_user_id
    FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'consent_account_unavailable'
            USING ERRCODE = '42501';
    END IF;

    -- Both AI providers share this account-scoped lock because event UUIDs
    -- share one table. Heads and causal comparisons remain provider-specific.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:user-ai-consent:' || caller_user_id::TEXT,
            0::BIGINT
        )
    );

    SELECT
        events.user_id,
        events.provider,
        events.consent_revision,
        events.recorded_at,
        events.disclosure_version,
        events.event_kind,
        events.occurred_at,
        events.disclosure_text,
        events.action_text,
        events.platform,
        events.app_version,
        events.app_build,
        events.causal_parent_id
    INTO
        existing_user_id,
        existing_provider,
        existing_revision,
        existing_recorded_at,
        existing_disclosure_version,
        existing_event_kind,
        existing_occurred_at,
        existing_disclosure_text,
        existing_action_text,
        existing_platform,
        existing_app_version,
        existing_app_build,
        existing_parent_id
    FROM public.user_ai_consent_events AS events
    WHERE events.id = p_id;
    existing_event_found := FOUND;

    IF existing_event_found AND (
        existing_user_id IS DISTINCT FROM caller_user_id
        OR existing_provider IS DISTINCT FROM 'google_gemini'
        OR existing_disclosure_version IS DISTINCT FROM p_disclosure_version
        OR existing_event_kind IS DISTINCT FROM p_event_kind
        OR existing_occurred_at IS DISTINCT FROM p_occurred_at
        OR existing_disclosure_text IS DISTINCT FROM p_disclosure_text
        OR existing_action_text IS DISTINCT FROM p_action_text
        OR existing_platform IS DISTINCT FROM p_platform
        OR existing_app_version IS DISTINCT FROM p_app_version
        OR existing_app_build IS DISTINCT FROM p_app_build
        OR (
            existing_event_kind IS DISTINCT FROM 'revoked'
            AND existing_parent_id IS DISTINCT FROM p_causal_parent_id
        )
    ) THEN
        RAISE EXCEPTION 'consent_event_id_conflict'
            USING ERRCODE = '23505';
    END IF;

    SELECT events.id, events.consent_revision
    INTO current_event_id, current_revision
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = caller_user_id
      AND events.provider = 'google_gemini'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    IF existing_event_found THEN
        accepted := TRUE;
        event_revision := existing_revision;
        accepted_parent_id := existing_parent_id;
        authoritative_revision := COALESCE(current_revision, 0);
        authoritative_event_id := current_event_id;
        recorded_at := existing_recorded_at;
        RETURN NEXT;
        RETURN;
    END IF;

    IF p_event_kind IS DISTINCT FROM 'revoked'
       AND p_causal_parent_id IS DISTINCT FROM current_event_id THEN
        accepted := FALSE;
        event_revision := NULL;
        accepted_parent_id := NULL;
        authoritative_revision := COALESCE(current_revision, 0);
        authoritative_event_id := current_event_id;
        recorded_at := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    INSERT INTO public.user_ai_consent_events AS inserted (
        id,
        user_id,
        provider,
        disclosure_version,
        event_kind,
        occurred_at,
        disclosure_text,
        action_text,
        platform,
        app_version,
        app_build,
        causal_parent_id
    )
    VALUES (
        p_id,
        caller_user_id,
        'google_gemini',
        p_disclosure_version,
        p_event_kind,
        p_occurred_at,
        p_disclosure_text,
        p_action_text,
        p_platform,
        p_app_version,
        p_app_build,
        current_event_id
    )
    RETURNING inserted.consent_revision, inserted.recorded_at
    INTO event_revision, recorded_at;

    accepted := TRUE;
    accepted_parent_id := current_event_id;
    authoritative_revision := event_revision;
    authoritative_event_id := p_id;
    RETURN NEXT;
END;
$function$;

CREATE FUNCTION public.append_user_openai_consent_event(
    p_id UUID,
    p_disclosure_version TEXT,
    p_event_kind TEXT,
    p_occurred_at TIMESTAMPTZ,
    p_disclosure_text TEXT,
    p_action_text TEXT,
    p_platform TEXT,
    p_app_version TEXT,
    p_app_build TEXT,
    p_causal_parent_id UUID DEFAULT NULL
)
RETURNS TABLE (
    accepted BOOLEAN,
    event_revision BIGINT,
    accepted_parent_id UUID,
    authoritative_revision BIGINT,
    authoritative_event_id UUID,
    recorded_at TIMESTAMPTZ
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    caller_user_id UUID := (SELECT auth.uid());
    current_event_id UUID;
    current_revision BIGINT;
    existing_user_id UUID;
    existing_provider TEXT;
    existing_revision BIGINT;
    existing_recorded_at TIMESTAMPTZ;
    existing_disclosure_version TEXT;
    existing_event_kind TEXT;
    existing_occurred_at TIMESTAMPTZ;
    existing_disclosure_text TEXT;
    existing_action_text TEXT;
    existing_platform TEXT;
    existing_app_version TEXT;
    existing_app_build TEXT;
    existing_parent_id UUID;
    existing_event_found BOOLEAN;
BEGIN
    IF caller_user_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;

    -- Match the public.users row-lock order used by Ghost-profile merge before
    -- taking the provider advisory lock. This prevents a reparent operation
    -- from changing the account stream between the head read and append.
    PERFORM profiles.id
    FROM public.users AS profiles
    WHERE profiles.id = caller_user_id
    FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'consent_account_unavailable'
            USING ERRCODE = '42501';
    END IF;

    -- Both AI providers share this account-scoped lock because event UUIDs
    -- share one table. Heads and causal comparisons remain provider-specific.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:user-ai-consent:' || caller_user_id::TEXT,
            0::BIGINT
        )
    );

    SELECT
        events.user_id,
        events.provider,
        events.consent_revision,
        events.recorded_at,
        events.disclosure_version,
        events.event_kind,
        events.occurred_at,
        events.disclosure_text,
        events.action_text,
        events.platform,
        events.app_version,
        events.app_build,
        events.causal_parent_id
    INTO
        existing_user_id,
        existing_provider,
        existing_revision,
        existing_recorded_at,
        existing_disclosure_version,
        existing_event_kind,
        existing_occurred_at,
        existing_disclosure_text,
        existing_action_text,
        existing_platform,
        existing_app_version,
        existing_app_build,
        existing_parent_id
    FROM public.user_ai_consent_events AS events
    WHERE events.id = p_id;
    existing_event_found := FOUND;

    IF existing_event_found AND (
        existing_user_id IS DISTINCT FROM caller_user_id
        OR existing_provider IS DISTINCT FROM 'openai'
        OR existing_disclosure_version IS DISTINCT FROM p_disclosure_version
        OR existing_event_kind IS DISTINCT FROM p_event_kind
        OR existing_occurred_at IS DISTINCT FROM p_occurred_at
        OR existing_disclosure_text IS DISTINCT FROM p_disclosure_text
        OR existing_action_text IS DISTINCT FROM p_action_text
        OR existing_platform IS DISTINCT FROM p_platform
        OR existing_app_version IS DISTINCT FROM p_app_version
        OR existing_app_build IS DISTINCT FROM p_app_build
        OR (
            existing_event_kind IS DISTINCT FROM 'revoked'
            AND existing_parent_id IS DISTINCT FROM p_causal_parent_id
        )
    ) THEN
        RAISE EXCEPTION 'consent_event_id_conflict'
            USING ERRCODE = '23505';
    END IF;

    SELECT events.id, events.consent_revision
    INTO current_event_id, current_revision
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = caller_user_id
      AND events.provider = 'openai'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    IF existing_event_found THEN
        accepted := TRUE;
        event_revision := existing_revision;
        accepted_parent_id := existing_parent_id;
        authoritative_revision := COALESCE(current_revision, 0);
        authoritative_event_id := current_event_id;
        recorded_at := existing_recorded_at;
        RETURN NEXT;
        RETURN;
    END IF;

    IF p_event_kind IS DISTINCT FROM 'revoked'
       AND p_causal_parent_id IS DISTINCT FROM current_event_id THEN
        accepted := FALSE;
        event_revision := NULL;
        accepted_parent_id := NULL;
        authoritative_revision := COALESCE(current_revision, 0);
        authoritative_event_id := current_event_id;
        recorded_at := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    INSERT INTO public.user_ai_consent_events AS inserted (
        id,
        user_id,
        provider,
        disclosure_version,
        event_kind,
        occurred_at,
        disclosure_text,
        action_text,
        platform,
        app_version,
        app_build,
        causal_parent_id
    )
    VALUES (
        p_id,
        caller_user_id,
        'openai',
        p_disclosure_version,
        p_event_kind,
        p_occurred_at,
        p_disclosure_text,
        p_action_text,
        p_platform,
        p_app_version,
        p_app_build,
        current_event_id
    )
    RETURNING inserted.consent_revision, inserted.recorded_at
    INTO event_revision, recorded_at;

    accepted := TRUE;
    accepted_parent_id := current_event_id;
    authoritative_revision := event_revision;
    authoritative_event_id := p_id;
    RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION internal.require_current_ai_consent(
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
    stream_head_disclosure_version TEXT;
BEGIN
    IF p_processor_permission = 'google_gemini' THEN
        PERFORM internal.require_current_ai_consent(p_user_id);
        RETURN;
    END IF;
    IF p_user_id IS NULL OR p_processor_permission IS DISTINCT FROM 'openai' THEN
        RAISE EXCEPTION 'ai_consent_required' USING ERRCODE = 'P0001';
    END IF;

    SELECT events.event_kind, events.disclosure_version
    INTO stream_head_event_kind, stream_head_disclosure_version
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id AND events.provider = 'openai'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    -- Select the all-version recipient head first: older-version revocations
    -- and unknown future grants must close permission. Gemini rollout exceptions
    -- and Google receipts cannot authorize OpenAI.
    IF stream_head_event_kind = 'granted'
       AND stream_head_disclosure_version = '2026-09-26'
       AND EXISTS (
           SELECT 1 FROM public.user_adult_eligibility_receipts AS receipts
           WHERE receipts.user_id = p_user_id
             AND receipts.policy_version = '2026-08-03'
       )
       AND EXISTS (
           SELECT 1 FROM public.user_terms_acceptance_receipts AS receipts
           WHERE receipts.user_id = p_user_id
             AND receipts.terms_version = '2026-08-03'
       ) THEN
        RETURN;
    END IF;
    RAISE EXCEPTION 'ai_consent_required' USING ERRCODE = 'P0001';
END;
$function$;

REVOKE ALL ON FUNCTION internal.require_current_ai_consent(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION internal.require_current_ai_consent(UUID, TEXT) IS
    'Validates the named processor independently. OpenAI requires its own exact current grant, adult and Terms bundle; this helper does not qualify or select a production provider.';

REVOKE ALL ON FUNCTION public.append_user_ai_consent_event(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.append_user_ai_consent_event(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, UUID)
    TO authenticated;
REVOKE ALL ON FUNCTION public.append_user_openai_consent_event(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.append_user_openai_consent_event(UUID, TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT, TEXT, UUID)
    TO authenticated;
INSERT INTO internal.privileged_routine_grants(role_name, routine_signature, purpose)
VALUES ('authenticated', 'public.append_user_openai_consent_event(uuid,text,text,timestamp with time zone,text,text,text,text,text,uuid)',
    'Caller-owned independent OpenAI consent stream with causal grant and deny-wins revocation. Does not select an identification provider.');

NOTIFY pgrst, 'reload schema';
RESET statement_timeout;
RESET lock_timeout;
