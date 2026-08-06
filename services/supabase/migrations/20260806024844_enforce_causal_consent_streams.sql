-- Replace receipt-time ordering with a causal append protocol for account-owned
-- AI and analytics consent streams. A device must name the event it last
-- observed. The database serializes each account/provider stream, accepts a
-- grant only while that parent is still current, rebases an explicit
-- revocation onto the current head, and assigns a server-only monotonic
-- revision. This prevents a delayed offline grant from superseding a
-- revocation while ensuring an offline withdrawal still fails closed.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE SEQUENCE public.user_ai_consent_revision_seq AS BIGINT;
CREATE SEQUENCE public.user_analytics_consent_revision_seq AS BIGINT;

REVOKE ALL ON SEQUENCE
    public.user_ai_consent_revision_seq,
    public.user_analytics_consent_revision_seq
FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.user_ai_consent_events
    ADD COLUMN consent_revision BIGINT,
    ADD COLUMN causal_parent_id UUID;

ALTER TABLE public.user_analytics_consent_events
    ADD COLUMN consent_revision BIGINT,
    ADD COLUMN causal_parent_id UUID;

-- Preserve the previously authoritative order while assigning revisions to
-- historical evidence. Revisions are globally unique within each provider
-- table, so anonymous evidence can still be reparented without collisions.
WITH ordered_events AS (
    SELECT
        events.id,
        pg_catalog.ROW_NUMBER() OVER (
            ORDER BY events.recorded_at, events.id
        )::BIGINT AS consent_revision,
        pg_catalog.LAG(events.id) OVER (
            PARTITION BY events.user_id, events.provider
            ORDER BY events.recorded_at, events.id
        ) AS causal_parent_id
    FROM public.user_ai_consent_events AS events
)
UPDATE public.user_ai_consent_events AS events
SET consent_revision = ordered_events.consent_revision,
    causal_parent_id = ordered_events.causal_parent_id
FROM ordered_events
WHERE ordered_events.id = events.id;

WITH ordered_events AS (
    SELECT
        events.id,
        pg_catalog.ROW_NUMBER() OVER (
            ORDER BY events.recorded_at, events.id
        )::BIGINT AS consent_revision,
        pg_catalog.LAG(events.id) OVER (
            PARTITION BY events.user_id, events.provider
            ORDER BY events.recorded_at, events.id
        ) AS causal_parent_id
    FROM public.user_analytics_consent_events AS events
)
UPDATE public.user_analytics_consent_events AS events
SET consent_revision = ordered_events.consent_revision,
    causal_parent_id = ordered_events.causal_parent_id
FROM ordered_events
WHERE ordered_events.id = events.id;

DO $sequence_heads$
DECLARE
    ai_max_revision BIGINT;
    analytics_max_revision BIGINT;
BEGIN
    SELECT pg_catalog.MAX(events.consent_revision)
    INTO ai_max_revision
    FROM public.user_ai_consent_events AS events;

    IF ai_max_revision IS NULL THEN
        PERFORM pg_catalog.SETVAL(
            'public.user_ai_consent_revision_seq'::pg_catalog.REGCLASS,
            1,
            FALSE
        );
    ELSE
        PERFORM pg_catalog.SETVAL(
            'public.user_ai_consent_revision_seq'::pg_catalog.REGCLASS,
            ai_max_revision,
            TRUE
        );
    END IF;

    SELECT pg_catalog.MAX(events.consent_revision)
    INTO analytics_max_revision
    FROM public.user_analytics_consent_events AS events;

    IF analytics_max_revision IS NULL THEN
        PERFORM pg_catalog.SETVAL(
            'public.user_analytics_consent_revision_seq'::pg_catalog.REGCLASS,
            1,
            FALSE
        );
    ELSE
        PERFORM pg_catalog.SETVAL(
            'public.user_analytics_consent_revision_seq'::pg_catalog.REGCLASS,
            analytics_max_revision,
            TRUE
        );
    END IF;
END;
$sequence_heads$;

ALTER SEQUENCE public.user_ai_consent_revision_seq
    OWNED BY public.user_ai_consent_events.consent_revision;
ALTER SEQUENCE public.user_analytics_consent_revision_seq
    OWNED BY public.user_analytics_consent_events.consent_revision;

ALTER TABLE public.user_ai_consent_events
    ALTER COLUMN consent_revision SET DEFAULT
        pg_catalog.NEXTVAL(
            'public.user_ai_consent_revision_seq'::pg_catalog.REGCLASS
        ),
    ALTER COLUMN consent_revision SET NOT NULL,
    ADD CONSTRAINT user_ai_consent_revision_unique
        UNIQUE (consent_revision),
    ADD CONSTRAINT user_ai_consent_causal_parent_fkey
        FOREIGN KEY (causal_parent_id)
        REFERENCES public.user_ai_consent_events(id)
        ON DELETE CASCADE;

ALTER TABLE public.user_analytics_consent_events
    ALTER COLUMN consent_revision SET DEFAULT
        pg_catalog.NEXTVAL(
            'public.user_analytics_consent_revision_seq'::pg_catalog.REGCLASS
        ),
    ALTER COLUMN consent_revision SET NOT NULL,
    ADD CONSTRAINT user_analytics_consent_revision_unique
        UNIQUE (consent_revision),
    ADD CONSTRAINT user_analytics_consent_causal_parent_fkey
        FOREIGN KEY (causal_parent_id)
        REFERENCES public.user_analytics_consent_events(id)
        ON DELETE CASCADE;

DROP INDEX public.user_ai_consent_current_idx;
CREATE INDEX user_ai_consent_current_idx
    ON public.user_ai_consent_events (
        user_id,
        provider,
        disclosure_version,
        consent_revision DESC,
        id DESC
    );

CREATE INDEX user_ai_consent_stream_head_idx
    ON public.user_ai_consent_events (
        user_id,
        provider,
        consent_revision DESC
    );

CREATE INDEX user_ai_consent_causal_parent_idx
    ON public.user_ai_consent_events (causal_parent_id)
    WHERE causal_parent_id IS NOT NULL;

DROP INDEX public.user_analytics_consent_current_idx;
CREATE INDEX user_analytics_consent_current_idx
    ON public.user_analytics_consent_events (
        user_id,
        provider,
        disclosure_version,
        consent_revision DESC,
        id DESC
    );

CREATE INDEX user_analytics_consent_stream_head_idx
    ON public.user_analytics_consent_events (
        user_id,
        provider,
        consent_revision DESC
    );

CREATE INDEX user_analytics_consent_causal_parent_idx
    ON public.user_analytics_consent_events (causal_parent_id)
    WHERE causal_parent_id IS NOT NULL;

-- Authenticated clients may read their own immutable history but can no longer
-- append directly. Every mutation must pass through the causal RPC below.
REVOKE INSERT ON TABLE
    public.user_ai_consent_events,
    public.user_analytics_consent_events
FROM PUBLIC, anon, authenticated, service_role;

REVOKE INSERT (
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
    app_build
) ON TABLE public.user_ai_consent_events FROM authenticated;

REVOKE INSERT (
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
    app_build
) ON TABLE public.user_analytics_consent_events FROM authenticated;

DROP POLICY "Users can append their own AI consent events"
    ON public.user_ai_consent_events;
DROP POLICY "Users can append their own analytics consent events"
    ON public.user_analytics_consent_events;

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

    -- Transaction-scoped and account-scoped: concurrent writers for this AI
    -- stream serialize for only the head comparison and immutable insert.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:user-ai-consent:' || caller_user_id::TEXT,
            0::BIGINT
        )
    );

    SELECT
        events.user_id,
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

CREATE OR REPLACE FUNCTION public.append_user_analytics_consent_event(
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

    PERFORM profiles.id
    FROM public.users AS profiles
    WHERE profiles.id = caller_user_id
    FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'consent_account_unavailable'
            USING ERRCODE = '42501';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian:user-analytics-consent:' || caller_user_id::TEXT,
            0::BIGINT
        )
    );

    SELECT
        events.user_id,
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
    FROM public.user_analytics_consent_events AS events
    WHERE events.id = p_id;
    existing_event_found := FOUND;

    IF existing_event_found AND (
        existing_user_id IS DISTINCT FROM caller_user_id
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
    FROM public.user_analytics_consent_events AS events
    WHERE events.user_id = caller_user_id
      AND events.provider = 'posthog'
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

    INSERT INTO public.user_analytics_consent_events AS inserted (
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
        'posthog',
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

REVOKE ALL ON FUNCTION public.append_user_ai_consent_event(
    UUID,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.append_user_ai_consent_event(
    UUID,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    UUID
) TO authenticated;

REVOKE ALL ON FUNCTION public.append_user_analytics_consent_event(
    UUID,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.append_user_analytics_consent_event(
    UUID,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    UUID
) TO authenticated;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'authenticated',
        'public.append_user_ai_consent_event(uuid,text,text,timestamp with time zone,text,text,text,text,text,uuid)',
        'Caller-authenticated causal append for the account Google Gemini consent stream.'
    ),
    (
        'authenticated',
        'public.append_user_analytics_consent_event(uuid,text,text,timestamp with time zone,text,text,text,text,text,uuid)',
        'Caller-authenticated causal append for the account PostHog consent stream.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

COMMENT ON TABLE public.user_ai_consent_events IS
    'Immutable grant/revocation trail for named third-party AI processing. consent_revision is server-issued; grants require the current head and revocations atomically rebase onto it.';
COMMENT ON TABLE public.user_analytics_consent_events IS
    'Immutable account-wide PostHog grants and revocations. consent_revision is server-issued; grants require the current head and revocations atomically rebase onto it.';
COMMENT ON COLUMN public.user_ai_consent_events.consent_revision IS
    'Server-issued monotonic ordering value. Clients cannot choose or insert this value.';
COMMENT ON COLUMN public.user_ai_consent_events.causal_parent_id IS
    'The accepted account/provider predecessor. It equals the observed parent for a grant; an explicit stale revocation is privacy-safely rebased to the current head.';
COMMENT ON COLUMN public.user_analytics_consent_events.consent_revision IS
    'Server-issued monotonic ordering value. Clients cannot choose or insert this value.';
COMMENT ON COLUMN public.user_analytics_consent_events.causal_parent_id IS
    'The accepted account/provider predecessor. It equals the observed parent for a grant; an explicit stale revocation is privacy-safely rebased to the current head.';
COMMENT ON FUNCTION public.append_user_ai_consent_event(
    UUID,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    UUID
) IS
    'Authenticated causal compare-and-append for the caller account Google Gemini consent stream. Stale grants return accepted=false; explicit revocations atomically rebase to the authoritative head.';
COMMENT ON FUNCTION public.append_user_analytics_consent_event(
    UUID,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    UUID
) IS
    'Authenticated causal compare-and-append for the caller account PostHog consent stream. Stale grants return accepted=false; explicit revocations atomically rebase to the authoritative head.';

UPDATE internal.ghost_profile_merge_reference_policies
SET purpose = CASE source_table
    WHEN 'user_ai_consent_events' THEN
        'Third-party AI permission history and server revisions follow the canonical permanent profile without coalescing immutable events.'
    WHEN 'user_analytics_consent_events' THEN
        'Analytics permission history and server revisions follow the canonical permanent profile without coalescing immutable events.'
    ELSE purpose
END
WHERE source_schema = 'public'
  AND source_table IN (
      'user_ai_consent_events',
      'user_analytics_consent_events'
  )
  AND source_column = 'user_id';

-- Provider authorization now follows the server-issued causal revision. Device
-- clocks and upload receipt time are retained as evidence but never authorize.
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
    ORDER BY events.consent_revision DESC
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

    IF latest_event_kind IS NOT NULL THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    IF enforcement_mode = 'strict_2026_08_04' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT events.event_kind
    INTO prior_event_kind
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id
      AND events.provider = 'google_gemini'
      AND events.disclosure_version = '2026-08-03.1'
    ORDER BY events.consent_revision DESC
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
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    IF prior_event_kind IS DISTINCT FROM 'granted' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION internal.require_current_ai_consent(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION internal.require_current_ai_consent(UUID) IS
    'Fails closed unless the account has the newest complete adult, Terms, and causally ordered Gemini consent bundle or a bundle temporarily allowed by the owner-controlled beta rollout mode.';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
