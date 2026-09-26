\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-0000-0000-00000000b941';
    request_id UUID := '00000000-0000-0000-0000-00000000b942';
    new_request UUID := '00000000-0000-0000-0000-00000000b944';
    admitted RECORD;
    repeated RECORD;
    item RECORD;
    old_snapshot JSONB;
    denied BOOLEAN;
    role_name TEXT;
    signature TEXT;
    counts_before JSONB;
    counts_after JSONB;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
        FOREACH signature IN ARRAY ARRAY['uuid,text,uuid,text','uuid,text,uuid,text,uuid,boolean,integer,boolean'] LOOP
            IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,'internal.reserve_ai_quota_core(' || signature || ')','EXECUTE') THEN
                RAISE EXCEPTION 'private quota core exposed to API role';
            END IF;
            IF pg_catalog.STRPOS(pg_catalog.PG_GET_FUNCTIONDEF(pg_catalog.TO_REGPROCEDURE('internal.reserve_ai_quota_core(' || signature || ')')), 'require_current_ai_consent') > 0 THEN
                RAISE EXCEPTION 'private quota core still hardcodes a processor';
            END IF;
        END LOOP;
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)','EXECUTE')
            IS DISTINCT FROM (role_name = 'service_role') THEN
            RAISE EXCEPTION 'profile routing RPC ACL mismatch';
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



    UPDATE public.users SET subscription_tier = 'pro', subscription_expires_at = NULL WHERE id = test_user_id;
    IF EXISTS (SELECT 1 FROM internal.identification_provider_bindings WHERE provider <> 'gemini' OR processor_permission <> 'google_gemini') THEN
        RAISE EXCEPTION 'routing enabled an unqualified provider';
    END IF;
    FOR item IN SELECT DISTINCT input_profile, operation FROM internal.identification_provider_bindings WHERE input_profile <> 'legacy_v1' LOOP
        request_id := extensions.gen_random_uuid();
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,item.operation,request_id,
            pg_catalog.REPEAT('b',64),request_id,FALSE,3,FALSE,item.input_profile);
        EXECUTE 'RESET ROLE';
        IF admitted.input_profile IS DISTINCT FROM item.input_profile OR admitted.provider <> 'gemini' OR admitted.is_replay THEN
            RAISE EXCEPTION 'fresh app-assigned profile missing';
        END IF;
        PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'refunded');
    END LOOP;
    request_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',request_id,
        pg_catalog.REPEAT('b',64),request_id,FALSE,3,FALSE,'multimodal_photo_v1');
    SELECT pg_catalog.TO_JSONB(saved) INTO STRICT old_snapshot FROM internal.identification_provider_attempts AS saved
        WHERE saved.reservation_id = admitted.reservation_id AND saved.attempt_count = admitted.attempt_count;
    -- Replaying a saved attempt does not consult a changed/removed catalog row.
    DELETE FROM internal.identification_provider_bindings WHERE input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',request_id,
        pg_catalog.REPEAT('b',64),request_id,FALSE,3,FALSE,'multimodal_photo_v1');
    IF NOT repeated.is_replay OR repeated.input_profile <> admitted.input_profile OR repeated.attempt_count <> admitted.attempt_count THEN
        RAISE EXCEPTION 'replay changed saved routing profile';
    END IF;
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',request_id,
        pg_catalog.REPEAT('b',64),request_id,FALSE,3,FALSE,'multimodal_text_v1');
    IF NOT repeated.is_replay OR repeated.input_profile <> 'multimodal_photo_v1' OR repeated.reservation_state <> 'reserved' THEN
        RAISE EXCEPTION 'changed duplicate shape bypassed original active replay';
    END IF;
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'committed');    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',request_id,
        pg_catalog.REPEAT('b',64),request_id,FALSE,3,FALSE,'multimodal_text_v1');
    IF NOT repeated.is_replay OR repeated.input_profile <> 'multimodal_photo_v1' OR repeated.reservation_state <> 'committed' THEN
        RAISE EXCEPTION 'changed duplicate shape bypassed original completion replay';
    END IF;

    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'failed');
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',request_id,
            pg_catalog.REPEAT('b',64),request_id,FALSE,3,FALSE,'multimodal_text_v1');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_provider_assignment_unavailable' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied OR old_snapshot IS DISTINCT FROM (SELECT pg_catalog.TO_JSONB(saved) FROM internal.identification_provider_attempts AS saved
        WHERE saved.reservation_id = admitted.reservation_id AND saved.attempt_count = admitted.attempt_count) THEN
        RAISE EXCEPTION 'changed retry evidence reinterpreted a reservation';
    END IF;
    -- Missing routing and recipient denial must also roll back complimentary holds.
    UPDATE public.users SET subscription_tier = 'free' WHERE id = test_user_id;
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'complimentary', required_client_protocol = 3 WHERE config_key = 'current';
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO counts_before;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',new_request,
            pg_catalog.REPEAT('b',64),new_request,FALSE,3,FALSE,'multimodal_photo_v1');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_provider_assignment_unavailable' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'missing route fell back'; END IF;
    INSERT INTO public.user_ai_consent_events (id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
    VALUES ('00000000-0000-4000-8000-00000000b94f',test_user_id,'google_gemini','2026-08-04.1','revoked',pg_catalog.NOW(),'Synthetic revocation','Revoke','ios','1','1'),
        ('00000000-0000-4000-8000-00000000b950',test_user_id,'openai','2026-09-26','granted',pg_catalog.NOW(),'Synthetic OpenAI grant','Allow','ios','1','1');
    PERFORM internal.require_current_ai_consent(test_user_id,'openai');
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',new_request,
            pg_catalog.REPEAT('b',64),new_request,FALSE,3,FALSE,'multimodal_text_v1');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'user consent changed the app-selected provider'; END IF;
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO counts_after;
    IF counts_before IS DISTINCT FROM counts_after THEN RAISE EXCEPTION 'denied routing or consent left quota or hold consumption'; END IF;
    -- The internal core remains processor-neutral, but cannot be called by API roles.
    SELECT * INTO STRICT repeated FROM internal.reserve_ai_quota_core(test_user_id,'scan_identification',new_request,
        pg_catalog.REPEAT('b',64),new_request,FALSE,3,FALSE);
    PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');
    FOREACH signature IN ARRAY ARRAY['unknown','legacy_v1','audio_compat_v1'] LOOP
        denied := FALSE;
        BEGIN
            PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',new_request,
                pg_catalog.REPEAT('b',64),new_request,FALSE,3,FALSE,signature);
        EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'invalid profile/operation admitted'; END IF;
    END LOOP;
END;
$test$;
SELECT extensions.pass('App-owned input routes, private quota cores, replay and recipient-denial rollback');
SELECT * FROM extensions.finish();
ROLLBACK;
