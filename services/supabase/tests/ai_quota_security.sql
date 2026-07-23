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
        'public.finalize_ai_quota_reservation(uuid,uuid,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.finalize_ai_quota_reservation(uuid,uuid,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.finalize_ai_quota_reservation(uuid,uuid,text)',
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
        RAISE EXCEPTION 'missing user unexpectedly received AI entitlement';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_entitlement_unavailable' THEN
                RAISE;
            END IF;
    END;

    INSERT INTO public.users (
        id,
        email,
        created_at,
        subscription_tier
    )
    VALUES (
        test_user_id,
        'ai-quota-test@example.invalid',
        NOW() - INTERVAL '30 days',
        'free'
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
        'refunded'
    ) THEN
        RAISE EXCEPTION 'refund finalization returned false';
    END IF;

    BEGIN
        PERFORM public.finalize_ai_quota_reservation(
            first_reservation.reservation_id,
            test_user_id,
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
            <> first_reservation.reservation_id THEN
        RAISE EXCEPTION 'refunded idempotency key was not safely re-reserved';
    END IF;

    IF NOT public.finalize_ai_quota_reservation(
        retried_reservation.reservation_id,
        test_user_id,
        'committed'
    ) THEN
        RAISE EXCEPTION 'commit finalization returned false';
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

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM internal.ai_quota_policies AS policies
        WHERE policies.operation IN (
            'scan_identification',
            'scan_audio_identification',
            'scan_overview_enrichment',
            'scan_lookalike_enrichment',
            'explore_audio_moderation',
            'insight_chat_reply',
            'insight_chat_prompt_suggestions',
            'insight_chat_summary',
            'explore_post_chat_reply'
        )
    ) <> 27 THEN
        RAISE EXCEPTION 'AI quota policy matrix is incomplete';
    END IF;
END;
$test$;

SELECT extensions.ok(TRUE, 'AI quota reservation and entitlement boundary is secure');
SELECT * FROM extensions.finish();
ROLLBACK;
