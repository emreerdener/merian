\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-4000-8000-00000000a911';
    paid_user_id UUID := '00000000-0000-4000-8000-00000000a912';
    merge_target_id UUID := '00000000-0000-4000-8000-00000000a913';
    merge_ghost_id UUID := '00000000-0000-4000-8000-00000000a914';
    scan_one UUID := '00000000-0000-4000-8000-00000000b911';
    scan_two UUID := '00000000-0000-4000-8000-00000000b912';
    scan_three UUID := '00000000-0000-4000-8000-00000000b913';
    scan_four UUID := '00000000-0000-4000-8000-00000000b914';
    reservation_one RECORD;
    reservation_two RECORD;
    reservation_three RECORD;
    fallback_reservation RECORD;
    replay_reservation RECORD;
    completion_result JSONB;
    entitlement_row RECORD;
    version_before_cutover BIGINT;
    version_after_cutover BIGINT;
    provider_counter_total_before BIGINT;
    provider_counter_total_after BIGINT;
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.complimentary_scan_usage',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.complimentary_scan_usage',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.complimentary_scan_usage',
        'SELECT'
    ) OR pg_catalog.HAS_COLUMN_PRIVILEGE(
        'authenticated',
        'public.users',
        'complimentary_entitlement_epoch',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION 'complimentary entitlement storage has an unsafe API ACL';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_my_entitlement()',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_my_entitlement()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_user_entitlement_service(uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_entitlement_rollout_service()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_complimentary_scan_states_service(uuid,uuid[])',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_complimentary_scan_states_service(uuid,uuid[])',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'complimentary entitlement routines have unsafe ACLs';
    END IF;

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
        ('00000000-0000-0000-0000-000000000000', test_user_id, 'authenticated', 'authenticated', 'complimentary-test@example.invalid', pg_catalog.NOW(), pg_catalog.NOW(), '{"provider":"email","providers":["email"]}', '{}'::JSONB, pg_catalog.NOW() - INTERVAL '30 days', pg_catalog.NOW(), FALSE),
        ('00000000-0000-0000-0000-000000000000', paid_user_id, 'authenticated', 'authenticated', 'complimentary-paid@example.invalid', pg_catalog.NOW(), pg_catalog.NOW(), '{"provider":"email","providers":["email"]}', '{}'::JSONB, pg_catalog.NOW() - INTERVAL '30 days', pg_catalog.NOW(), FALSE),
        ('00000000-0000-0000-0000-000000000000', merge_target_id, 'authenticated', 'authenticated', 'complimentary-target@example.invalid', pg_catalog.NOW(), pg_catalog.NOW(), '{"provider":"email","providers":["email"]}', '{}'::JSONB, pg_catalog.NOW() - INTERVAL '30 days', pg_catalog.NOW(), FALSE),
        ('00000000-0000-0000-0000-000000000000', merge_ghost_id, 'authenticated', 'authenticated', 'complimentary-ghost@example.invalid', pg_catalog.NOW(), pg_catalog.NOW(), '{"provider":"email","providers":["email"]}', '{}'::JSONB, pg_catalog.NOW() - INTERVAL '30 days', pg_catalog.NOW(), FALSE)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (
        id,
        email,
        public_username,
        public_author_name,
        public_identity_source,
        created_at,
        subscription_tier
    )
    VALUES
        (
            test_user_id,
            'complimentary-test@example.invalid',
            'complimentary_test_a911',
            'Complimentary Test',
            'alias',
            pg_catalog.NOW() - INTERVAL '30 days',
            'free'
        ),
        (
            paid_user_id,
            'complimentary-paid@example.invalid',
            'complimentary_paid_a912',
            'Complimentary Paid Test',
            'alias',
            pg_catalog.NOW() - INTERVAL '30 days',
            'pro'
        ),
        (
            merge_target_id,
            'complimentary-target@example.invalid',
            'complimentary_tgt_a913',
            'Complimentary Target',
            'alias',
            pg_catalog.NOW() - INTERVAL '30 days',
            'free'
        ),
        (
            merge_ghost_id,
            'complimentary-ghost@example.invalid',
            'complimentary_ghost_a914',
            'Complimentary Ghost',
            'alias',
            pg_catalog.NOW() - INTERVAL '30 days',
            'free'
        )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_username = EXCLUDED.public_username,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        created_at = EXCLUDED.created_at,
        subscription_tier = EXCLUDED.subscription_tier;

    SELECT entitlement.entitlement_version
    INTO STRICT version_before_cutover
    FROM internal.resolve_effective_entitlement(test_user_id) AS entitlement;

    UPDATE internal.entitlement_rollout_config
    SET entitlement_mode = 'complimentary',
        required_client_protocol = 2
    WHERE config_key = 'current';

    SELECT entitlement.entitlement_version
    INTO STRICT version_after_cutover
    FROM internal.resolve_effective_entitlement(test_user_id) AS entitlement;

    IF version_after_cutover <> version_before_cutover + 1 THEN
        RAISE EXCEPTION 'global cutover did not monotonically advance every account';
    END IF;

    BEGIN
        PERFORM public.reserve_ai_quota(
            test_user_id,
            'scan_identification',
            '00000000-0000-4000-8000-00000000c910'::UUID,
            pg_catalog.REPEAT('a', 64),
            scan_one,
            TRUE,
            NULL,
            FALSE
        );
        RAISE EXCEPTION 'missing protocol unexpectedly passed after cutover';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'client_update_required' THEN
                RAISE;
            END IF;
    END;

    SELECT * INTO STRICT reservation_one
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        '00000000-0000-4000-8000-00000000c911'::UUID,
        pg_catalog.REPEAT('a', 64),
        scan_one,
        TRUE,
        2,
        FALSE
    );
    SELECT * INTO STRICT reservation_two
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        '00000000-0000-4000-8000-00000000c912'::UUID,
        pg_catalog.REPEAT('a', 64),
        scan_two,
        TRUE,
        2,
        FALSE
    );
    SELECT * INTO STRICT reservation_three
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        '00000000-0000-4000-8000-00000000c913'::UUID,
        pg_catalog.REPEAT('a', 64),
        scan_three,
        TRUE,
        2,
        FALSE
    );

    IF reservation_one.effective_plan <> 'pro_complimentary'
       OR reservation_two.effective_plan <> 'pro_complimentary'
       OR reservation_three.effective_plan <> 'pro_complimentary'
       OR reservation_one.complimentary_client_scan_id <> scan_one
       OR reservation_three.scans_available_to_start <> 0
       OR reservation_three.in_flight_count <> 3
       OR (
            SELECT pg_catalog.COUNT(*)
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = test_user_id
              AND usage.state = 'held'
       ) <> 3 THEN
        RAISE EXCEPTION 'three atomic complimentary holds returned invalid state';
    END IF;

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM public.get_complimentary_scan_states_service(
            test_user_id,
            ARRAY[
                scan_one,
                scan_two,
                scan_three,
                '00000000-0000-4000-8000-00000000ffff'::UUID
            ]
        ) AS funding
        WHERE funding.complimentary_state = 'held'
    ) <> 3 THEN
        RAISE EXCEPTION 'owner-scoped bulk funding-state read returned invalid rows';
    END IF;

    SELECT * INTO STRICT replay_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        reservation_one.request_id,
        pg_catalog.REPEAT('a', 64),
        scan_one,
        TRUE,
        NULL,
        TRUE
    );
    IF NOT replay_reservation.is_replay
       OR replay_reservation.reservation_id <> reservation_one.reservation_id
       OR replay_reservation.complimentary_client_scan_id <> scan_one THEN
        RAISE EXCEPTION 'internal replay did not reuse its original analysis';
    END IF;

    SELECT * INTO STRICT fallback_reservation
    FROM public.reserve_ai_quota(
        test_user_id,
        'scan_identification',
        '00000000-0000-4000-8000-00000000c914'::UUID,
        pg_catalog.REPEAT('a', 64),
        scan_four,
        TRUE,
        2,
        FALSE
    );
    IF fallback_reservation.effective_plan <> 'free'
       OR fallback_reservation.model <> 'gemini-2.5-flash'
       OR NOT fallback_reservation.flash_fallback_used
       OR fallback_reservation.daily_remaining <> 0
       OR EXISTS (
            SELECT 1
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = test_user_id
              AND usage.client_scan_id = scan_four
       ) THEN
        RAISE EXCEPTION 'fourth compatible scan did not use the separate daily Flash policy';
    END IF;

    BEGIN
        PERFORM public.reserve_ai_quota(
            test_user_id,
            'scan_identification',
            '00000000-0000-4000-8000-00000000c915'::UUID,
            pg_catalog.REPEAT('a', 64),
            '00000000-0000-4000-8000-00000000b915'::UUID,
            FALSE,
            2,
            FALSE
        );
        RAISE EXCEPTION 'exhausted Pro-only scan unexpectedly fell back';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_entitlement_required' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        PERFORM public.reserve_ai_quota(
            test_user_id,
            'scan_identification',
            '00000000-0000-4000-8000-00000000c916'::UUID,
            pg_catalog.REPEAT('a', 64),
            '00000000-0000-4000-8000-00000000b916'::UUID,
            TRUE,
            2,
            FALSE
        );
        RAISE EXCEPTION 'second daily Flash scan unexpectedly succeeded';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'ai_quota_daily_exceeded' THEN
                RAISE;
            END IF;
    END;

    PERFORM public.finalize_ai_quota_reservation(
        reservation_one.reservation_id,
        test_user_id,
        reservation_one.lease_token,
        'committed'
    );
    PERFORM public.finalize_ai_quota_reservation(
        reservation_one.reservation_id,
        test_user_id,
        reservation_one.lease_token,
        'failed'
    );
    IF (
        SELECT usage.state
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = test_user_id
          AND usage.client_scan_id = scan_one
    ) <> 'held' THEN
        RAISE EXCEPTION 'ambiguous/provider failure incorrectly released a hold';
    END IF;

    SELECT COALESCE(pg_catalog.SUM(counters.request_count), 0)
    INTO STRICT provider_counter_total_before
    FROM internal.ai_quota_counters AS counters
    WHERE counters.scope_key IN (
        test_user_id::TEXT,
        pg_catalog.REPEAT('a', 64)
    );

    INSERT INTO public.scan_ingestion_jobs (
        scan_id,
        user_id,
        endpoint,
        status,
        stage
    ) VALUES (
        scan_one::TEXT,
        test_user_id,
        'identify',
        'processing',
        'ai_inference_started'
    );
    BEGIN
        UPDATE public.scan_ingestion_jobs AS jobs
        SET status = 'failed_terminal',
            stage = 'provider_terminal_failure'
        WHERE jobs.scan_id = scan_one::TEXT
          AND jobs.user_id = test_user_id;
        RAISE EXCEPTION
            'lower-level terminal settlement unexpectedly bypassed the orchestrator';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            IF SQLERRM <>
                    'complimentary_terminal_requires_orchestrator' THEN
                RAISE;
            END IF;
    END;

    PERFORM public.fail_scan_ingestion_terminal(
        scan_one,
        test_user_id,
        'provider_terminal_failure',
        'provider rejected request',
        'provider_terminal_failure'
    );
    SELECT COALESCE(pg_catalog.SUM(counters.request_count), 0)
    INTO STRICT provider_counter_total_after
    FROM internal.ai_quota_counters AS counters
    WHERE counters.scope_key IN (
        test_user_id::TEXT,
        pg_catalog.REPEAT('a', 64)
    );
    IF (
        SELECT usage.state = 'released'
            AND usage.settlement_reason = 'provider_terminal_failure'
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = test_user_id
          AND usage.client_scan_id = scan_one
    ) IS DISTINCT FROM TRUE
       OR provider_counter_total_after <>
            provider_counter_total_before THEN
        RAISE EXCEPTION 'terminal release erased provider quota accounting';
    END IF;

    -- An already-durable fixture lets the public completion orchestrator prove
    -- that a valid non-biological result consumes exactly one held credit.
    INSERT INTO public.scans (
        id,
        user_id,
        ai_confidence_score,
        timestamp,
        is_biological_subject
    ) VALUES (scan_two, test_user_id, 0.2, pg_catalog.NOW(), FALSE);
    PERFORM pg_catalog.SET_CONFIG(
        'merian.scan_ingestion_completion_fence',
        test_user_id::TEXT || ':' || scan_two::TEXT,
        TRUE
    );
    PERFORM pg_catalog.SET_CONFIG(
        'merian.complimentary_completion_fence',
        test_user_id::TEXT || ':' || scan_two::TEXT,
        TRUE
    );
    INSERT INTO public.scan_ingestion_jobs (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        completed_at
    ) VALUES (
        scan_two::TEXT,
        test_user_id,
        'identify-describe',
        'complete',
        'media_finalization_complete',
        pg_catalog.NOW()
    );

    SELECT public.complete_scan_ingestion_with_entitlement(
        scan_two,
        test_user_id,
        pg_catalog.JSONB_BUILD_OBJECT(
            'success', TRUE,
            'data', pg_catalog.JSONB_BUILD_OBJECT('scan_id', scan_two)
        ),
        '{}'::JSONB,
        '{}'::TEXT[]
    ) INTO STRICT completion_result;
    IF completion_result #>> '{entitlement,user_id}' <> test_user_id::TEXT
       OR completion_result #>> '{entitlement,plan_used}' <> 'pro_complimentary'
       OR (completion_result #>> '{entitlement,credit_consumed}')::BOOLEAN
            IS DISTINCT FROM TRUE
       OR (
            SELECT usage.state
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = test_user_id
              AND usage.client_scan_id = scan_two
       ) <> 'consumed' THEN
        RAISE EXCEPTION 'valid non-biological completion did not consume its hold';
    END IF;

    -- Purchase before final settlement releases rather than consumes the hold.
    UPDATE public.users
    SET subscription_tier = 'pro'
    WHERE id = test_user_id;
    INSERT INTO public.scans (
        id,
        user_id,
        ai_confidence_score,
        timestamp,
        is_biological_subject
    ) VALUES (scan_three, test_user_id, 0.8, pg_catalog.NOW(), TRUE);
    PERFORM pg_catalog.SET_CONFIG(
        'merian.scan_ingestion_completion_fence',
        test_user_id::TEXT || ':' || scan_three::TEXT,
        TRUE
    );
    PERFORM pg_catalog.SET_CONFIG(
        'merian.complimentary_completion_fence',
        test_user_id::TEXT || ':' || scan_three::TEXT,
        TRUE
    );
    INSERT INTO public.scan_ingestion_jobs (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        completed_at
    ) VALUES (
        scan_three::TEXT,
        test_user_id,
        'identify',
        'complete',
        'media_finalization_complete',
        pg_catalog.NOW()
    );
    PERFORM public.complete_scan_ingestion_with_entitlement(
        scan_three,
        test_user_id,
        pg_catalog.JSONB_BUILD_OBJECT(
            'success', TRUE,
            'data', pg_catalog.JSONB_BUILD_OBJECT('scan_id', scan_three)
        ),
        '{}'::JSONB,
        '{}'::TEXT[]
    );
    IF (
        SELECT usage.state = 'released'
            AND usage.settlement_reason = 'paid_before_completion'
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = test_user_id
          AND usage.client_scan_id = scan_three
    ) IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'purchase-before-settlement did not preserve the credit';
    END IF;

    SELECT * INTO STRICT replay_reservation
    FROM public.reserve_ai_quota(
        paid_user_id,
        'scan_identification',
        '00000000-0000-4000-8000-00000000c920'::UUID,
        pg_catalog.REPEAT('b', 64),
        '00000000-0000-4000-8000-00000000b920'::UUID,
        FALSE,
        2,
        FALSE
    );
    IF replay_reservation.effective_plan <> 'pro_paid'
       OR EXISTS (
            SELECT 1
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = paid_user_id
       ) THEN
        RAISE EXCEPTION 'paid scan changed complimentary-credit history';
    END IF;

    INSERT INTO internal.complimentary_scan_usage (
        user_id,
        client_scan_id,
        state,
        held_at,
        settled_at,
        settlement_reason,
        created_at,
        updated_at
    ) VALUES
        (merge_target_id, '00000000-0000-4000-8000-00000000d911', 'consumed', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day', 'durable_result_complete', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day'),
        (merge_target_id, '00000000-0000-4000-8000-00000000d912', 'consumed', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day', 'durable_result_complete', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day'),
        (merge_target_id, '00000000-0000-4000-8000-00000000d915', 'held', pg_catalog.NOW() - INTERVAL '1 hour', NULL, NULL, pg_catalog.NOW() - INTERVAL '1 hour', pg_catalog.NOW() - INTERVAL '1 hour'),
        (merge_ghost_id, '00000000-0000-4000-8000-00000000d911', 'released', pg_catalog.NOW() - INTERVAL '3 days', pg_catalog.NOW() - INTERVAL '2 days', 'provider_terminal_failure', pg_catalog.NOW() - INTERVAL '3 days', pg_catalog.NOW() - INTERVAL '2 days'),
        (merge_ghost_id, '00000000-0000-4000-8000-00000000d913', 'consumed', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day', 'durable_result_complete', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day'),
        (merge_ghost_id, '00000000-0000-4000-8000-00000000d914', 'consumed', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day', 'durable_result_complete', pg_catalog.NOW() - INTERVAL '2 days', pg_catalog.NOW() - INTERVAL '1 day'),
        (merge_ghost_id, '00000000-0000-4000-8000-00000000d916', 'held', pg_catalog.NOW() - INTERVAL '30 minutes', NULL, NULL, pg_catalog.NOW() - INTERVAL '30 minutes', pg_catalog.NOW() - INTERVAL '30 minutes');

    PERFORM internal.merge_ghost_complimentary_scan_usage(
        merge_ghost_id,
        merge_target_id
    );
    SELECT entitlement.* INTO STRICT entitlement_row
    FROM internal.resolve_effective_entitlement(merge_target_id) AS entitlement;
    IF EXISTS (
        SELECT 1
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = merge_ghost_id
    ) OR (
        SELECT pg_catalog.COUNT(*)
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = merge_target_id
          AND usage.state = 'consumed'
    ) <> 4 OR EXISTS (
        SELECT 1
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = merge_target_id
          AND usage.state = 'held'
    ) OR entitlement_row.scans_remaining <> 0
       OR entitlement_row.scans_available_to_start <> 0 THEN
        RAISE EXCEPTION 'merge added grants, lost consumption, or retained excess holds';
    END IF;

    UPDATE internal.entitlement_rollout_config
    SET required_client_protocol = 3
    WHERE config_key = 'current'
      AND entitlement_mode = 'complimentary';

    BEGIN
        PERFORM public.reserve_ai_quota(
            paid_user_id,
            'scan_identification',
            '00000000-0000-4000-8000-00000000cf21'::UUID,
            pg_catalog.REPEAT('a', 64),
            '00000000-0000-4000-8000-00000000bf21'::UUID,
            TRUE,
            2,
            FALSE
        );
        RAISE EXCEPTION 'protocol 2 unexpectedly passed after protocol-3 cutover';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'client_update_required' THEN
                RAISE;
            END IF;
    END;

    PERFORM public.reserve_ai_quota(
        paid_user_id,
        'scan_identification',
        '00000000-0000-4000-8000-00000000cf22'::UUID,
        pg_catalog.REPEAT('a', 64),
        '00000000-0000-4000-8000-00000000bf22'::UUID,
        TRUE,
        3,
        FALSE
    );
END;
$test$;

SELECT extensions.ok(
    TRUE,
    'three complimentary Pro scans, separate Flash quota, settlement, paid preservation, merge cap, versions, and ACLs hold'
);
SELECT * FROM extensions.finish();
ROLLBACK;
