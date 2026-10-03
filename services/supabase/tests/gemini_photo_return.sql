\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-0000-0000-00000000b941';
    test_request_id UUID;
    preview RECORD; admitted RECORD;
    tier TEXT; before_counts JSONB; after_counts JSONB; denied BOOLEAN;
BEGIN
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
        'provider-admission-test@example.invalid',
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
        'provider-admission-test@example.invalid',
        'ai_quota_test_b941',
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
        '00000000-0000-4000-8000-00000000b940',
        test_user_id,
        '2026-08-03',
        pg_catalog.NOW(),
        'self_attestation',
        'I confirm I am 18 or older',
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
        '00000000-0000-4000-8000-00000000b941',
        test_user_id,
        '2026-08-03',
        pg_catalog.NOW(),
        'I accept the terms and allow this data sharing',
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
        '00000000-0000-4000-8000-00000000b942',
        test_user_id,
        'google_gemini',
        '2026-08-04.1',
        'granted',
        pg_catalog.NOW(),
        'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
        'I accept the terms and allow this data sharing',
        'ios',
        '1.0.3',
        '275'
    );

    IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_bindings
        WHERE operation='scan_identification' AND input_profile='multimodal_photo_v1')
       OR EXISTS (SELECT 1 FROM internal.identification_provider_bindings
        WHERE operation='scan_identification' AND input_profile='multimodal_photo_v1'
          AND (provider <> 'gemini' OR binding <> 'gemini_baseline_v1'
          OR processor_permission <> 'google_gemini' OR provider_model IS NOT NULL
          OR minimum_identification_protocol <> 0)) THEN
        RAISE EXCEPTION 'Gemini return did not restore exact current assignments';
    END IF;
    -- Exercise real admission for subscription, complimentary, and free fallback.
    UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',
        required_client_protocol=3 WHERE config_key='current';
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims',
        pg_catalog.JSONB_BUILD_OBJECT('role','authenticated','sub',test_user_id)::TEXT,TRUE);
    FOREACH tier IN ARRAY ARRAY['pro','complimentary','free'] LOOP
        UPDATE public.users SET subscription_tier=(CASE WHEN tier='pro' THEN 'pro' ELSE 'free' END)::public.subscription_tier_enum,
            subscription_expires_at=NULL WHERE id=test_user_id;
        IF tier='free' THEN
            INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id,state,held_at,settled_at,settlement_reason)
            SELECT test_user_id,extensions.gen_random_uuid(),'consumed',NOW(),NOW(),'completed'
            FROM pg_catalog.generate_series(1,3);
        END IF;
        test_request_id := extensions.gen_random_uuid();
        SELECT * INTO STRICT preview FROM public.get_my_identification_preflight(
            'scan_identification','multimodal_photo_v1',tier='free',test_request_id,3,5);
        IF preview.decision <> 'ready' OR preview.processor_permission <> 'google_gemini'
            OR preview.minimum_identification_protocol <> 0 THEN
            RAISE EXCEPTION 'Gemini photo preflight failed for %',tier;
        END IF;
        SELECT pg_catalog.JSONB_BUILD_ARRAY(
            (SELECT COUNT(*) FROM internal.ai_quota_reservations),
            (SELECT COALESCE(SUM(request_count),0) FROM internal.ai_quota_counters),
            (SELECT COUNT(*) FROM internal.identification_provider_attempts),
            (SELECT COUNT(*) FROM internal.complimentary_scan_usage)) INTO before_counts;
        denied := FALSE;
        BEGIN
            PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
                pg_catalog.REPEAT('b',64),test_request_id,tier='free',3,FALSE,'multimodal_photo_v1','openai',5);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_identification_preflight_changed' THEN RAISE; END IF;
            denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'stale OpenAI recipient was admitted'; END IF;
        SELECT pg_catalog.JSONB_BUILD_ARRAY(
            (SELECT COUNT(*) FROM internal.ai_quota_reservations),
            (SELECT COALESCE(SUM(request_count),0) FROM internal.ai_quota_counters),
            (SELECT COUNT(*) FROM internal.identification_provider_attempts),
            (SELECT COUNT(*) FROM internal.complimentary_scan_usage)) INTO after_counts;
        IF before_counts IS DISTINCT FROM after_counts THEN
            RAISE EXCEPTION 'recipient mismatch mutated quota';
        END IF;
        SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,tier='free',3,FALSE,'multimodal_photo_v1','google_gemini',5);
        IF admitted.provider <> 'gemini' OR admitted.binding <> 'gemini_baseline_v1'
           OR admitted.model <> (CASE WHEN tier='free' THEN 'gemini-2.5-flash' ELSE 'gemini-2.5-pro' END)
           OR admitted.effective_tier <> (CASE WHEN tier='free' THEN 'free' ELSE 'pro' END) THEN
            RAISE EXCEPTION 'Gemini photo model/tier mismatch for %',tier;
        END IF;
        IF tier='free' AND (admitted.effective_plan <> 'free' OR NOT admitted.flash_fallback_used) THEN
            RAISE EXCEPTION 'free fallback did not retain its funding identity';
        END IF;
        IF tier='complimentary' AND admitted.effective_plan <> 'pro_complimentary' THEN
            RAISE EXCEPTION 'complimentary scan did not retain its funding identity';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_attempts
            WHERE reservation_id=admitted.reservation_id AND attempt_count=admitted.attempt_count
              AND provider='gemini' AND provider_model IS NULL
              AND model=admitted.model AND accepted_identification_protocol=5) THEN
            RAISE EXCEPTION 'Gemini assignment snapshot not preserved';
        END IF;
        PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'refunded');
    END LOOP;
    IF EXISTS (SELECT 1 FROM public.user_ai_consent_events WHERE user_id=test_user_id AND provider='openai') THEN
        RAISE EXCEPTION 'Gemini return manufactured OpenAI consent';
    END IF;
END;
$test$;
SELECT extensions.pass('Gemini photo defaults, Pro/complimentary/free model policy, recipient mismatch and atomic quota');
SELECT * FROM extensions.finish();
ROLLBACK;
