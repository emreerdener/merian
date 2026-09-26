\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-0000-0000-00000000b941';
    request_id UUID := '00000000-0000-0000-0000-00000000b942';
    legacy_request UUID := '00000000-0000-0000-0000-00000000b943';
    new_request UUID := '00000000-0000-0000-0000-00000000b944';
    admitted RECORD;
    repeated RECORD;
    retried RECORD;
    legacy RECORD;
    assignment internal.identification_provider_bindings%ROWTYPE;
    old_snapshot JSONB;
    denied BOOLEAN;
    role_name TEXT;
    recipient TEXT;
    baseline_reservations BIGINT;
    baseline_counters BIGINT;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
        IF pg_catalog.HAS_TABLE_PRIVILEGE(role_name, 'internal.identification_provider_bindings', 'SELECT,INSERT,UPDATE,DELETE')
           OR pg_catalog.HAS_TABLE_PRIVILEGE(role_name, 'internal.identification_provider_attempts', 'SELECT,INSERT,UPDATE,DELETE')
           OR pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name, 'internal.require_current_ai_consent(uuid,text)', 'EXECUTE') THEN
            RAISE EXCEPTION 'private assignment/recipient boundary exposed';
        END IF;
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name,
            'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)', 'EXECUTE')
            IS DISTINCT FROM (role_name = 'service_role') THEN
            RAISE EXCEPTION 'identification quota RPC ACL mismatch';
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
    PERFORM internal.require_current_ai_consent(test_user_id, 'google_gemini');
    FOREACH recipient IN ARRAY ARRAY['openai', 'unknown', '', NULL] LOOP
        denied := FALSE;
        BEGIN
            PERFORM internal.require_current_ai_consent(test_user_id, recipient);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
            denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'Gemini receipt authorized another recipient'; END IF;
    END LOOP;

    -- Exercise the actual service role; it can use only the reviewed definer RPC.
    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO STRICT admitted FROM public.reserve_identification_quota(
        test_user_id, 'scan_identification', request_id, pg_catalog.REPEAT('b',64), request_id, FALSE, 3, FALSE);
    EXECUTE 'RESET ROLE';
    IF admitted.is_replay OR admitted.provider <> 'gemini'
       OR admitted.binding <> 'gemini_baseline_v1'
       OR admitted.processor_permission <> 'google_gemini' THEN
        RAISE EXCEPTION 'fresh reservation lacks exact Gemini assignment';
    END IF;
    SELECT pg_catalog.TO_JSONB(saved) INTO STRICT old_snapshot
    FROM internal.identification_provider_attempts AS saved
    WHERE saved.reservation_id = admitted.reservation_id AND saved.attempt_count = admitted.attempt_count;

    SELECT * INTO STRICT assignment FROM internal.identification_provider_bindings AS bindings
    WHERE bindings.operation = 'scan_identification' AND bindings.effective_plan = admitted.effective_plan
      AND bindings.model = admitted.model AND bindings.policy_version = admitted.policy_version;
    DELETE FROM internal.identification_provider_bindings WHERE operation = assignment.operation
      AND effective_plan = assignment.effective_plan AND model = assignment.model AND policy_version = assignment.policy_version;
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(
        test_user_id, 'scan_identification', request_id, pg_catalog.REPEAT('b',64), request_id, FALSE, 3, FALSE);
    IF NOT repeated.is_replay OR repeated.reservation_id <> admitted.reservation_id
       OR repeated.binding <> admitted.binding OR repeated.attempt_count <> admitted.attempt_count THEN
        RAISE EXCEPTION 'replay reinterpreted its saved assignment';
    END IF;

    SELECT pg_catalog.COUNT(*) INTO baseline_reservations FROM internal.ai_quota_reservations;
    SELECT COALESCE(pg_catalog.SUM(request_count),0) INTO baseline_counters FROM internal.ai_quota_counters;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id, 'scan_identification', new_request,
            pg_catalog.REPEAT('b',64), new_request, FALSE, 3, FALSE);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_provider_assignment_unavailable' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied OR baseline_reservations <> (SELECT pg_catalog.COUNT(*) FROM internal.ai_quota_reservations)
       OR baseline_counters <> (SELECT COALESCE(pg_catalog.SUM(request_count),0) FROM internal.ai_quota_counters) THEN
        RAISE EXCEPTION 'missing binding left quota consumption or a usable reservation';
    END IF;
    INSERT INTO internal.identification_provider_bindings SELECT assignment.*;

    -- New metered generation preserves old provenance rather than replacing it.
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id, test_user_id, admitted.lease_token, 'committed');
    PERFORM public.finalize_ai_quota_reservation(admitted.reservation_id, test_user_id, admitted.lease_token, 'failed');
    SELECT * INTO STRICT retried FROM public.reserve_identification_quota(
        test_user_id, 'scan_identification', request_id, pg_catalog.REPEAT('b',64), request_id, FALSE, 3, FALSE);
    IF retried.is_replay OR retried.attempt_count <> admitted.attempt_count + 1
       OR retried.lease_token = admitted.lease_token
       OR (SELECT pg_catalog.COUNT(*) FROM internal.identification_provider_attempts WHERE reservation_id = admitted.reservation_id) <> 2
       OR old_snapshot IS DISTINCT FROM (SELECT pg_catalog.TO_JSONB(saved) FROM internal.identification_provider_attempts AS saved
            WHERE saved.reservation_id = admitted.reservation_id AND saved.attempt_count = admitted.attempt_count) THEN
        RAISE EXCEPTION 'retry did not retain immutable attempt generations';
    END IF;

    -- A policy version is part of admission, not merely a model label.
    UPDATE internal.ai_quota_policies SET policy_version = policy_version + 1
        WHERE operation = assignment.operation AND effective_plan = assignment.effective_plan;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id, 'scan_identification', new_request,
            pg_catalog.REPEAT('b',64), new_request, FALSE, 3, FALSE);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_provider_assignment_unavailable' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'unreviewed policy version was admitted'; END IF;
    UPDATE internal.ai_quota_policies SET policy_version = assignment.policy_version
        WHERE operation = assignment.operation AND effective_plan = assignment.effective_plan;

    -- No synthetic history is attached to live/completed reservations from old workers.
    SELECT * INTO STRICT legacy FROM public.reserve_ai_quota(test_user_id, 'scan_identification', legacy_request,
        pg_catalog.REPEAT('b',64), legacy_request, FALSE, 3, FALSE);
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id, 'scan_identification', legacy_request,
        pg_catalog.REPEAT('b',64), legacy_request, FALSE, 3, FALSE);
    IF NOT repeated.is_replay OR repeated.provider IS NOT NULL
       OR EXISTS (SELECT 1 FROM internal.identification_provider_attempts WHERE reservation_id = legacy.reservation_id) THEN
        RAISE EXCEPTION 'legacy replay fabricated provider evidence';
    END IF;
    PERFORM public.finalize_ai_quota_reservation(legacy.reservation_id, test_user_id, legacy.lease_token, 'committed');
    SELECT * INTO STRICT repeated FROM public.reserve_identification_quota(test_user_id, 'scan_identification', legacy_request,
        pg_catalog.REPEAT('b',64), legacy_request, FALSE, 3, FALSE);
    IF NOT repeated.is_replay OR repeated.reservation_state <> 'committed' OR repeated.provider IS NOT NULL THEN
        RAISE EXCEPTION 'legacy committed result became dispatchable';
    END IF;

    -- Snapshot drift is rejected even if the current catalog still matches.
    UPDATE internal.identification_provider_attempts SET model = 'gemini-2.5-flash'
        WHERE reservation_id = retried.reservation_id AND attempt_count = retried.attempt_count;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id, 'scan_identification', request_id,
            pg_catalog.REPEAT('b',64), request_id, FALSE, 3, FALSE);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_provider_assignment_unavailable' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'snapshot drift was reinterpreted'; END IF;
    UPDATE internal.identification_provider_attempts SET model = retried.model
        WHERE reservation_id = retried.reservation_id AND attempt_count = retried.attempt_count;

    -- Provider-wide revoke remains authoritative for fresh admission and retry.
    INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,
        occurred_at,disclosure_text,action_text,platform,app_version,app_build)
    VALUES ('00000000-0000-4000-8000-00000000b94f',test_user_id,'google_gemini','2099-01-01','revoked',
        pg_catalog.NOW(),'Synthetic revocation','Revoke','ios','1','1');
    FOREACH recipient IN ARRAY ARRAY['google_gemini', 'openai'] LOOP
        denied := FALSE;
        BEGIN
            PERFORM internal.require_current_ai_consent(test_user_id,recipient);
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
            denied := TRUE;
        END;
        IF NOT denied THEN RAISE EXCEPTION 'revocation was ignored'; END IF;
    END LOOP;
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id, 'scan_identification', new_request,
            pg_catalog.REPEAT('b',64), new_request, FALSE, 3, FALSE);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM <> 'ai_consent_required' THEN RAISE; END IF;
        denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'revoked user was admitted'; END IF;

    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_overview_enrichment',new_request,
            pg_catalog.REPEAT('b',64),NULL,FALSE,3,FALSE);
    EXCEPTION WHEN SQLSTATE '22023' THEN denied := TRUE;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'content operation entered identification admission'; END IF;

    EXECUTE 'SET LOCAL ROLE authenticated';
    denied := FALSE;
    BEGIN
        PERFORM public.reserve_identification_quota(test_user_id,'scan_identification',new_request,
            pg_catalog.REPEAT('b',64),new_request,FALSE,3,FALSE);
    EXCEPTION WHEN insufficient_privilege THEN denied := TRUE;
    END;
    EXECUTE 'RESET ROLE';
    IF NOT denied THEN RAISE EXCEPTION 'authenticated caller bypassed service boundary'; END IF;

    DELETE FROM internal.ai_quota_reservations WHERE id = admitted.reservation_id;
    IF EXISTS (SELECT 1 FROM internal.identification_provider_attempts WHERE reservation_id = admitted.reservation_id) THEN
        RAISE EXCEPTION 'quota cleanup retained attempt data';
    END IF;
END;
$test$;
SELECT extensions.pass('identification recipient admission, replay, retry, rollback, consent and privileges');
SELECT * FROM extensions.finish();
ROLLBACK;
