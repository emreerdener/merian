\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    quota_overload_count INTEGER;
    protected_overload_count INTEGER;
BEGIN
    IF NOT (
        SELECT tables.relrowsecurity
        FROM pg_catalog.pg_class AS tables
        WHERE tables.oid =
            'public.user_terms_acceptance_receipts'::pg_catalog.REGCLASS
    ) OR NOT (
        SELECT tables.relrowsecurity
        FROM pg_catalog.pg_class AS tables
        WHERE tables.oid =
            'public.user_ai_consent_events'::pg_catalog.REGCLASS
    ) OR NOT (
        SELECT tables.relrowsecurity
        FROM pg_catalog.pg_class AS tables
        WHERE tables.oid =
            'public.user_adult_eligibility_receipts'::pg_catalog.REGCLASS
    ) OR NOT (
        SELECT tables.relrowsecurity
        FROM pg_catalog.pg_class AS tables
        WHERE tables.oid =
            'public.user_analytics_consent_events'::pg_catalog.REGCLASS
    ) THEN
        RAISE EXCEPTION 'a legal-consent table is missing RLS';
    END IF;

    IF pg_catalog.TO_REGCLASS(
        'public.user_ai_consent_stream_head_idx'
    ) IS NULL OR pg_catalog.TO_REGCLASS(
        'public.user_analytics_consent_stream_head_idx'
    ) IS NULL OR pg_catalog.TO_REGCLASS(
        'public.user_ai_consent_causal_parent_idx'
    ) IS NULL OR pg_catalog.TO_REGCLASS(
        'public.user_analytics_consent_causal_parent_idx'
    ) IS NULL THEN
        RAISE EXCEPTION 'causal consent indexes are incomplete';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.user_terms_acceptance_receipts',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.user_ai_consent_events',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.user_adult_eligibility_receipts',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.user_analytics_consent_events',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_terms_acceptance_receipts',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_ai_consent_events',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_adult_eligibility_receipts',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_analytics_consent_events',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.user_terms_acceptance_receipts',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.user_ai_consent_events',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.user_adult_eligibility_receipts',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.user_analytics_consent_events',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'legal-consent read ACLs are unsafe';
    END IF;

    IF NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_terms_acceptance_receipts',
        'id',
        'INSERT'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_ai_consent_events',
        'id',
        'INSERT'
    ) OR NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_adult_eligibility_receipts',
        'id',
        'INSERT'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_analytics_consent_events',
        'id',
        'INSERT'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_terms_acceptance_receipts',
        'recorded_at',
        'INSERT'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_ai_consent_events',
        'recorded_at',
        'INSERT'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_adult_eligibility_receipts',
        'recorded_at',
        'INSERT'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_analytics_consent_events',
        'recorded_at',
        'INSERT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_terms_acceptance_receipts',
        'UPDATE, DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_ai_consent_events',
        'UPDATE, DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_adult_eligibility_receipts',
        'UPDATE, DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.user_analytics_consent_events',
        'UPDATE, DELETE'
    ) THEN
        RAISE EXCEPTION 'legal-consent append-only ACLs are unsafe';
    END IF;

    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.append_user_ai_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.append_user_analytics_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.append_user_ai_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.append_user_ai_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.append_user_analytics_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.append_user_analytics_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'causal consent RPC ACLs are unsafe';
    END IF;

    IF pg_catalog.HAS_SEQUENCE_PRIVILEGE(
        'authenticated',
        'public.user_ai_consent_revision_seq',
        'USAGE, SELECT, UPDATE'
    ) OR pg_catalog.HAS_SEQUENCE_PRIVILEGE(
        'authenticated',
        'public.user_analytics_consent_revision_seq',
        'USAGE, SELECT, UPDATE'
    ) THEN
        RAISE EXCEPTION 'authenticated can choose a consent revision';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        WHERE pg_catalog.HAS_FUNCTION_PRIVILEGE(
            api_role.role_name,
            'internal.require_current_ai_consent(uuid)',
            'EXECUTE'
        )
    ) THEN
        RAISE EXCEPTION 'an API role can execute the internal consent gate';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        WHERE pg_catalog.HAS_TABLE_PRIVILEGE(
            api_role.role_name,
            'internal.ai_consent_rollout_config',
            'SELECT, INSERT, UPDATE, DELETE'
        )
    ) THEN
        RAISE EXCEPTION 'an API role can mutate the consent rollout mode';
    END IF;

    SELECT pg_catalog.COUNT(*),
           pg_catalog.COUNT(*) FILTER (
               WHERE pg_catalog.STRPOS(
                   pg_catalog.PG_GET_FUNCTIONDEF(routines.oid),
                   'PERFORM internal.require_current_ai_consent(p_user_id);'
               ) > 0
           )
    INTO STRICT quota_overload_count, protected_overload_count
    FROM pg_catalog.pg_proc AS routines
    JOIN pg_catalog.pg_namespace AS namespaces
      ON namespaces.oid = routines.pronamespace
    WHERE namespaces.nspname = 'public'
      AND routines.proname = 'reserve_ai_quota';

    IF quota_overload_count <> 2
       OR protected_overload_count <> quota_overload_count THEN
        RAISE EXCEPTION 'a reserve_ai_quota overload lacks the consent gate';
    END IF;

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM internal.ghost_profile_merge_reference_policies AS policies
        WHERE policies.source_schema = 'public'
          AND policies.source_table IN (
              'user_terms_acceptance_receipts',
              'user_ai_consent_events',
              'user_adult_eligibility_receipts',
              'user_analytics_consent_events'
          )
          AND policies.source_column = 'user_id'
          AND policies.strategy = 'reparent'
    ) <> 4 THEN
        RAISE EXCEPTION 'legal evidence is missing a merge policy';
    END IF;
END;
$test$;

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-00000000e101',
        'authenticated',
        'authenticated',
        'legal-consent-owner@example.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}',
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-00000000e102',
        'authenticated',
        'authenticated',
        'legal-consent-other@example.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}',
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-4000-8000-00000000e103',
        'authenticated',
        'authenticated',
        'legal-consent-upgrade@example.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}',
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    );

INSERT INTO public.users (
    id,
    email,
    public_username,
    public_author_name,
    public_identity_source,
    subscription_tier,
    created_at
)
VALUES
    (
        '00000000-0000-4000-8000-00000000e101',
        'legal-consent-owner@example.invalid',
        'legal_consent_owner',
        'Legal Consent Owner',
        'alias',
        'free',
        pg_catalog.NOW()
    ),
    (
        '00000000-0000-4000-8000-00000000e102',
        'legal-consent-other@example.invalid',
        'legal_consent_other',
        'Legal Consent Other',
        'alias',
        'free',
        pg_catalog.NOW()
    ),
    (
        '00000000-0000-4000-8000-00000000e103',
        'legal-consent-upgrade@example.invalid',
        'legal_consent_upgrade',
        'Legal Consent Upgrade',
        'alias',
        'free',
        pg_catalog.NOW()
    )
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source,
    subscription_tier = EXCLUDED.subscription_tier,
    created_at = EXCLUDED.created_at;

DO $test$
BEGIN
    BEGIN
        PERFORM internal.require_current_ai_consent(
            '00000000-0000-4000-8000-00000000e101'
        );
        RAISE EXCEPTION 'missing legal evidence passed the consent gate';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN
                RAISE;
            END IF;
    END;
END;
$test$;

INSERT INTO public.user_terms_acceptance_receipts (
    id,
    user_id,
    terms_version,
    accepted_at,
    acceptance_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000e121',
    '00000000-0000-4000-8000-00000000e102',
    '2026-08-02',
    pg_catalog.NOW(),
    'Legacy TestFlight Terms acceptance.',
    'ios',
    '1.0.3',
    '274'
);

INSERT INTO public.user_ai_consent_events (
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
)
VALUES (
    '00000000-0000-4000-8000-00000000e122',
    '00000000-0000-4000-8000-00000000e102',
    'google_gemini',
    '2026-08-03',
    'granted',
    pg_catalog.NOW(),
    'Legacy TestFlight Google Gemini disclosure.',
    'Legacy TestFlight Google Gemini grant.',
    'ios',
    '1.0.3',
    '274'
);

SELECT internal.require_current_ai_consent(
    '00000000-0000-4000-8000-00000000e102'
);

INSERT INTO public.user_ai_consent_events (
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
)
VALUES (
    '00000000-0000-4000-8000-00000000e123',
    '00000000-0000-4000-8000-00000000e102',
    'google_gemini',
    '2026-08-04.1',
    'revoked',
    pg_catalog.NOW(),
    'Current disclosure supersedes legacy evidence.',
    'Current permission withdrawn.',
    'ios',
    '1.0.3',
    '275'
);

DO $test$
BEGIN
    BEGIN
        PERFORM internal.require_current_ai_consent(
            '00000000-0000-4000-8000-00000000e102'
        );
        RAISE EXCEPTION 'current revocation fell back to legacy consent';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN
                RAISE;
            END IF;
    END;
END;
$test$;

SET LOCAL ROLE authenticated;
SELECT pg_catalog.SET_CONFIG(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000e101","role":"authenticated"}',
    TRUE
);

INSERT INTO public.user_adult_eligibility_receipts (
    id,
    user_id,
    policy_version,
    confirmed_at,
    confirmation_method,
    confirmation_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000e110',
    '00000000-0000-4000-8000-00000000e101',
    '2026-08-03',
    pg_catalog.NOW(),
    'self_attestation',
    'I confirm I am 18 or older.',
    'ios',
    '1.0.3',
    '275'
);

INSERT INTO public.user_terms_acceptance_receipts (
    id,
    user_id,
    terms_version,
    accepted_at,
    acceptance_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000e111',
    '00000000-0000-4000-8000-00000000e101',
    '2026-08-03',
    pg_catalog.NOW(),
    'I accept the terms and allow this data sharing.',
    'ios',
    '1.0.3',
    '275'
);

SELECT *
FROM public.append_user_ai_consent_event(
    '00000000-0000-4000-8000-00000000e112',
    '2026-08-03.1',
    'granted',
    pg_catalog.NOW(),
    'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
    'I accept the terms and allow this data sharing.',
    'ios',
    '1.0.3',
    '275',
    NULL
);

SELECT *
FROM public.append_user_analytics_consent_event(
    '00000000-0000-4000-8000-00000000e115',
    '2026-08-04',
    'granted',
    pg_catalog.NOW(),
    'Share usage and diagnostics to help improve Naturebook.',
    'Share usage and diagnostics to help improve Naturebook.',
    'ios',
    '1.0.3',
    '275',
    NULL
);

DO $test$
BEGIN
    IF (
        SELECT pg_catalog.COUNT(*)
        FROM public.user_terms_acceptance_receipts
    ) <> 1 OR (
        SELECT pg_catalog.COUNT(*)
        FROM public.user_ai_consent_events
    ) <> 1 OR (
        SELECT pg_catalog.COUNT(*)
        FROM public.user_adult_eligibility_receipts
    ) <> 1 OR (
        SELECT pg_catalog.COUNT(*)
        FROM public.user_analytics_consent_events
    ) <> 1 THEN
        RAISE EXCEPTION 'owner cannot read its appended legal evidence';
    END IF;

    BEGIN
        INSERT INTO public.user_terms_acceptance_receipts (
            id,
            user_id,
            terms_version,
            accepted_at,
            acceptance_text,
            platform,
            app_version,
            app_build
        )
        VALUES (
            '00000000-0000-4000-8000-00000000e119',
            '00000000-0000-4000-8000-00000000e102',
            '2026-08-03',
            pg_catalog.NOW(),
            'Cross-owner attempt',
            'ios',
            '1.0.3',
            '275'
        );
        RAISE EXCEPTION 'cross-owner Terms receipt was accepted';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        INSERT INTO public.user_adult_eligibility_receipts (
            id,
            user_id,
            policy_version,
            confirmed_at,
            confirmation_method,
            confirmation_text,
            platform,
            app_version,
            app_build
        )
        VALUES (
            '00000000-0000-4000-8000-00000000e117',
            '00000000-0000-4000-8000-00000000e102',
            '2026-08-03',
            pg_catalog.NOW(),
            'self_attestation',
            'Cross-owner attempt',
            'ios',
            '1.0.3',
            '275'
        );
        RAISE EXCEPTION 'cross-owner adult receipt was accepted';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        UPDATE public.user_ai_consent_events
        SET event_kind = 'revoked';
        RAISE EXCEPTION 'authenticated updated immutable AI evidence';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        UPDATE public.user_analytics_consent_events
        SET event_kind = 'revoked';
        RAISE EXCEPTION 'authenticated updated immutable analytics evidence';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        DELETE FROM public.user_terms_acceptance_receipts;
        RAISE EXCEPTION 'authenticated deleted immutable Terms evidence';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        DELETE FROM public.user_adult_eligibility_receipts;
        RAISE EXCEPTION 'authenticated deleted immutable adult evidence';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        INSERT INTO public.user_ai_consent_events (
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
            recorded_at
        )
        VALUES (
            '00000000-0000-4000-8000-00000000e118',
            '00000000-0000-4000-8000-00000000e101',
            'google_gemini',
            '2026-08-04.1',
            'granted',
            pg_catalog.NOW(),
            'Spoofed timestamp attempt',
            'Spoofed timestamp attempt',
            'ios',
            '1.0.3',
            '275',
            pg_catalog.NOW() + INTERVAL '1 day'
        );
        RAISE EXCEPTION 'authenticated chose the server ordering timestamp';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;

    BEGIN
        INSERT INTO public.user_analytics_consent_events (
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
            recorded_at
        )
        VALUES (
            '00000000-0000-4000-8000-00000000e116',
            '00000000-0000-4000-8000-00000000e101',
            'posthog',
            '2026-08-04',
            'granted',
            pg_catalog.NOW(),
            'Spoofed timestamp attempt',
            'Spoofed timestamp attempt',
            'ios',
            '1.0.3',
            '275',
            pg_catalog.NOW() + INTERVAL '1 day'
        );
        RAISE EXCEPTION 'authenticated chose analytics server timestamp';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
END;
$test$;

RESET ROLE;

SELECT internal.require_current_ai_consent(
    '00000000-0000-4000-8000-00000000e101'
);

UPDATE internal.ai_consent_rollout_config
SET enforcement_mode = 'strict_2026_08_04',
    changed_at = pg_catalog.NOW()
WHERE config_key = 'current';

DO $test$
BEGIN
    BEGIN
        PERFORM internal.require_current_ai_consent(
            '00000000-0000-4000-8000-00000000e101'
        );
        RAISE EXCEPTION 'legacy consent passed after strict cutover';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN
                RAISE;
            END IF;
    END;
END;
$test$;

SET LOCAL ROLE authenticated;
SELECT *
FROM public.append_user_ai_consent_event(
    '00000000-0000-4000-8000-00000000e113',
    '2026-08-04.1',
    'revoked',
    pg_catalog.NOW(),
    'Naturebook sends observation data to Google Gemini for AI-powered identification.',
    'I withdraw permission for future observations.',
    'ios',
    '1.0.3',
    '275',
    '00000000-0000-4000-8000-00000000e112'
);
RESET ROLE;

DO $test$
BEGIN
    BEGIN
        PERFORM internal.require_current_ai_consent(
            '00000000-0000-4000-8000-00000000e101'
        );
        RAISE EXCEPTION 'a latest revocation passed the consent gate';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN
                RAISE;
            END IF;
    END;
END;
$test$;

SET LOCAL ROLE authenticated;
SELECT *
FROM public.append_user_ai_consent_event(
    '00000000-0000-4000-8000-00000000e114',
    '2026-08-04.1',
    'granted',
    pg_catalog.NOW(),
    'Naturebook sends observation data to Google Gemini for AI-powered identification.',
    'I accept the terms and allow this data sharing.',
    'ios',
    '1.0.3',
    '275',
    '00000000-0000-4000-8000-00000000e113'
);
RESET ROLE;

SELECT internal.require_current_ai_consent(
    '00000000-0000-4000-8000-00000000e101'
);

SET LOCAL ROLE authenticated;
SELECT *
FROM public.append_user_analytics_consent_event(
    '00000000-0000-4000-8000-00000000e118',
    '2026-08-04',
    'revoked',
    pg_catalog.NOW(),
    'Share usage and diagnostics to help improve Naturebook.',
    'I withdraw permission for PostHog to process future app usage and diagnostics.',
    'ios',
    '1.0.3',
    '275',
    '00000000-0000-4000-8000-00000000e115'
);
RESET ROLE;

DO $test$
DECLARE
    latest_analytics_event TEXT;
BEGIN
    SELECT events.event_kind
    INTO STRICT latest_analytics_event
    FROM public.user_analytics_consent_events AS events
    WHERE events.user_id = '00000000-0000-4000-8000-00000000e101'
      AND events.provider = 'posthog'
      AND events.disclosure_version = '2026-08-04'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    IF latest_analytics_event <> 'revoked' THEN
        RAISE EXCEPTION 'latest account-wide analytics withdrawal did not win';
    END IF;
END;
$test$;

-- Prove both conflict directions. A stale explicit withdrawal must rebase and
-- remain idempotent, while a stale grant from the superseded head must be
-- rejected even when it uploads after the withdrawal.
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
    append_accepted BOOLEAN;
    accepted_parent_id UUID;
    authoritative_event_id UUID;
BEGIN
    SELECT result.accepted
    INTO STRICT append_accepted
    FROM public.append_user_ai_consent_event(
        '00000000-0000-4000-8000-00000000e128',
        '2026-08-04.1',
        'granted',
        '2026-08-05T12:00:00Z'::TIMESTAMPTZ,
        'Naturebook sends observation data to Google Gemini for AI-powered identification.',
        'Another device confirms permission.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e114'
    ) AS result;

    IF append_accepted IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'newer AI grant setup was not accepted';
    END IF;

    SELECT result.accepted, result.accepted_parent_id
    INTO STRICT append_accepted, accepted_parent_id
    FROM public.append_user_ai_consent_event(
        '00000000-0000-4000-8000-00000000e131',
        '2026-08-04.1',
        'revoked',
        '2026-08-05T11:00:00Z'::TIMESTAMPTZ,
        'Naturebook sends observation data to Google Gemini for AI-powered identification.',
        'Device A queued an offline withdrawal.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e114'
    ) AS result;

    IF append_accepted IS DISTINCT FROM TRUE
       OR accepted_parent_id IS DISTINCT FROM
            '00000000-0000-4000-8000-00000000e128'::UUID THEN
        RAISE EXCEPTION 'stale offline AI revocation did not rebase safely';
    END IF;

    SELECT result.accepted, result.authoritative_event_id
    INTO STRICT append_accepted, authoritative_event_id
    FROM public.append_user_ai_consent_event(
        '00000000-0000-4000-8000-00000000e130',
        '2026-08-04.1',
        'granted',
        '2026-08-05T10:00:00Z'::TIMESTAMPTZ,
        'Naturebook sends observation data to Google Gemini for AI-powered identification.',
        'Device A queued an offline grant.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e128'
    ) AS result;

    IF append_accepted IS DISTINCT FROM FALSE
       OR authoritative_event_id IS DISTINCT FROM
            '00000000-0000-4000-8000-00000000e131'::UUID THEN
        RAISE EXCEPTION 'stale offline AI grant superseded a cross-device revocation';
    END IF;

    SELECT result.accepted
    INTO STRICT append_accepted
    FROM public.append_user_analytics_consent_event(
        '00000000-0000-4000-8000-00000000e134',
        '2026-08-04',
        'granted',
        '2026-08-05T12:00:00Z'::TIMESTAMPTZ,
        'Share usage and diagnostics to help improve Naturebook.',
        'Another device enables analytics.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e118'
    ) AS result;

    IF append_accepted IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'newer analytics grant setup was not accepted';
    END IF;

    SELECT result.accepted, result.accepted_parent_id
    INTO STRICT append_accepted, accepted_parent_id
    FROM public.append_user_analytics_consent_event(
        '00000000-0000-4000-8000-00000000e133',
        '2026-08-04',
        'revoked',
        '2026-08-05T11:00:00Z'::TIMESTAMPTZ,
        'Share usage and diagnostics to help improve Naturebook.',
        'Device A queued an offline analytics withdrawal.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e118'
    ) AS result;

    IF append_accepted IS DISTINCT FROM TRUE
       OR accepted_parent_id IS DISTINCT FROM
            '00000000-0000-4000-8000-00000000e134'::UUID THEN
        RAISE EXCEPTION 'stale offline analytics revocation did not rebase safely';
    END IF;

    SELECT result.accepted, result.authoritative_event_id
    INTO STRICT append_accepted, authoritative_event_id
    FROM public.append_user_analytics_consent_event(
        '00000000-0000-4000-8000-00000000e132',
        '2026-08-04',
        'granted',
        '2026-08-05T10:00:00Z'::TIMESTAMPTZ,
        'Share usage and diagnostics to help improve Naturebook.',
        'Device A queued an offline analytics grant.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e134'
    ) AS result;

    IF append_accepted IS DISTINCT FROM FALSE
       OR authoritative_event_id IS DISTINCT FROM
            '00000000-0000-4000-8000-00000000e133'::UUID THEN
        RAISE EXCEPTION 'stale offline analytics grant superseded a cross-device revocation';
    END IF;

    -- A lost response may retry with the originally observed stale parent.
    -- The immutable revocation ID remains idempotent and returns the accepted
    -- server predecessor rather than creating another row.
    SELECT result.accepted, result.accepted_parent_id
    INTO STRICT append_accepted, accepted_parent_id
    FROM public.append_user_ai_consent_event(
        '00000000-0000-4000-8000-00000000e131',
        '2026-08-04.1',
        'revoked',
        '2026-08-05T11:00:00Z'::TIMESTAMPTZ,
        'Naturebook sends observation data to Google Gemini for AI-powered identification.',
        'Device A queued an offline withdrawal.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e114'
    ) AS result;

    IF append_accepted IS DISTINCT FROM TRUE
       OR accepted_parent_id IS DISTINCT FROM
            '00000000-0000-4000-8000-00000000e128'::UUID THEN
        RAISE EXCEPTION 'rebased AI revocation retry was not idempotent';
    END IF;

    SELECT result.accepted, result.accepted_parent_id
    INTO STRICT append_accepted, accepted_parent_id
    FROM public.append_user_analytics_consent_event(
        '00000000-0000-4000-8000-00000000e133',
        '2026-08-04',
        'revoked',
        '2026-08-05T11:00:00Z'::TIMESTAMPTZ,
        'Share usage and diagnostics to help improve Naturebook.',
        'Device A queued an offline analytics withdrawal.',
        'ios',
        '1.0.3',
        '275',
        '00000000-0000-4000-8000-00000000e118'
    ) AS result;

    IF append_accepted IS DISTINCT FROM TRUE
       OR accepted_parent_id IS DISTINCT FROM
            '00000000-0000-4000-8000-00000000e134'::UUID THEN
        RAISE EXCEPTION 'rebased analytics revocation retry was not idempotent';
    END IF;
END;
$test$;
RESET ROLE;

DO $test$
DECLARE
    latest_ai_event TEXT;
    latest_analytics_event TEXT;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.user_ai_consent_events
        WHERE id = '00000000-0000-4000-8000-00000000e130'
    ) OR EXISTS (
        SELECT 1
        FROM public.user_analytics_consent_events
        WHERE id = '00000000-0000-4000-8000-00000000e132'
    ) THEN
        RAISE EXCEPTION 'a stale causal branch was persisted';
    END IF;

    IF (
        SELECT events.causal_parent_id
        FROM public.user_ai_consent_events AS events
        WHERE events.id = '00000000-0000-4000-8000-00000000e131'
    ) IS DISTINCT FROM '00000000-0000-4000-8000-00000000e128'::UUID
       OR (
        SELECT events.causal_parent_id
        FROM public.user_analytics_consent_events AS events
        WHERE events.id = '00000000-0000-4000-8000-00000000e133'
    ) IS DISTINCT FROM '00000000-0000-4000-8000-00000000e134'::UUID THEN
        RAISE EXCEPTION 'a stale revocation was not linked to its accepted head';
    END IF;

    SELECT events.event_kind
    INTO STRICT latest_ai_event
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = '00000000-0000-4000-8000-00000000e101'
      AND events.provider = 'google_gemini'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    SELECT events.event_kind
    INTO STRICT latest_analytics_event
    FROM public.user_analytics_consent_events AS events
    WHERE events.user_id = '00000000-0000-4000-8000-00000000e101'
      AND events.provider = 'posthog'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    IF latest_ai_event <> 'revoked'
       OR latest_analytics_event <> 'revoked' THEN
        RAISE EXCEPTION 'cross-device revocations are not authoritative';
    END IF;

    BEGIN
        PERFORM internal.require_current_ai_consent(
            '00000000-0000-4000-8000-00000000e101'
        );
        RAISE EXCEPTION 'stale offline AI grant reopened provider access';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN
                RAISE;
            END IF;
    END;
END;
$test$;

-- A queued withdrawal can survive an app upgrade with its original disclosure
-- version. It must still close the account/provider stream after a newer-
-- disclosure grant and must never be hidden by a version-filtered read.
INSERT INTO public.user_adult_eligibility_receipts (
    id,
    user_id,
    policy_version,
    confirmed_at,
    confirmation_method,
    confirmation_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000e140',
    '00000000-0000-4000-8000-00000000e103',
    '2026-08-03',
    pg_catalog.NOW(),
    'self_attestation',
    'I confirm I am 18 or older.',
    'ios',
    '1.0.3',
    '275'
);

INSERT INTO public.user_terms_acceptance_receipts (
    id,
    user_id,
    terms_version,
    accepted_at,
    acceptance_text,
    platform,
    app_version,
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000e141',
    '00000000-0000-4000-8000-00000000e103',
    '2026-08-03',
    pg_catalog.NOW(),
    'I accept the terms and allow this data sharing.',
    'ios',
    '1.0.3',
    '275'
);

SET LOCAL ROLE authenticated;
SELECT pg_catalog.SET_CONFIG(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000e103","role":"authenticated"}',
    TRUE
);

SELECT *
FROM public.append_user_ai_consent_event(
    '00000000-0000-4000-8000-00000000e142',
    '2026-08-03.1',
    'granted',
    '2026-08-05T10:00:00Z'::TIMESTAMPTZ,
    'Prior TestFlight Google Gemini disclosure.',
    'I allow Google Gemini processing.',
    'ios',
    '1.0.3',
    '274',
    NULL
);

SELECT *
FROM public.append_user_analytics_consent_event(
    '00000000-0000-4000-8000-00000000e143',
    '2026-08-03',
    'granted',
    '2026-08-05T10:00:00Z'::TIMESTAMPTZ,
    'Prior TestFlight analytics disclosure.',
    'Share usage and diagnostics to help improve Naturebook.',
    'ios',
    '1.0.3',
    '274',
    NULL
);

SELECT *
FROM public.append_user_ai_consent_event(
    '00000000-0000-4000-8000-00000000e144',
    '2026-08-04.1',
    'granted',
    '2026-08-05T12:00:00Z'::TIMESTAMPTZ,
    'Naturebook sends observation data to Google Gemini for AI-powered identification.',
    'I accept the terms and allow this data sharing.',
    'ios',
    '1.0.3',
    '275',
    '00000000-0000-4000-8000-00000000e142'
);

SELECT *
FROM public.append_user_analytics_consent_event(
    '00000000-0000-4000-8000-00000000e145',
    '2026-08-04',
    'granted',
    '2026-08-05T12:00:00Z'::TIMESTAMPTZ,
    'Share usage and diagnostics to help improve Naturebook.',
    'Share usage and diagnostics to help improve Naturebook.',
    'ios',
    '1.0.3',
    '275',
    '00000000-0000-4000-8000-00000000e143'
);

SELECT *
FROM public.append_user_ai_consent_event(
    '00000000-0000-4000-8000-00000000e146',
    '2026-08-03.1',
    'revoked',
    '2026-08-05T11:00:00Z'::TIMESTAMPTZ,
    'Prior TestFlight Google Gemini disclosure.',
    'A prior app queued this withdrawal before upgrading.',
    'ios',
    '1.0.3',
    '274',
    -- This was the head observed before the app upgrade. The RPC must accept
    -- the explicit withdrawal and rebase it over the newer current grant.
    '00000000-0000-4000-8000-00000000e142'
);

SELECT *
FROM public.append_user_analytics_consent_event(
    '00000000-0000-4000-8000-00000000e147',
    '2026-08-03',
    'revoked',
    '2026-08-05T11:00:00Z'::TIMESTAMPTZ,
    'Prior TestFlight analytics disclosure.',
    'A prior app queued this analytics withdrawal before upgrading.',
    'ios',
    '1.0.3',
    '274',
    -- Same stale-parent upgrade sequence for the analytics stream.
    '00000000-0000-4000-8000-00000000e143'
);
RESET ROLE;

DO $test$
DECLARE
    ai_head_kind TEXT;
    ai_head_version TEXT;
    ai_head_parent UUID;
    analytics_head_kind TEXT;
    analytics_head_version TEXT;
    analytics_head_parent UUID;
BEGIN
    SELECT
        events.event_kind,
        events.disclosure_version,
        events.causal_parent_id
    INTO STRICT ai_head_kind, ai_head_version, ai_head_parent
    FROM public.user_ai_consent_events AS events
    WHERE events.user_id = '00000000-0000-4000-8000-00000000e103'
      AND events.provider = 'google_gemini'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    SELECT
        events.event_kind,
        events.disclosure_version,
        events.causal_parent_id
    INTO STRICT
        analytics_head_kind,
        analytics_head_version,
        analytics_head_parent
    FROM public.user_analytics_consent_events AS events
    WHERE events.user_id = '00000000-0000-4000-8000-00000000e103'
      AND events.provider = 'posthog'
    ORDER BY events.consent_revision DESC
    LIMIT 1;

    IF ai_head_kind <> 'revoked'
       OR ai_head_version <> '2026-08-03.1'
       OR ai_head_parent <> '00000000-0000-4000-8000-00000000e144'
       OR analytics_head_kind <> 'revoked'
       OR analytics_head_version <> '2026-08-03'
       OR analytics_head_parent <> '00000000-0000-4000-8000-00000000e145' THEN
        RAISE EXCEPTION 'cross-version withdrawals were not rebased as provider stream heads';
    END IF;

    BEGIN
        PERFORM internal.require_current_ai_consent(
            '00000000-0000-4000-8000-00000000e103'
        );
        RAISE EXCEPTION 'an older-disclosure AI withdrawal was ignored';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN
                RAISE;
            END IF;
    END;
END;
$test$;

SELECT extensions.ok(
    TRUE,
    'Adult, Terms, Gemini, and analytics evidence is append-only, owner-scoped, causally ordered, merge-safe, and enforced at every provider quota boundary'
);
SELECT * FROM extensions.finish();
ROLLBACK;
