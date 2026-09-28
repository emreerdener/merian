\set ON_ERROR_STOP on
BEGIN;
-- This fixture verifies the supported Gemini/legacy routing configuration.
-- Activation defaults are asserted independently by openai_photo_routing.sql.
UPDATE internal.identification_provider_bindings
SET provider = 'gemini', binding = 'gemini_baseline_v1',
    processor_permission = 'google_gemini', provider_model = NULL,
    minimum_identification_protocol = 0, minimum_client_protocol = 0
WHERE operation = 'scan_identification' AND input_profile = 'multimodal_photo_v1';

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-0000-0000-00000000b941';
    test_request_id UUID;
    replay_id UUID;
    admitted RECORD;
    repeated RECORD;
    origin RECORD;
    saved JSONB;
    denied BOOLEAN;
    role_name TEXT;
    signature TEXT;
    protocol INTEGER;
    counts_before JSONB;
    counts_after JSONB;
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

    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,
            'internal.require_identification_client_protocol(uuid,text,uuid,text,integer,boolean,integer)', 'EXECUTE') THEN
            RAISE EXCEPTION 'compatibility helper exposed to API role';
        END IF;
        FOREACH signature IN ARRAY ARRAY[
            'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
            'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)'
        ] LOOP
            IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,signature,'EXECUTE') IS DISTINCT FROM (role_name = 'service_role') THEN
                RAISE EXCEPTION 'identification RPC ACL changed';
            END IF;
        END LOOP;
    END LOOP;
    IF EXISTS (SELECT 1 FROM internal.identification_provider_bindings
        WHERE minimum_client_protocol <> 0 OR provider <> 'gemini') THEN
        RAISE EXCEPTION 'migration activated a provider or changed current compatibility';
    END IF;
    UPDATE public.users SET subscription_tier = 'pro', subscription_expires_at = NULL WHERE id = test_user_id;
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'legacy_trial', required_client_protocol = 0 WHERE config_key = 'current';

    -- Legacy schema-first requests remain admissible; unknown is never upgraded
    -- into recognized capability evidence, even for numeric future claims.
    FOREACH protocol IN ARRAY ARRAY[NULL,1,2,3,4,999] LOOP
        test_request_id := extensions.gen_random_uuid();
        EXECUTE 'SET LOCAL ROLE service_role';
        SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,protocol,FALSE,'multimodal_photo_v1');
        EXECUTE 'RESET ROLE';
        IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_attempts AS attempt
            WHERE attempt.reservation_id = admitted.reservation_id AND attempt.attempt_count = admitted.attempt_count
              AND attempt.minimum_client_protocol = 0
              AND attempt.accepted_client_protocol IS NOT DISTINCT FROM CASE WHEN protocol BETWEEN 1 AND 3 THEN protocol ELSE NULL END) THEN
            RAISE EXCEPTION 'schema-first capability snapshot is incorrect';
        END IF;
        PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'refunded');
    END LOOP;

    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 3
        WHERE input_profile IN ('legacy_v1','multimodal_text_v1','multimodal_photo_v1');
    -- Both RPC ABIs reject missing, older and unrecognized claims. Every failed
    -- fresh admission rolls back the reservation and immutable snapshot.
    FOREACH protocol IN ARRAY ARRAY[NULL,1,2,4,999] LOOP
        test_request_id := extensions.gen_random_uuid();
        FOREACH signature IN ARRAY ARRAY['legacy','profile'] LOOP
            denied := FALSE;
            BEGIN
                IF signature = 'legacy' THEN
                    PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
                        pg_catalog.REPEAT('b',64),test_request_id,FALSE,protocol,FALSE);
                ELSE
                    PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
                        pg_catalog.REPEAT('b',64),test_request_id,FALSE,protocol,FALSE,'multimodal_photo_v1');
                END IF;
            EXCEPTION WHEN SQLSTATE 'P0001' THEN
                IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
                denied := TRUE;
            END;
            IF NOT denied OR EXISTS (SELECT 1 FROM internal.ai_quota_reservations AS reservations WHERE user_id = test_user_id AND reservations.request_id = test_request_id) THEN
                RAISE EXCEPTION 'incompatible fresh admission was not rolled back';
            END IF;
        END LOOP;
    END LOOP;

    -- A recognized client admits once; catalog edits do not reinterpret a live
    -- or committed duplicate, and a refunded retry requires a new snapshot.
    test_request_id := extensions.gen_random_uuid();
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 0 WHERE input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,2,FALSE,'multimodal_photo_v1');
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'refunded');
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 3 WHERE input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1');
    IF NOT EXISTS (SELECT 1 FROM internal.ai_quota_reservations AS reservation
        JOIN internal.identification_provider_attempts AS attempt ON attempt.reservation_id = reservation.id
        WHERE reservation.id = admitted.reservation_id AND reservation.client_protocol = 2
          AND attempt.attempt_count = admitted.attempt_count AND attempt.accepted_client_protocol = 3) THEN
        RAISE EXCEPTION 'new generation reused stale reservation-level protocol';
    END IF;
    SELECT pg_catalog.TO_JSONB(attempt) INTO STRICT saved FROM internal.identification_provider_attempts AS attempt
        WHERE attempt.reservation_id = admitted.reservation_id AND attempt.attempt_count = admitted.attempt_count;
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 4 WHERE input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,NULL,FALSE,'multimodal_photo_v1');
    IF NOT repeated.is_replay THEN RAISE EXCEPTION 'catalog cutoff hid active recovery'; END IF;
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'committed');
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,NULL,FALSE,'multimodal_photo_v1');
    IF NOT repeated.is_replay OR repeated.reservation_state <> 'committed' THEN RAISE EXCEPTION 'catalog cutoff hid committed recovery'; END IF;
    IF saved IS DISTINCT FROM (SELECT pg_catalog.TO_JSONB(attempt) FROM internal.identification_provider_attempts AS attempt
        WHERE attempt.reservation_id = admitted.reservation_id AND attempt.attempt_count = admitted.attempt_count) THEN
        RAISE EXCEPTION 'compatibility snapshot was rewritten by replay';
    END IF;
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'failed');
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'new retry reused old compatibility admission'; END IF;
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 3 WHERE input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1');
    IF repeated.is_replay OR repeated.attempt_count <> admitted.attempt_count + 1 THEN RAISE EXCEPTION 'retry lost separate generation'; END IF;
    PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');

    -- Original-client proof, not the worker's claimed header, authorizes a new
    -- internal replay. The source must be the current exact-profile attempt.
    replay_id := extensions.gen_random_uuid();
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',replay_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,NULL,TRUE,'multimodal_photo_v1');
    IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_attempts AS attempt
        WHERE attempt.reservation_id = repeated.reservation_id AND attempt.attempt_count = repeated.attempt_count
          AND attempt.minimum_client_protocol = 3 AND attempt.accepted_client_protocol = 3) THEN
        RAISE EXCEPTION 'internal replay did not inherit exact original proof';
    END IF;
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',replay_id,
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,999,TRUE,'multimodal_photo_v1');
    IF NOT repeated.is_replay THEN RAISE EXCEPTION 'internal duplicate dispatched twice'; END IF;
    PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');

    -- Exercise every dimension of the source proof without touching real data.
    FOREACH signature IN ARRAY ARRAY['owner','operation','observation','profile','old_generation','unknown'] LOOP
        denied := FALSE;
        BEGIN
            IF signature IN ('old_generation','unknown') THEN
                UPDATE internal.identification_provider_attempts AS attempt
                SET accepted_client_protocol = CASE WHEN signature = 'old_generation' THEN 2 ELSE NULL END
                WHERE attempt.reservation_id = admitted.reservation_id
                  AND attempt.attempt_count = admitted.attempt_count + 1;
            END IF;
            PERFORM internal.require_identification_client_protocol(
                CASE WHEN signature = 'owner' THEN '00000000-0000-0000-0000-00000000b999'::UUID ELSE test_user_id END,
                CASE WHEN signature = 'operation' THEN 'scan_audio_identification' ELSE 'scan_identification' END,
                CASE WHEN signature = 'observation' THEN extensions.gen_random_uuid() ELSE test_request_id END,
                CASE WHEN signature = 'profile' THEN 'multimodal_text_v1' ELSE 'multimodal_photo_v1' END,
                3,TRUE,3);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
            denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'worker header bypassed missing or mismatched source proof'; END IF;
    END LOOP;

    -- Even a stored reservation-level protocol is insufficient for historical
    -- attempts with no immutable accepted protocol.
    UPDATE internal.identification_provider_attempts AS attempt SET accepted_client_protocol = NULL, minimum_client_protocol = NULL
        WHERE attempt.reservation_id = admitted.reservation_id;
    UPDATE internal.ai_quota_reservations SET client_protocol = 3 WHERE id = admitted.reservation_id;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',extensions.gen_random_uuid(),
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,TRUE,'multimodal_photo_v1');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'historical unknown was promoted by worker header'; END IF;

    -- Restore dormant policy: old background workers still run without proof.
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 0 WHERE input_profile = 'multimodal_photo_v1';
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',extensions.gen_random_uuid(),
        pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,TRUE,'multimodal_photo_v1');
    IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_attempts AS attempt
        WHERE attempt.reservation_id = repeated.reservation_id AND attempt.accepted_client_protocol IS NULL AND attempt.minimum_client_protocol = 0) THEN
        RAISE EXCEPTION 'legacy worker header manufactured client capability';
    END IF;
    PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');

    -- Compatibility intents currently replay through the multimodal endpoint.
    -- Their transformed profile (and audio operation) cannot lend eligibility
    -- to a future gated binding. All current zero-minimum recovery still works.
    FOR origin IN SELECT * FROM (VALUES
        ('scan_identification','vision_compat_v1','multimodal_photo_v1'),
        ('scan_identification','description_compat_v1','multimodal_text_v1'),
        ('scan_audio_identification','audio_compat_v1','multimodal_audio_v1')
    ) AS origins(operation, profile, replay_profile) LOOP
        test_request_id := extensions.gen_random_uuid();
        SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(test_user_id,origin.operation,test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,origin.profile);
        PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id,test_user_id,admitted.lease_token,'refunded');
        UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 0 WHERE input_profile = origin.replay_profile;
        SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id,'scan_identification',extensions.gen_random_uuid(),
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,NULL,TRUE,origin.replay_profile);
        IF NOT EXISTS (SELECT 1 FROM internal.identification_provider_attempts AS attempt
            WHERE attempt.reservation_id = repeated.reservation_id AND attempt.accepted_client_protocol IS NULL) THEN
            RAISE EXCEPTION 'compatibility transformation manufactured protocol proof';
        END IF;
        PERFORM public.finalize_ai_quota_reservation(repeated.reservation_id,test_user_id,repeated.lease_token,'refunded');
        UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 3 WHERE input_profile = origin.replay_profile;
        denied := FALSE;
        BEGIN
            PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',extensions.gen_random_uuid(),
                pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,TRUE,origin.replay_profile);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
            denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'unqualified compatibility replay entered a gated binding'; END IF;
        UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 0 WHERE input_profile = origin.replay_profile;
    END LOOP;

    -- A future min4 is intentionally impossible until the coordinated accepted
    -- maximum expansion. Denial must refund all atomic complimentary effects.
    UPDATE public.users SET subscription_tier = 'free' WHERE id = test_user_id;
    UPDATE internal.entitlement_rollout_config SET entitlement_mode = 'complimentary', required_client_protocol = 3 WHERE config_key = 'current';
    UPDATE internal.identification_provider_bindings SET minimum_client_protocol = 4 WHERE input_profile = 'multimodal_photo_v1';
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO counts_before;
    test_request_id := extensions.gen_random_uuid();
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',test_request_id,
            pg_catalog.REPEAT('b',64),test_request_id,FALSE,3,FALSE,'multimodal_photo_v1');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'client_update_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    SELECT pg_catalog.JSONB_BUILD_ARRAY(
        (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations),
        (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters),
        (SELECT pg_catalog.COUNT(*) FROM internal.identification_provider_attempts),
        (SELECT pg_catalog.COUNT(*) FROM internal.complimentary_scan_usage),
        (SELECT complimentary_entitlement_epoch FROM public.users WHERE id = test_user_id)
    ) INTO counts_after;
    IF NOT denied OR counts_before IS DISTINCT FROM counts_after THEN RAISE EXCEPTION 'compatibility rejection consumed quota or complimentary credit'; END IF;
END;
$test$;
SELECT extensions.pass('Binding compatibility, immutable protocol proof, exact internal replay and atomic denial');
SELECT * FROM extensions.finish();
ROLLBACK;
