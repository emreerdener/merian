\set ON_ERROR_STOP on
BEGIN;
-- This fixture verifies the supported Gemini/legacy routing configuration.
-- Activation defaults are asserted independently by gemini_photo_return.sql.
UPDATE internal.identification_provider_bindings
SET provider = 'gemini', binding = 'gemini_baseline_v1',
    processor_permission = 'google_gemini', provider_model = NULL,
    minimum_identification_protocol = 0, minimum_client_protocol = 0
WHERE operation = 'scan_identification' AND input_profile = 'multimodal_photo_v1';

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-0000-0000-00000000b981';
    other_user_id UUID := '00000000-0000-0000-0000-00000000b983';
    scan_id UUID := '00000000-0000-4000-8000-00000000b984';
    held_scan_id UUID := '00000000-0000-4000-8000-00000000b985';
    preview RECORD;
    admitted RECORD;
    repeated RECORD;
    role_name TEXT;
    profile TEXT;
    test_operation TEXT;
    expected TEXT;
    protocol INTEGER;
    denied BOOLEAN;
    before_state JSONB;
    after_state JSONB;
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
        'ai_quota_test_b981',
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
        '00000000-0000-4000-8000-00000000b980',
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
        '00000000-0000-4000-8000-00000000b981',
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
        '00000000-0000-4000-8000-00000000b982',
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


    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,
            'public.get_my_identification_preflight(text,text,boolean,uuid,integer)', 'EXECUTE')
            IS DISTINCT FROM (role_name = 'authenticated') THEN
            RAISE EXCEPTION 'recipient preview ACL is unsafe';
        END IF;
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,
            'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text)', 'EXECUTE')
            IS DISTINCT FROM (role_name = 'service_role') THEN
            RAISE EXCEPTION 'recipient reservation ACL is unsafe';
        END IF;
    END LOOP;
    IF EXISTS (SELECT 1 FROM internal.identification_provider_bindings
        WHERE provider <> 'gemini' OR processor_permission <> 'google_gemini' OR minimum_client_protocol <> 0) THEN
        RAISE EXCEPTION 'recipient preflight activated a different assignment';
    END IF;
    INSERT INTO auth.users(instance_id,id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES ('00000000-0000-0000-0000-000000000000', other_user_id,'authenticated','authenticated',
        'preflight-other@example.invalid','{}','{}',NOW() - INTERVAL '30 days',NOW());
    UPDATE public.users SET subscription_tier = 'pro', subscription_expires_at = NULL
        WHERE id IN (test_user_id,other_user_id);
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'legacy_trial', required_client_protocol = 0 WHERE config_key = 'current';

    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims','{}',TRUE);
    EXECUTE 'SET LOCAL ROLE authenticated';
    denied := FALSE;
    BEGIN
        PERFORM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    EXCEPTION WHEN SQLSTATE '42501' THEN
        denied := TRUE;
    END;
    EXECUTE 'RESET ROLE';
    IF NOT denied THEN RAISE EXCEPTION 'preflight accepted missing identity'; END IF;

    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT pg_catalog.COUNT(*) FROM public.user_ai_consent_events),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO before_state;
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims',pg_catalog.JSONB_BUILD_OBJECT('sub',test_user_id,'role','authenticated')::TEXT,TRUE);
    EXECUTE 'SET LOCAL ROLE authenticated';
    FOREACH profile IN ARRAY ARRAY['description_compat_v1','vision_compat_v1','audio_compat_v1',
        'multimodal_text_v1','multimodal_photo_v1','multimodal_audio_v1','multimodal_photo_audio_v1','multimodal_video_frames_v1','multimodal_video_audio_v1'] LOOP
        test_operation := CASE WHEN profile = 'audio_compat_v1' THEN 'scan_audio_identification' ELSE 'scan_identification' END;
        SELECT * INTO STRICT preview FROM public.get_my_identification_preflight(test_operation,profile,FALSE,scan_id,3);
        IF preview.input_profile <> profile OR preview.decision <> 'ready' OR preview.processor_permission <> 'google_gemini'
            OR preview.minimum_client_protocol <> 0 THEN
            RAISE EXCEPTION 'ready preview changed the recipient or profile';
        END IF;
    END LOOP;
    FOREACH profile IN ARRAY ARRAY[NULL,'legacy_v1','unknown','audio_compat_v1'] LOOP
        denied := FALSE;
        BEGIN
            PERFORM public.get_my_identification_preflight('scan_identification',profile,FALSE,scan_id,3);
        EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'preflight accepted an unsupported shape'; END IF;
    END LOOP;
    EXECUTE 'RESET ROLE';
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT pg_catalog.COUNT(*) FROM public.user_ai_consent_events),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO after_state;
    IF before_state IS DISTINCT FROM after_state THEN RAISE EXCEPTION 'preflight mutated admission or consent state'; END IF;

    -- A second account cannot borrow the first account's recipient permission.
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims',pg_catalog.JSONB_BUILD_OBJECT('sub',other_user_id,'role','authenticated')::TEXT,TRUE);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    EXECUTE 'RESET ROLE';
    IF preview.decision <> 'permission_required' OR preview.processor_permission <> 'google_gemini' THEN
        RAISE EXCEPTION 'preflight borrowed another account permission';
    END IF;
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims',pg_catalog.JSONB_BUILD_OBJECT('sub',test_user_id,'role','authenticated')::TEXT,TRUE);
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 3 WHERE input_profile = 'multimodal_photo_v1';
    FOREACH protocol IN ARRAY ARRAY[NULL,1,2,4,999] LOOP
        EXECUTE 'SET LOCAL ROLE authenticated';
        SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,protocol);
        EXECUTE 'RESET ROLE';
        IF preview.decision <> 'client_update_required' OR preview.minimum_client_protocol <> 3 THEN
            RAISE EXCEPTION 'preflight admitted an incompatible protocol';
        END IF;
    END LOOP;
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 0 WHERE input_profile = 'multimodal_photo_v1';

    -- Preview sees policy absence without guessing an assignment.
    UPDATE internal.ai_quota_policies SET policy_version = policy_version + 1
        WHERE operation = 'scan_identification' AND effective_plan = 'pro_paid';
    denied := FALSE;
    BEGIN
        PERFORM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_provider_assignment_unavailable' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'preflight guessed a missing binding'; END IF;
    UPDATE internal.ai_quota_policies SET policy_version = policy_version - 1
        WHERE operation = 'scan_identification' AND effective_plan = 'pro_paid';

    -- Only this rollback-only fixture widens recipient data, without allowing
    -- OpenAI model admission or dispatch. Simulate assignment drift after a
    -- Gemini preview; even an explicit OpenAI withdrawal must not mask that drift.
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.append_user_openai_consent_event(extensions.gen_random_uuid(),'2026-09-26','revoked',NOW(),
        'Synthetic disclosure','Synthetic withdrawal','ios','test','1',NULL);
    EXECUTE 'RESET ROLE';
    ALTER TABLE internal.identification_provider_bindings DROP CONSTRAINT identification_provider_bindings_recipient_tuple;
    UPDATE internal.identification_provider_bindings SET processor_permission = 'openai'
        WHERE effective_plan = 'pro_paid' AND input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    IF preview.decision <> 'ready' OR preview.processor_permission <> 'openai' THEN
        RAISE EXCEPTION 'beta preflight blocked the app-assigned recipient';
    END IF;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1','google_gemini');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_identification_preflight_changed' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied OR EXISTS (SELECT 1 FROM internal.ai_quota_reservations WHERE user_id = test_user_id AND request_id = scan_id) THEN
        RAISE EXCEPTION 'changed assignment admitted or charged a fresh request';
    END IF;
    UPDATE internal.identification_provider_bindings SET processor_permission = 'google_gemini';

    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1','google_gemini');
    EXECUTE 'RESET ROLE';
    IF admitted.is_replay OR admitted.processor_permission <> 'google_gemini' THEN RAISE EXCEPTION 'matching expectation failed'; END IF;
    -- Recovery does not manufacture recipient or capability evidence and the
    -- expectation cannot dispatch a second call for a live/committed lease.
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 4 WHERE input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    IF preview.decision <> 'recovery_only' OR preview.processor_permission IS NOT NULL OR preview.minimum_client_protocol IS NOT NULL THEN
        RAISE EXCEPTION 'live preflight reinterpreted its recipient';
    END IF;
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1','recovery_only');
    IF NOT repeated.is_replay THEN RAISE EXCEPTION 'recovery expectation dispatched a live duplicate'; END IF;
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'committed');
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1','recovery_only');
    IF preview.decision <> 'recovery_only' OR NOT repeated.is_replay OR repeated.reservation_state <> 'committed' THEN
        RAISE EXCEPTION 'committed recovery was not preserved';
    END IF;
    -- The global public-client gate precedes even recovery, unlike a changed
    -- binding minimum. Preflight must give the same update decision as Edge.
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'complimentary', required_client_protocol = 3 WHERE config_key = 'current';
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,2);
    IF preview.decision <> 'client_update_required' OR preview.processor_permission IS NOT NULL OR preview.minimum_client_protocol <> 3 THEN
        RAISE EXCEPTION 'recovery bypassed the global protocol fence';
    END IF;
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'legacy_trial', required_client_protocol = 0 WHERE config_key = 'current';
    -- Historical missing snapshots remain unknown, never backfilled by preview.
    DELETE FROM internal.identification_provider_attempts WHERE reservation_id = admitted.reservation_id;
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    IF preview.decision <> 'recovery_only' OR preview.processor_permission IS NOT NULL THEN RAISE EXCEPTION 'preview invented historical permission'; END IF;
    -- Another owner cannot discover that scan's recovery state.
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims',pg_catalog.JSONB_BUILD_OBJECT('sub',other_user_id,'role','authenticated')::TEXT,TRUE);
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    IF preview.decision <> 'client_update_required' THEN RAISE EXCEPTION 'preview leaked cross-owner recovery'; END IF;
    PERFORM pg_catalog.SET_CONFIG('request.jwt.claims',pg_catalog.JSONB_BUILD_OBJECT('sub',test_user_id,'role','authenticated')::TEXT,TRUE);
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 0 WHERE input_profile = 'multimodal_photo_v1';

    -- An expired/refunded/failed reservation is fresh work, never recovery
    -- authority. Re-preflight current policy before a later metered attempt.
    scan_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1','google_gemini');
    UPDATE internal.ai_quota_reservations SET lease_expires_at = NOW() - INTERVAL '1 minute' WHERE id = admitted.reservation_id;
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    IF preview.decision <> 'ready' THEN RAISE EXCEPTION 'expired reservation incorrectly allowed recovery'; END IF;
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'refunded');
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    IF preview.decision <> 'ready' THEN RAISE EXCEPTION 'refunded reservation incorrectly allowed recovery'; END IF;
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1','google_gemini');
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'committed');
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'failed');
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    IF preview.decision <> 'ready' THEN RAISE EXCEPTION 'failed reservation incorrectly allowed recovery'; END IF;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1','recovery_only');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_identification_preflight_changed' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'failed request resumed new work using recovery-only expectation'; END IF;

    -- A held/consumed scan keeps its complimentary funding even when there is
    -- no available credit for a new scan. Use different minima to observe plan.
    UPDATE public.users SET subscription_tier = 'free', created_at = NOW() - INTERVAL '30 days' WHERE id = test_user_id;
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'complimentary', required_client_protocol = 3 WHERE config_key = 'current';
    INSERT INTO internal.complimentary_scan_usage(user_id,client_scan_id,state,held_at,settled_at,settlement_reason)
    VALUES (test_user_id,held_scan_id,'held',NOW(),NULL,NULL),
        (test_user_id,'00000000-0000-4000-8000-00000000b986','consumed',NOW(),NOW(),'completed'),
        (test_user_id,'00000000-0000-4000-8000-00000000b987','consumed',NOW(),NOW(),'completed');
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 4
        WHERE effective_plan = 'free' AND input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,held_scan_id,3);
    IF preview.decision <> 'ready' OR preview.minimum_client_protocol <> 3 THEN RAISE EXCEPTION 'preview lost the held scan funding'; END IF;
    UPDATE internal.complimentary_scan_usage SET state = 'consumed', settled_at = NOW(), settlement_reason = 'completed'
        WHERE user_id = test_user_id AND client_scan_id = held_scan_id;
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,held_scan_id,3);
    IF preview.decision <> 'ready' THEN RAISE EXCEPTION 'preview lost consumed scan funding'; END IF;
    scan_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',TRUE,scan_id,3);
    IF preview.decision <> 'client_update_required' OR preview.minimum_client_protocol <> 4 THEN RAISE EXCEPTION 'new scan borrowed another scan credit'; END IF;
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,2);
    IF preview.decision <> 'client_update_required' OR preview.processor_permission IS NOT NULL THEN
        RAISE EXCEPTION 'entitlement failure preceded global compatibility';
    END IF;
    denied := FALSE;
    BEGIN
        PERFORM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,3);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_entitlement_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'preview manufactured an unavailable entitlement'; END IF;

    DELETE FROM internal.complimentary_scan_usage WHERE user_id = test_user_id;
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 0;
    SELECT * INTO STRICT preview FROM public.get_my_identification_preflight('scan_identification','multimodal_photo_v1',FALSE,scan_id,2);
    IF preview.decision <> 'client_update_required' OR preview.minimum_client_protocol <> 3 THEN RAISE EXCEPTION 'preview ignored global protocol fence'; END IF;
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO before_state;
    FOREACH expected IN ARRAY ARRAY['openai','recovery_only'] LOOP
        denied := FALSE;
        BEGIN
            PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',scan_id,pg_catalog.REPEAT('b',64),scan_id,FALSE,3,FALSE,'multimodal_photo_v1',expected);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_identification_preflight_changed' THEN RAISE; END IF;
            denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'mismatched expectation admitted fresh inference'; END IF;
    END LOOP;
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO after_state;
    IF before_state IS DISTINCT FROM after_state THEN RAISE EXCEPTION 'recipient drift consumed a counter or complimentary credit'; END IF;
END;
$test$;
SELECT extensions.pass('recipient preflight is advisory, caller-bound and fresh admission rejects drift atomically');
SELECT * FROM extensions.finish();
ROLLBACK;
