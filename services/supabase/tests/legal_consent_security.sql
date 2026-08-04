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
    ) OR NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_ai_consent_events',
        'id',
        'INSERT'
    ) OR NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.user_adult_eligibility_receipts',
        'id',
        'INSERT'
    ) OR NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
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
    '2026-08-03.1',
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
    '00000000-0000-4000-8000-00000000e112',
    '00000000-0000-4000-8000-00000000e101',
    'google_gemini',
    '2026-08-03.1',
    'granted',
    pg_catalog.NOW(),
    'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
    'I accept the terms and allow this data sharing.',
    'ios',
    '1.0.3',
    '275'
);

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
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000e115',
    '00000000-0000-4000-8000-00000000e101',
    'posthog',
    '2026-08-03',
    'granted',
    pg_catalog.NOW(),
    'Share app usage and diagnostics with PostHog to help improve Naturebook. Optional.',
    'Share app usage and diagnostics with PostHog to help improve Naturebook. Optional.',
    'ios',
    '1.0.3',
    '275'
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
            '2026-08-03.1',
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
            '2026-08-03',
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
SET enforcement_mode = 'strict_2026_08_03',
    changed_at = pg_catalog.NOW()
WHERE config_key = 'current';

DO $test$
BEGIN
    BEGIN
        PERFORM internal.require_current_ai_consent(
            '00000000-0000-4000-8000-00000000e102'
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
    '00000000-0000-4000-8000-00000000e113',
    '00000000-0000-4000-8000-00000000e101',
    'google_gemini',
    '2026-08-03.1',
    'revoked',
    pg_catalog.NOW(),
    'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
    'I withdraw permission for future observations.',
    'ios',
    '1.0.3',
    '275'
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
    '00000000-0000-4000-8000-00000000e114',
    '00000000-0000-4000-8000-00000000e101',
    'google_gemini',
    '2026-08-03.1',
    'granted',
    pg_catalog.NOW(),
    'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
    'I accept the terms and allow this data sharing.',
    'ios',
    '1.0.3',
    '275'
);
RESET ROLE;

SELECT internal.require_current_ai_consent(
    '00000000-0000-4000-8000-00000000e101'
);

SET LOCAL ROLE authenticated;
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
    app_build
)
VALUES (
    '00000000-0000-4000-8000-00000000e118',
    '00000000-0000-4000-8000-00000000e101',
    'posthog',
    '2026-08-03',
    'revoked',
    pg_catalog.NOW(),
    'Share app usage and diagnostics with PostHog to help improve Naturebook. Optional.',
    'I withdraw permission for PostHog to process future app usage and diagnostics.',
    'ios',
    '1.0.3',
    '275'
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
      AND events.disclosure_version = '2026-08-03'
    ORDER BY events.recorded_at DESC, events.id DESC
    LIMIT 1;

    IF latest_analytics_event <> 'revoked' THEN
        RAISE EXCEPTION 'latest account-wide analytics withdrawal did not win';
    END IF;
END;
$test$;

SELECT extensions.ok(
    TRUE,
    'Adult, Terms, Gemini, and analytics evidence is append-only, owner-scoped, versioned, merge-safe, and enforced at every provider quota boundary'
);
SELECT * FROM extensions.finish();
ROLLBACK;
