-- Add immutable 18+ self-attestation evidence and optional, account-wide
-- PostHog permission history. The current AI gate is advanced to the new Terms
-- and Gemini disclosure versions and now also requires adult eligibility.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE TABLE public.user_adult_eligibility_receipts (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    policy_version TEXT NOT NULL,
    confirmed_at TIMESTAMPTZ NOT NULL,
    confirmation_method TEXT NOT NULL,
    confirmation_text TEXT NOT NULL,
    platform TEXT NOT NULL,
    app_version TEXT NOT NULL,
    app_build TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT user_adult_eligibility_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(policy_version)) BETWEEN 1 AND 80
        AND policy_version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([.][0-9]+)?$'
    ),
    CONSTRAINT user_adult_eligibility_method_check CHECK (
        confirmation_method IN ('self_attestation')
    ),
    CONSTRAINT user_adult_eligibility_text_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(confirmation_text))
            BETWEEN 1 AND 2000
    ),
    CONSTRAINT user_adult_eligibility_platform_check CHECK (
        platform IN ('ios', 'web')
    ),
    CONSTRAINT user_adult_eligibility_app_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_version)) BETWEEN 1 AND 64
    ),
    CONSTRAINT user_adult_eligibility_app_build_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_build)) BETWEEN 1 AND 64
    )
);

CREATE INDEX user_adult_eligibility_current_idx
    ON public.user_adult_eligibility_receipts (
        user_id,
        policy_version,
        recorded_at DESC,
        id DESC
    );

CREATE TABLE public.user_analytics_consent_events (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    disclosure_version TEXT NOT NULL,
    event_kind TEXT NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    disclosure_text TEXT NOT NULL,
    action_text TEXT NOT NULL,
    platform TEXT NOT NULL,
    app_version TEXT NOT NULL,
    app_build TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT user_analytics_consent_provider_check CHECK (
        provider IN ('posthog')
    ),
    CONSTRAINT user_analytics_consent_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(disclosure_version))
            BETWEEN 1 AND 80
        AND disclosure_version ~
            '^[0-9]{4}-[0-9]{2}-[0-9]{2}([.][0-9]+)?$'
    ),
    CONSTRAINT user_analytics_consent_event_kind_check CHECK (
        event_kind IN ('granted', 'revoked')
    ),
    CONSTRAINT user_analytics_consent_disclosure_text_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(disclosure_text))
            BETWEEN 1 AND 4000
    ),
    CONSTRAINT user_analytics_consent_action_text_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(action_text))
            BETWEEN 1 AND 2000
    ),
    CONSTRAINT user_analytics_consent_platform_check CHECK (
        platform IN ('ios', 'web')
    ),
    CONSTRAINT user_analytics_consent_app_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_version)) BETWEEN 1 AND 64
    ),
    CONSTRAINT user_analytics_consent_app_build_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_build)) BETWEEN 1 AND 64
    )
);

CREATE INDEX user_analytics_consent_current_idx
    ON public.user_analytics_consent_events (
        user_id,
        provider,
        disclosure_version,
        recorded_at DESC,
        id DESC
    );

ALTER TABLE public.user_adult_eligibility_receipts
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_analytics_consent_events
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    public.user_adult_eligibility_receipts,
    public.user_analytics_consent_events
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.user_adult_eligibility_receipts
    TO authenticated, service_role;
GRANT INSERT (
    id,
    user_id,
    policy_version,
    confirmed_at,
    confirmation_method,
    confirmation_text,
    platform,
    app_version,
    app_build
) ON TABLE public.user_adult_eligibility_receipts TO authenticated;

GRANT SELECT ON TABLE public.user_analytics_consent_events
    TO authenticated, service_role;
GRANT INSERT (
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
) ON TABLE public.user_analytics_consent_events TO authenticated;

CREATE POLICY "Users can read their own adult eligibility receipts"
ON public.user_adult_eligibility_receipts
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can append their own adult eligibility receipts"
ON public.user_adult_eligibility_receipts
FOR INSERT
TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can read their own analytics consent events"
ON public.user_analytics_consent_events
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can append their own analytics consent events"
ON public.user_analytics_consent_events
FOR INSERT
TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

COMMENT ON TABLE public.user_adult_eligibility_receipts IS
    'Immutable account-owned evidence of an 18+ self-attestation. Exact age and birth date are never collected.';
COMMENT ON TABLE public.user_analytics_consent_events IS
    'Immutable account-wide PostHog grants and revocations. The latest server-recorded event determines current permission.';

-- The additive rollout must coexist with the current TestFlight build until
-- its replacement is verified and the old build is expired. Compatibility
-- accepts either the prior bundle or the complete current bundle; the owner
-- cutover script permanently advances production to current-only evidence.
CREATE TABLE internal.ai_consent_rollout_config (
    config_key TEXT PRIMARY KEY DEFAULT 'current'
        CHECK (config_key = 'current'),
    enforcement_mode TEXT NOT NULL DEFAULT 'legacy_compatible'
        CHECK (enforcement_mode IN (
            'legacy_compatible',
            'strict_2026_08_03'
        )),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW()
);

INSERT INTO internal.ai_consent_rollout_config (
    config_key,
    enforcement_mode
)
VALUES ('current', 'legacy_compatible');

ALTER TABLE internal.ai_consent_rollout_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.ai_consent_rollout_config
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.ai_consent_rollout_config IS
    'Owner-only one-way TestFlight cutover from legacy-compatible to current adult/Terms/Gemini evidence.';

INSERT INTO internal.ghost_profile_merge_reference_policies (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column,
    strategy,
    execution_order,
    handler_key,
    purpose
)
VALUES
    (
        'public',
        'user_adult_eligibility_receipts',
        'user_id',
        'public',
        'users',
        'id',
        'reparent',
        500,
        NULL,
        'Adult eligibility evidence follows the canonical permanent profile without coalescing immutable receipts.'
    ),
    (
        'public',
        'user_analytics_consent_events',
        'user_id',
        'public',
        'users',
        'id',
        'reparent',
        500,
        NULL,
        'Analytics permission history follows the canonical permanent profile without coalescing immutable events.'
    )
ON CONFLICT (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column
) DO UPDATE
SET strategy = EXCLUDED.strategy,
    execution_order = EXCLUDED.execution_order,
    handler_key = EXCLUDED.handler_key,
    purpose = EXCLUDED.purpose;

-- Postgres Changes observes INSERT only for this append-only table. RLS and
-- the indexed user_id filter keep account-wide propagation owner-scoped.
DO $publication$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_publication
        WHERE pubname = 'supabase_realtime'
    ) AND NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'user_analytics_consent_events'
    ) THEN
        ALTER PUBLICATION supabase_realtime
            ADD TABLE public.user_analytics_consent_events;
    END IF;
END;
$publication$;

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
    ) AND latest_event_kind = 'granted' THEN
        RETURN;
    END IF;

    -- Once this account has acted on the current disclosure, that decision is
    -- authoritative. Never let a current revocation or incomplete current
    -- bundle fall back to a historical TestFlight grant during transition.
    IF latest_event_kind IS NOT NULL THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    IF enforcement_mode = 'strict_2026_08_03' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Temporary compatibility for only the consent bundle used by the build
    -- being expired. It is removed atomically by the owner cutover script.
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
    INTO latest_event_kind
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = p_user_id
      AND events.provider = 'google_gemini'
      AND events.disclosure_version = '2026-08-03'
    ORDER BY events.recorded_at DESC, events.id DESC
    LIMIT 1;

    IF latest_event_kind IS DISTINCT FROM 'granted' THEN
        RAISE EXCEPTION 'ai_consent_required'
            USING ERRCODE = 'P0001';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION internal.require_current_ai_consent(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT) IS
    'Service-only AI quota reservation. Fails closed unless current adult eligibility, Terms acceptance, and Google Gemini permission are recorded.';
COMMENT ON FUNCTION public.reserve_ai_quota(
    UUID,
    TEXT,
    UUID,
    TEXT,
    UUID,
    BOOLEAN,
    INTEGER,
    BOOLEAN
) IS
    'Service-only AI quota reservation. Fails closed unless current adult eligibility, Terms acceptance, and Google Gemini permission are recorded.';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
