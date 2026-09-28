\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    withdrawal_id UUID := extensions.gen_random_uuid();
    test_user_id UUID := '00000000-0000-0000-0000-00000000b941';
    test_request_id UUID;
    replay_id UUID;
    admitted RECORD; repeated RECORD; preview RECORD;
    before_counts JSONB; after_counts JSONB;
    denied BOOLEAN; protocol INTEGER; column_name TEXT; profile TEXT;
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
        WHERE operation = 'scan_identification' AND input_profile = 'multimodal_photo_v1')
       OR EXISTS (SELECT 1 FROM internal.identification_provider_bindings
        WHERE operation = 'scan_identification' AND input_profile = 'multimodal_photo_v1'
        AND (provider <> 'openai' OR binding <> 'openai_photo_v1' OR processor_permission <> 'openai'
            OR provider_model IS DISTINCT FROM 'gpt-6-sol' OR minimum_identification_protocol <> 4)) THEN
        RAISE EXCEPTION 'not every photo plan and policy selects the exact OpenAI binding';
    END IF;
    IF EXISTS (SELECT 1 FROM internal.identification_provider_bindings
        WHERE NOT (operation = 'scan_identification' AND input_profile = 'multimodal_photo_v1')
        AND (provider <> 'gemini' OR provider_model IS NOT NULL OR minimum_identification_protocol <> 0)) THEN
        RAISE EXCEPTION 'photo activation changed another input profile';
    END IF;
    UPDATE public.users SET subscription_tier = 'pro', subscription_expires_at = NULL WHERE id = test_user_id;
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'complimentary', required_client_protocol = 3 WHERE config_key = 'current';
    -- Enforced tuples cannot select audio/video or mismatch model/recipient.
    FOREACH column_name IN ARRAY ARRAY['provider_model','processor_permission','input_profile','minimum_identification_protocol'] LOOP
        denied := FALSE;
        BEGIN
            CASE column_name
                WHEN 'provider_model' THEN UPDATE internal.identification_provider_bindings SET provider_model=NULL WHERE provider='openai';
                WHEN 'processor_permission' THEN UPDATE internal.identification_provider_bindings SET processor_permission='google_gemini' WHERE provider='openai';
                WHEN 'input_profile' THEN UPDATE internal.identification_provider_bindings SET input_profile='multimodal_video_frames_v1' WHERE provider='openai';
                ELSE UPDATE internal.identification_provider_bindings SET minimum_identification_protocol=0 WHERE provider='openai';
            END CASE;
        EXCEPTION WHEN check_violation THEN denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'invalid assignment tuple accepted: %',column_name; END IF;
    END LOOP;
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims', pg_catalog.JSONB_BUILD_OBJECT('role','authenticated','sub',test_user_id)::TEXT, TRUE);
    test_request_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,test_request_id,3);
    IF preview.decision <> 'client_update_required' THEN RAISE EXCEPTION 'old preview admitted OpenAI'; END IF;
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,test_request_id,3,4);
    IF preview.decision <> 'ready' OR preview.processor_permission <> 'openai'
       OR preview.minimum_identification_protocol <> 4 OR preview.minimum_client_protocol <> 3 THEN
        RAISE EXCEPTION 'beta photo without opt-in not ready or protocols conflated';
    END IF;
    denied := FALSE;
    BEGIN
        PERFORM internal.require_current_ai_consent(test_user_id, 'openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'beta eligibility manufactured strict OpenAI consent'; END IF;
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1','openai',4);
    IF admitted.provider <> 'openai' OR admitted.model <> 'gpt-6-sol' THEN
        RAISE EXCEPTION 'beta photo without opt-in did not admit exact OpenAI model';
    END IF;
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'refunded');
    IF EXISTS (SELECT 1 FROM public.user_ai_consent_events WHERE user_id = test_user_id AND provider = 'openai') THEN
        RAISE EXCEPTION 'beta admission wrote consent evidence';
    END IF;
    -- A real withdrawal, including an older disclosure, closes beta admission.
    PERFORM pg_catalog.SET_CONFIG('role','authenticated',TRUE);
    PERFORM public.append_user_openai_consent_event(withdrawal_id,'2026-09-25','revoked',NOW(),
        'Synthetic disclosure','Synthetic withdrawal','ios','test','1',NULL);
    PERFORM pg_catalog.SET_CONFIG('role','none',TRUE);
    test_request_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,test_request_id,3,4);
    IF preview.decision <> 'permission_required' THEN RAISE EXCEPTION 'withdrawal did not close beta admission'; END IF;
    -- Missing/wrong capability, recipient drift and explicit withdrawal all roll back quota.
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT COUNT(*) FROM internal.complimentary_scan_usage)
    ) INTO before_counts;
    FOREACH protocol IN ARRAY ARRAY[NULL,3,5,4] LOOP
        denied := FALSE;
        BEGIN
            PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
                pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1','openai',protocol);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> (CASE WHEN protocol=4 THEN 'ai_openai_consent_required' ELSE 'client_update_required' END) THEN RAISE; END IF;
            denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'capability or consent denial missing'; END IF;
    END LOOP;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1','openai');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'client_update_required' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'legacy reservation ABI admitted OpenAI'; END IF;
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT COUNT(*) FROM internal.complimentary_scan_usage)
    ) INTO after_counts;
    IF before_counts IS DISTINCT FROM after_counts THEN RAISE EXCEPTION 'denial mutated quota'; END IF;
    PERFORM pg_catalog.SET_CONFIG('role','authenticated',TRUE);
    PERFORM public.append_user_openai_consent_event(extensions.gen_random_uuid(),'2026-09-26','granted',NOW(),
        'Synthetic disclosure','Synthetic choice','ios','test','1',withdrawal_id);
    PERFORM pg_catalog.SET_CONFIG('role','none',TRUE);
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,test_request_id,3,4);
    IF preview.decision <> 'ready' THEN RAISE EXCEPTION 'exact capability and consent not recognized'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1',NULL,4);
    EXCEPTION WHEN SQLSTATE '22023' THEN
        IF SQLERRM <> 'ai_quota_invalid_request' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'fresh external admission omitted recipient expectation'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1','google_gemini',4);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_identification_preflight_changed' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'recipient expectation selected a different provider'; END IF;
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1','openai',4);
    IF admitted.model <> 'gpt-6-sol' OR admitted.provider <> 'openai' THEN RAISE EXCEPTION 'RPC returned quota model as execution model'; END IF;
    IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_attempts AS saved
        WHERE saved.reservation_id=admitted.reservation_id AND saved.attempt_count=admitted.attempt_count
        AND saved.model='gemini-2.5-pro' AND saved.provider_model='gpt-6-sol'
        AND saved.accepted_client_protocol=3 AND saved.accepted_identification_protocol=4) THEN
        RAISE EXCEPTION 'assignment snapshot conflated models or capabilities';
    END IF;
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'committed');
    -- Exercise the actual worker ABI, not just the proof helper: workers have
    -- neither an original-client header nor a fresh recipient expectation.
    replay_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',replay_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,NULL,TRUE,'multimodal_photo_v1',NULL,NULL);
    IF repeated.provider <> 'openai' OR repeated.model <> 'gpt-6-sol' OR NOT EXISTS (
        SELECT 1 FROM internal.identification_provider_attempts AS saved
        WHERE saved.reservation_id=repeated.reservation_id AND saved.attempt_count=repeated.attempt_count
          AND saved.minimum_identification_protocol=4 AND saved.accepted_identification_protocol=4
    ) THEN RAISE EXCEPTION 'headerless worker lost original capability or provider model'; END IF;
    PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',extensions.gen_random_uuid(),
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,NULL,TRUE,'multimodal_photo_v1','google_gemini',NULL);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_identification_preflight_changed' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'worker bypassed an explicit recipient mismatch'; END IF;
    -- A changed binding cannot reinterpret a live/committed attempt.
    UPDATE internal.identification_provider_bindings SET provider='gemini', binding='gemini_baseline_v1',
        processor_permission='google_gemini',provider_model=NULL,minimum_identification_protocol=0 WHERE provider='openai';
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1','google_gemini',NULL);
    IF NOT repeated.is_replay OR repeated.model <> 'gpt-6-sol' OR repeated.provider <> 'openai' THEN
        RAISE EXCEPTION 'replay reinterpreted immutable execution';
    END IF;
    IF internal.require_identification_capability(test_user_id,'scan_identification',test_request_id,'multimodal_photo_v1',NULL,TRUE,4) <> 4 THEN
        RAISE EXCEPTION 'worker lost original capability';
    END IF;
    denied := FALSE;
    BEGIN PERFORM internal.require_identification_capability(test_user_id,'scan_identification',extensions.gen_random_uuid(),'multimodal_photo_v1',4,TRUE,4);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN denied := TRUE; END;
    IF NOT denied THEN RAISE EXCEPTION 'worker invented original capability'; END IF;
    -- Historical Gemini attempts carry no identification capability. A worker's
    -- own header must not upgrade the original client to V2 eligibility.
    test_request_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1','google_gemini');
    denied := FALSE;
    BEGIN PERFORM internal.require_identification_capability(test_user_id,'scan_identification',test_request_id,'multimodal_photo_v1',4,TRUE,4);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'client_update_required' THEN RAISE; END IF; denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'worker upgraded a historical Gemini attempt'; END IF;
    denied := FALSE;
    BEGIN
        UPDATE internal.identification_provider_attempts SET minimum_identification_protocol=4, accepted_identification_protocol=4
        WHERE reservation_id=repeated.reservation_id AND attempt_count=repeated.attempt_count;
    EXCEPTION WHEN check_violation THEN denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'Gemini attempt accepted OpenAI minimum capability'; END IF;
    PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');
    FOREACH profile IN ARRAY ARRAY['multimodal_text_v1','multimodal_audio_v1','multimodal_photo_audio_v1','multimodal_video_frames_v1','multimodal_video_audio_v1'] LOOP
        test_request_id := extensions.gen_random_uuid();
        SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,profile,'google_gemini',4);
        IF repeated.model <> 'gemini-2.5-pro' OR repeated.provider <> 'gemini' THEN RAISE EXCEPTION 'photo assignment affected another profile'; END IF;
        IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_attempts AS saved
            WHERE saved.reservation_id=repeated.reservation_id AND saved.attempt_count=repeated.attempt_count
              AND saved.minimum_identification_protocol=0 AND saved.accepted_identification_protocol=4) THEN
            RAISE EXCEPTION 'capable Gemini client lost independent identification capability';
        END IF;
        PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');
    END LOOP;
END;
$test$;
SELECT extensions.pass('Dormant photo model routing, independent capabilities, consent, atomic rollback and immutable replay');
SELECT * FROM extensions.finish();
ROLLBACK;
