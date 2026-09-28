\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-0000-0000-00000000c001';
    target_user_id UUID := '00000000-0000-0000-0000-00000000c002';
    result RECORD;
    first_revision BIGINT;
    denied BOOLEAN;
    role_name TEXT;
    recipient TEXT;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,
            'public.append_user_openai_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)', 'EXECUTE')
            IS DISTINCT FROM (role_name = 'authenticated') THEN
            RAISE EXCEPTION 'OpenAI append ACL mismatch';
        END IF;
        IF pg_catalog.HAS_COLUMN_PRIVILEGE(role_name, 'public.user_ai_consent_events', 'provider', 'INSERT')
           OR pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name, 'internal.require_current_ai_consent(uuid,text)', 'EXECUTE') THEN
            RAISE EXCEPTION 'direct processor evidence mutation/authority exposed';
        END IF;
    END LOOP;
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
    VALUES (
        '00000000-0000-0000-0000-000000000000'::UUID,
        test_user_id,
        'authenticated',
        'authenticated',
        'openai-consent-test@example.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW() - INTERVAL '30 days',
        pg_catalog.NOW(),
        FALSE
    );

    INSERT INTO public.users (
        id,
        email,
        public_username,
        public_author_name,
        public_identity_source,
        created_at,
        subscription_tier
    )
    VALUES (
        test_user_id,
        'openai-consent-test@example.invalid',
        'openai_consent_c001',
        'AI Quota Test',
        'alias',
        NOW() - INTERVAL '30 days',
        'free'
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_username = EXCLUDED.public_username,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        created_at = EXCLUDED.created_at,
        subscription_tier = EXCLUDED.subscription_tier;

    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims',
        pg_catalog.JSON_BUILD_OBJECT('sub', test_user_id, 'role', 'authenticated')::TEXT, TRUE);
    PERFORM pg_catalog.SET_CONFIG('role', 'authenticated', TRUE);
    SELECT * INTO result FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c011', '2026-09-26', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', NULL);
    IF NOT result.accepted THEN RAISE EXCEPTION 'first OpenAI grant rejected'; END IF;
    first_revision := result.event_revision;
    SELECT * INTO result FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c011', '2026-09-26', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', NULL);
    IF NOT result.accepted OR result.event_revision <> first_revision THEN
        RAISE EXCEPTION 'OpenAI exact retry was not idempotent';
    END IF;
    PERFORM pg_catalog.SET_CONFIG('role', 'none', TRUE);
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'unexpected processor authorization: %', 'openai'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM internal.require_identification_processor_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'recipient recovery accepted invalid OpenAI evidence'; END IF;
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
        '00000000-0000-4000-8000-00000000c090',
        test_user_id,
        '2026-08-03',
        pg_catalog.NOW(),
        'self_attestation',
        'I confirm I am 18 or older',
        'ios',
        '1.0.3',
        '275'
    );

    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'OpenAI grant bypassed current Terms'; END IF;
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
        '00000000-0000-4000-8000-00000000c093',
        test_user_id,
        '2026-08-02',
        pg_catalog.NOW(),
        'I accept the terms and allow this data sharing',
        'ios',
        '1.0.3',
        '275'
    );

    UPDATE internal.ai_consent_rollout_config SET enforcement_mode = 'legacy_compatible' WHERE config_key = 'current';
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'OpenAI grant bypassed current Terms'; END IF;
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
        '00000000-0000-4000-8000-00000000c091',
        test_user_id,
        '2026-08-03',
        pg_catalog.NOW(),
        'I accept the terms and allow this data sharing',
        'ios',
        '1.0.3',
        '275'
    );

    PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    denied := FALSE;
    BEGIN
        PERFORM internal.require_identification_processor_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'OpenAI grant bypassed ordinary required consent'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'google_gemini');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'unexpected processor authorization: %', 'google_gemini'; END IF;
    PERFORM pg_catalog.SET_CONFIG('role', 'authenticated', TRUE);
    SELECT * INTO result FROM public.append_user_ai_consent_event('00000000-0000-4000-8000-00000000c012', '2026-08-04.1', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', NULL);
    IF NOT result.accepted OR result.accepted_parent_id IS NOT NULL THEN
        RAISE EXCEPTION 'Gemini grant was influenced by OpenAI history';
    END IF;
    PERFORM pg_catalog.SET_CONFIG('role', 'none', TRUE);
    PERFORM internal.require_identification_processor_consent(test_user_id, 'openai');
    PERFORM pg_catalog.SET_CONFIG('role', 'authenticated', TRUE);
    -- Equal UUID/payload is not idempotence across different processors.
    denied := FALSE;
    BEGIN
        PERFORM * FROM public.append_user_ai_consent_event('00000000-0000-4000-8000-00000000c011', '2026-09-26', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', NULL);
    EXCEPTION WHEN unique_violation THEN
        IF SQLERRM <> 'consent_event_id_conflict' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'OpenAI evidence replayed as Gemini'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM * FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c012', '2026-08-04.1', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', NULL);
    EXCEPTION WHEN unique_violation THEN
        IF SQLERRM <> 'consent_event_id_conflict' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'Gemini evidence replayed as OpenAI'; END IF;
    SELECT * INTO result FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c013', '2026-09-25', 'revoked', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', NULL);
    IF NOT result.accepted OR result.accepted_parent_id <> '00000000-0000-4000-8000-00000000c011'::UUID THEN
        RAISE EXCEPTION 'old-disclosure OpenAI withdrawal did not rebase to its own head';
    END IF;
    SELECT * INTO result FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c014', '2026-09-26', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', '00000000-0000-4000-8000-00000000c011');
    IF result.accepted OR result.authoritative_event_id <> '00000000-0000-4000-8000-00000000c013'::UUID THEN
        RAISE EXCEPTION 'stale OpenAI grant superseded withdrawal';
    END IF;
    PERFORM pg_catalog.SET_CONFIG('role', 'none', TRUE);
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'unexpected processor authorization: %', 'openai'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM internal.require_identification_processor_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_openai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'recipient recovery accepted invalid OpenAI evidence'; END IF;
    PERFORM internal.require_current_ai_consent(test_user_id, 'google_gemini');
    PERFORM pg_catalog.SET_CONFIG('role', 'authenticated', TRUE);
    SELECT * INTO result FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c015', '2026-09-26', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', '00000000-0000-4000-8000-00000000c013');
    IF NOT result.accepted THEN RAISE EXCEPTION 'fresh OpenAI approval rejected'; END IF;
    SELECT * INTO result FROM public.append_user_ai_consent_event('00000000-0000-4000-8000-00000000c016', '2026-08-04.1', 'revoked', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', NULL);
    IF NOT result.accepted OR result.accepted_parent_id <> '00000000-0000-4000-8000-00000000c012'::UUID THEN
        RAISE EXCEPTION 'Gemini withdrawal was influenced by OpenAI';
    END IF;
    PERFORM pg_catalog.SET_CONFIG('role', 'none', TRUE);
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'google_gemini');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'unexpected processor authorization: %', 'google_gemini'; END IF;
    PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    denied := FALSE;
    BEGIN
        PERFORM internal.require_identification_processor_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'OpenAI grant bypassed Gemini withdrawal'; END IF;
    FOREACH recipient IN ARRAY ARRAY[NULL, '', 'unknown', 'OpenAI'] LOOP
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, recipient);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'unexpected processor authorization: %', recipient; END IF;
    END LOOP;
    PERFORM pg_catalog.SET_CONFIG('role', 'authenticated', TRUE);
    SELECT * INTO result FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c017', '2099-01-01', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', '00000000-0000-4000-8000-00000000c015');
    PERFORM pg_catalog.SET_CONFIG('role', 'none', TRUE);
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'unexpected processor authorization: %', 'openai'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM internal.require_identification_processor_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'recipient recovery accepted invalid OpenAI evidence'; END IF;
    PERFORM pg_catalog.SET_CONFIG('role', 'authenticated', TRUE);
    SELECT * INTO result FROM public.append_user_openai_consent_event('00000000-0000-4000-8000-00000000c018', '2026-09-26', 'granted', '2026-09-26T00:00:00Z', 'Synthetic processor disclosure', 'Synthetic choice', 'ios', 'test', '1', '00000000-0000-4000-8000-00000000c017');
    PERFORM pg_catalog.SET_CONFIG('role', 'none', TRUE);
    -- Existing migration-owned reparent/cascade rules also cover OpenAI rows.
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
    VALUES (
        '00000000-0000-0000-0000-000000000000'::UUID,
        target_user_id,
        'authenticated',
        'authenticated',
        'openai-consent-target@example.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW() - INTERVAL '30 days',
        pg_catalog.NOW(),
        FALSE
    );

    INSERT INTO public.users (
        id,
        email,
        public_username,
        public_author_name,
        public_identity_source,
        created_at,
        subscription_tier
    )
    VALUES (
        target_user_id,
        'openai-consent-target@example.invalid',
        'openai_consent_c002',
        'AI Quota Test',
        'alias',
        NOW() - INTERVAL '30 days',
        'free'
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_username = EXCLUDED.public_username,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        created_at = EXCLUDED.created_at,
        subscription_tier = EXCLUDED.subscription_tier;

    -- Exercise the real orchestrator so all handler-before-reparent
    -- preconditions from account-creation triggers are included.
    UPDATE auth.users SET is_anonymous = TRUE WHERE id = test_user_id;
    PERFORM internal.perform_ghost_profile_merge(test_user_id, target_user_id);
    IF EXISTS (SELECT 1 FROM public.user_ai_consent_events WHERE user_id = test_user_id)
       OR NOT EXISTS (SELECT 1 FROM public.user_ai_consent_events
           WHERE user_id = target_user_id AND provider = 'openai'
             AND id = '00000000-0000-4000-8000-00000000c018'::UUID
             AND causal_parent_id = '00000000-0000-4000-8000-00000000c017'::UUID) THEN
        RAISE EXCEPTION 'OpenAI reparent lost ownership or causal ancestry';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.user_ai_consent_events
        WHERE user_id = target_user_id AND provider = 'google_gemini'
          AND id = '00000000-0000-4000-8000-00000000c016'::UUID
          AND event_kind = 'revoked') THEN
        RAISE EXCEPTION 'merge changed or lost Gemini evidence';
    END IF;
    PERFORM internal.require_current_ai_consent(target_user_id, 'openai');
    DELETE FROM public.users WHERE id = target_user_id;
    IF EXISTS (SELECT 1 FROM public.user_ai_consent_events WHERE user_id = target_user_id) THEN
        RAISE EXCEPTION 'account deletion retained processor consent evidence';
    END IF;
END;
$test$;
SELECT extensions.ok(TRUE, 'OpenAI consent is causal, recipient-isolated, owner-bound and lifecycle-safe');
SELECT * FROM extensions.finish();
ROLLBACK;
