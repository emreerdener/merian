-- Keep immutable, account-owned evidence for the clickwrap Terms acceptance
-- and every Google Gemini permission change. Client-generated receipt IDs make
-- offline retries idempotent; server-recorded timestamps remain authoritative
-- when resolving the current permission state.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE TABLE public.user_terms_acceptance_receipts (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    terms_version TEXT NOT NULL,
    accepted_at TIMESTAMPTZ NOT NULL,
    acceptance_text TEXT NOT NULL,
    platform TEXT NOT NULL,
    app_version TEXT NOT NULL,
    app_build TEXT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT user_terms_receipts_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(terms_version)) BETWEEN 1 AND 80
        AND terms_version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([.][0-9]+)?$'
    ),
    CONSTRAINT user_terms_receipts_text_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(acceptance_text)) BETWEEN 1 AND 2000
    ),
    CONSTRAINT user_terms_receipts_platform_check CHECK (
        platform IN ('ios', 'web')
    ),
    CONSTRAINT user_terms_receipts_app_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_version)) BETWEEN 1 AND 64
    ),
    CONSTRAINT user_terms_receipts_app_build_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_build)) BETWEEN 1 AND 64
    )
);

CREATE INDEX user_terms_receipts_current_idx
    ON public.user_terms_acceptance_receipts (
        user_id,
        terms_version,
        recorded_at DESC,
        id DESC
    );

CREATE TABLE public.user_ai_consent_events (
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
    CONSTRAINT user_ai_consent_provider_check CHECK (
        provider IN ('google_gemini')
    ),
    CONSTRAINT user_ai_consent_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(disclosure_version)) BETWEEN 1 AND 80
        AND disclosure_version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}([.][0-9]+)?$'
    ),
    CONSTRAINT user_ai_consent_event_kind_check CHECK (
        event_kind IN ('granted', 'revoked')
    ),
    CONSTRAINT user_ai_consent_disclosure_text_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(disclosure_text)) BETWEEN 1 AND 4000
    ),
    CONSTRAINT user_ai_consent_action_text_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(action_text)) BETWEEN 1 AND 2000
    ),
    CONSTRAINT user_ai_consent_platform_check CHECK (
        platform IN ('ios', 'web')
    ),
    CONSTRAINT user_ai_consent_app_version_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_version)) BETWEEN 1 AND 64
    ),
    CONSTRAINT user_ai_consent_app_build_check CHECK (
        pg_catalog.CHAR_LENGTH(pg_catalog.BTRIM(app_build)) BETWEEN 1 AND 64
    )
);

CREATE INDEX user_ai_consent_current_idx
    ON public.user_ai_consent_events (
        user_id,
        provider,
        disclosure_version,
        recorded_at DESC,
        id DESC
    );

ALTER TABLE public.user_terms_acceptance_receipts
    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_ai_consent_events
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    public.user_terms_acceptance_receipts,
    public.user_ai_consent_events
FROM PUBLIC, anon, authenticated, service_role;

-- recorded_at is deliberately absent from the insert grants so callers cannot
-- choose the timestamp used by the backend permission gate.
GRANT SELECT ON TABLE public.user_terms_acceptance_receipts
    TO authenticated, service_role;
GRANT INSERT (
    id,
    user_id,
    terms_version,
    accepted_at,
    acceptance_text,
    platform,
    app_version,
    app_build
) ON TABLE public.user_terms_acceptance_receipts TO authenticated;

GRANT SELECT ON TABLE public.user_ai_consent_events
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
) ON TABLE public.user_ai_consent_events TO authenticated;

CREATE POLICY "Users can read their own Terms receipts"
ON public.user_terms_acceptance_receipts
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can append their own Terms receipts"
ON public.user_terms_acceptance_receipts
FOR INSERT
TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can read their own AI consent events"
ON public.user_ai_consent_events
FOR SELECT
TO authenticated
USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can append their own AI consent events"
ON public.user_ai_consent_events
FOR INSERT
TO authenticated
WITH CHECK ((SELECT auth.uid()) = user_id);

COMMENT ON TABLE public.user_terms_acceptance_receipts IS
    'Immutable account-owned clickwrap evidence. recorded_at is server-controlled; accepted_at is the device action time.';
COMMENT ON TABLE public.user_ai_consent_events IS
    'Immutable grant/revocation trail for named third-party AI processing. The latest server-recorded event determines current permission.';

-- Receipt/event IDs are globally unique and there are intentionally no
-- account-scoped unique constraints, so anonymous ownership can be reparented
-- without destroying or coalescing legal evidence.
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
        'user_terms_acceptance_receipts',
        'user_id',
        'public',
        'users',
        'id',
        'reparent',
        500,
        NULL,
        'Terms acceptance evidence follows the canonical permanent profile without coalescing immutable receipts.'
    ),
    (
        'public',
        'user_ai_consent_events',
        'user_id',
        'public',
        'users',
        'id',
        'reparent',
        500,
        NULL,
        'Third-party AI permission history follows the canonical permanent profile without coalescing immutable events.'
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

-- Current release policy. A material Terms or disclosure change must ship a
-- new version and force renewed acceptance in both Swift and this function.
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
BEGIN
    IF p_user_id IS NULL THEN
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

-- Inject the durable permission check into both established service-only quota
-- overloads. This is the common boundary immediately before every paid Gemini
-- dispatch, including scans, audio, chats, moderation, and replay workers.
DO $migration$
DECLARE
    identity_arguments TEXT;
    function_definition TEXT;
    rewritten_definition TEXT;
    old_fragment CONSTANT TEXT :=
        'PERFORM internal.require_service_role();';
    new_fragment CONSTANT TEXT :=
        'PERFORM internal.require_service_role();'
        || pg_catalog.CHR(10)
        || '    PERFORM internal.require_current_ai_consent(p_user_id);';
BEGIN
    FOREACH identity_arguments IN ARRAY ARRAY[
        'p_user_id uuid, p_operation text, p_request_id uuid, p_ip_hash text',
        'p_user_id uuid, p_operation text, p_request_id uuid, p_ip_hash text, p_original_analysis_id uuid, p_flash_fallback_eligible boolean, p_client_protocol integer, p_internal_replay boolean'
    ]
    LOOP
        SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine.oid)
        INTO STRICT function_definition
        FROM pg_catalog.pg_proc AS routine
        JOIN pg_catalog.pg_namespace AS namespace
          ON namespace.oid = routine.pronamespace
        WHERE namespace.nspname = 'public'
          AND routine.proname = 'reserve_ai_quota'
          AND pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(routine.oid) =
                identity_arguments;

        IF pg_catalog.STRPOS(function_definition, new_fragment) <> 0
           OR pg_catalog.STRPOS(function_definition, old_fragment) = 0 THEN
            RAISE EXCEPTION 'reserve_ai_quota_consent_source_drift: %',
                identity_arguments
                USING ERRCODE = '55000';
        END IF;

        rewritten_definition := pg_catalog.REPLACE(
            function_definition,
            old_fragment,
            new_fragment
        );

        IF rewritten_definition IS NOT DISTINCT FROM function_definition THEN
            RAISE EXCEPTION 'reserve_ai_quota_consent_rewrite_failed: %',
                identity_arguments
                USING ERRCODE = '55000';
        END IF;

        EXECUTE rewritten_definition;
    END LOOP;
END;
$migration$;

COMMENT ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT) IS
    'Service-only AI quota reservation. Fails closed unless current Terms acceptance and Google Gemini permission are recorded.';
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
    'Service-only AI quota reservation. Fails closed unless current Terms acceptance and Google Gemini permission are recorded.';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
