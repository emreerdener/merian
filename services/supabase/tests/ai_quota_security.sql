\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-0000-0000-00000000a901';
    request_id UUID := '00000000-0000-0000-0000-00000000a902';
    second_request_id UUID := '00000000-0000-0000-0000-00000000a903';
    first_reservation RECORD;
    replayed_reservation RECORD;
    retried_reservation RECORD;
    stale_reservation RECORD;
    recovered_reservation RECORD;
    initial_entitlement_version BIGINT;
    updated_entitlement_version BIGINT;
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.reserve_ai_quota(uuid,text,uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.reserve_ai_quota(uuid,text,uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.reserve_ai_quota(uuid,text,uuid,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'reserve_ai_quota has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'finalize_ai_quota_reservation has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.users',
        'subscription_tier',
        'UPDATE'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.users',
        'subscription_expires_at',
        'UPDATE'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.users',
        'entitlement_version',
        'UPDATE'
    ) OR NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.users',
        'default_geoprivacy',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION 'public.users column privileges expose entitlement state';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.users',
        'INSERT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.users',
        'DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.users',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION 'API roles can replace or mutate public user identity rows';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attributes
        WHERE attributes.attrelid = 'public.users'::pg_catalog.REGCLASS
          AND attributes.attnum > 0
          AND NOT attributes.attisdropped
          AND (
              pg_catalog.HAS_COLUMN_PRIVILEGE(
                  'anon',
                  'public.users',
                  attributes.attname,
                  'INSERT'
              )
              OR pg_catalog.HAS_COLUMN_PRIVILEGE(
                  'authenticated',
                  'public.users',
                  attributes.attname,
                  'INSERT'
              )
              OR pg_catalog.HAS_COLUMN_PRIVILEGE(
                  'anon',
                  'public.users',
                  attributes.attname,
                  'UPDATE'
              )
              OR (
                  attributes.attname NOT IN (
                      'default_geoprivacy',
                      'marketing_opt_in'
                  )
                  AND pg_catalog.HAS_COLUMN_PRIVILEGE(
                      'authenticated',
                      'public.users',
                      attributes.attname,
                      'UPDATE'
                  )
              )
          )
    ) THEN
        RAISE EXCEPTION 'public.users retains an unsafe column-level write ACL';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.ai_quota_reservations',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.ai_quota_policies',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'AI quota internals are directly visible to API roles';
    END IF;

    IF internal.effective_plan(
        'free'::public.subscription_tier_enum,
        NOW() + INTERVAL '1 day',
        NULL
    ) <> 'free' THEN
        RAISE EXCEPTION 'future-dated users unexpectedly receive a Pro trial';
    END IF;

    BEGIN
        PERFORM public.reserve_ai_quota(
            test_user_id,
            'scan_identification',
            request_id,
            pg_catalog.REPEAT('a', 64)
        );
        RAISE EXCEPTION 'request without current consent unexpectedly reached entitlement resolution';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_consent_required' THEN
                RAISE;
            END IF;
    END;

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
        'ai-quota-test@example.invalid',
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
        'ai-quota-test@example.invalid',
        'ai_quota_test_a901',
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
        '00000000-0000-4000-8000-00000000a9f0',
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
        '00000000-0000-4000-8000-00000000a9f1',
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
        '00000000-0000-4000-8000-00000000a9f2',
        test_user_id,
        'google_gemini',
        '2026-08-03.1',
        'granted',
        pg_catalog.NOW(),
        'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
        'I accept the terms and allow this data sharing',
        'ios',
        '1.0.3',
        '275'
    );

    SELECT users.entitlement_version
    INTO initial_entitlement_version
    FROM public.users AS users
    WHERE users.id = test_user_id;

    SELECT *
    INTO STRICT first_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        request_id,
        pg_catalog.REPEAT('a', 64)
    );

    IF first_reservation.is_replay
       OR first_reservation.reservation_state <> 'reserved'
       OR first_reservation.model <> 'gemini-2.5-flash'
       OR first_reservation.effective_plan <> 'free'
       OR first_reservation.daily_limit <> 1
       OR first_reservation.daily_remaining <> 0 THEN
        RAISE EXCEPTION 'initial free reservation returned invalid policy state';
    END IF;

    SELECT *
    INTO STRICT replayed_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        request_id,
        pg_catalog.REPEAT('a', 64)
    );

    IF NOT replayed_reservation.is_replay
       OR replayed_reservation.reservation_id
            <> first_reservation.reservation_id THEN
        RAISE EXCEPTION 'idempotent reservation replay consumed new quota';
    END IF;

    BEGIN
        PERFORM public.reserve_ai_quota(
            test_user_id,
            'scan_identification',
            second_request_id,
            pg_catalog.REPEAT('a', 64)
        );
        RAISE EXCEPTION 'second free reservation unexpectedly succeeded';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_quota_daily_exceeded' THEN
                RAISE;
            END IF;
    END;

    IF NOT public.finalize_ai_quota_reservation(
        first_reservation.reservation_id,
        test_user_id,
        first_reservation.lease_token,
        'refunded'
    ) THEN
        RAISE EXCEPTION 'refund finalization returned false';
    END IF;

    BEGIN
        PERFORM public.finalize_ai_quota_reservation(
            first_reservation.reservation_id,
            test_user_id,
            first_reservation.lease_token,
            NULL
        );
        RAISE EXCEPTION 'NULL finalization unexpectedly succeeded';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            IF SQLERRM <> 'ai_quota_invalid_finalization' THEN
                RAISE;
            END IF;
    END;

    SELECT *
    INTO STRICT retried_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        request_id,
        pg_catalog.REPEAT('a', 64)
    );

    IF retried_reservation.is_replay
       OR retried_reservation.attempt_count <> 2
       OR retried_reservation.reservation_id
            <> first_reservation.reservation_id
       OR retried_reservation.lease_token
            = first_reservation.lease_token THEN
        RAISE EXCEPTION 'refunded idempotency key was not safely re-reserved';
    END IF;

    IF NOT public.finalize_ai_quota_reservation(
        retried_reservation.reservation_id,
        test_user_id,
        retried_reservation.lease_token,
        'committed'
    ) THEN
        RAISE EXCEPTION 'commit finalization returned false';
    END IF;

    IF NOT public.finalize_ai_quota_reservation(
        retried_reservation.reservation_id,
        test_user_id,
        retried_reservation.lease_token,
        'failed'
    ) THEN
        RAISE EXCEPTION 'failed finalization returned false';
    END IF;

    UPDATE public.users
    SET subscription_tier = 'pro'
    WHERE id = test_user_id;

    SELECT users.entitlement_version
    INTO updated_entitlement_version
    FROM public.users AS users
    WHERE users.id = test_user_id;

    IF updated_entitlement_version <> initial_entitlement_version + 1 THEN
        RAISE EXCEPTION 'entitlement version did not advance atomically';
    END IF;

    SELECT *
    INTO STRICT replayed_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        request_id,
        pg_catalog.REPEAT('a', 64)
    );

    IF replayed_reservation.is_replay
       OR replayed_reservation.attempt_count <> 3
       OR replayed_reservation.lease_token
            = retried_reservation.lease_token
       OR replayed_reservation.effective_plan <> 'pro_paid' THEN
        RAISE EXCEPTION 'failed provider attempt was not safely re-reserved';
    END IF;

    BEGIN
        PERFORM public.finalize_ai_quota_reservation(
            replayed_reservation.reservation_id,
            test_user_id,
            retried_reservation.lease_token,
            'committed'
        );
        RAISE EXCEPTION 'stale lease token unexpectedly finalized a retry';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_quota_finalization_conflict' THEN
                RAISE;
            END IF;
    END;

    IF NOT public.finalize_ai_quota_reservation(
        replayed_reservation.reservation_id,
        test_user_id,
        replayed_reservation.lease_token,
        'refunded'
    ) THEN
        RAISE EXCEPTION 'retry cleanup refund returned false';
    END IF;

    SELECT *
    INTO STRICT stale_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_group_tag_enrichment',
        second_request_id,
        pg_catalog.REPEAT('a', 64)
    );

    UPDATE internal.ai_quota_reservations AS reservations
    SET lease_expires_at = pg_catalog.NOW() - INTERVAL '1 second'
    WHERE reservations.id = stale_reservation.reservation_id;

    IF internal.refund_expired_ai_quota_reservations(10) <> 1 THEN
        RAISE EXCEPTION 'expired reservation cleanup did not refund one lease';
    END IF;
    IF (
        SELECT reservations.state
        FROM internal.ai_quota_reservations AS reservations
        WHERE reservations.id = stale_reservation.reservation_id
    ) <> 'refunded' OR EXISTS (
        SELECT 1
        FROM internal.ai_quota_reservation_counters AS links
        WHERE links.reservation_id = stale_reservation.reservation_id
    ) THEN
        RAISE EXCEPTION 'expired reservation retained state or counter links';
    END IF;

    SELECT *
    INTO STRICT recovered_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_group_tag_enrichment',
        second_request_id,
        pg_catalog.REPEAT('a', 64)
    );
    IF recovered_reservation.is_replay
       OR recovered_reservation.attempt_count <> 2
       OR recovered_reservation.lease_token = stale_reservation.lease_token THEN
        RAISE EXCEPTION 'expired reservation was not safely recoverable';
    END IF;
    PERFORM public.finalize_ai_quota_reservation(
        recovered_reservation.reservation_id,
        test_user_id,
        recovered_reservation.lease_token,
        'refunded'
    );

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM internal.ai_quota_policies AS policies
        WHERE policies.operation IN (
            'scan_identification',
            'scan_audio_identification',
            'scan_overview_enrichment',
            'scan_lookalike_enrichment',
            'scan_group_tag_enrichment',
            'explore_audio_moderation',
            'insight_chat_reply',
            'insight_chat_prompt_suggestions',
            'insight_chat_summary',
            'explore_post_chat_reply',
            'species_dictionary_chat_reply'
        )
    ) <> 44 THEN
        RAISE EXCEPTION 'AI quota policy matrix including complimentary plans is incomplete';
    END IF;
END;
$test$;

SELECT extensions.ok(TRUE, 'AI quota reservation and entitlement boundary is secure');
SELECT * FROM extensions.finish();
ROLLBACK;
