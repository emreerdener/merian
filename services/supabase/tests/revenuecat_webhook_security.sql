\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    destination_user_id UUID := '00000000-0000-0000-0000-00000000b401';
    source_user_id UUID := '00000000-0000-0000-0000-00000000b402';
    missing_user_id UUID := '00000000-0000-0000-0000-00000000b403';
    initial_entitlement_version BIGINT;
    transition RECORD;
    receipt RECORD;
    replay RECORD;
    stale_transition RECORD;
    refund_transition RECORD;
    delayed_purchase RECORD;
    transfer_transition RECORD;
    deleted_source_transfer RECORD;
    stored_tier public.subscription_tier_enum;
    stored_expiry TIMESTAMPTZ;
    stored_version BIGINT;
    reconciliation_claim RECORD;
    reconciliation_applied BOOLEAN;
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'RevenueCat state RPC has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_revenuecat_webhook_event_result(text,bigint,text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_revenuecat_webhook_event_result(text,bigint,text,text)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_revenuecat_webhook_event_result(text,bigint,text,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'RevenueCat duplicate lookup has an unsafe ACL';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.revenuecat_webhook_events',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.revenuecat_customer_state',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.revenuecat_webhook_event_subjects',
        'INSERT'
    ) THEN
        RAISE EXCEPTION 'RevenueCat internals are directly exposed';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.revenuecat_reconciliation_queue',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.revenuecat_reconciliation_queue',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.revenuecat_reconciliation_queue',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'RevenueCat reconciliation queue is directly exposed';
    END IF;

    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.claim_revenuecat_reconciliations(integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_revenuecat_reconciliations(integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'RevenueCat reconciliation RPC has an unsafe ACL';
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
    SELECT
        '00000000-0000-0000-0000-000000000000'::UUID,
        seed.user_id,
        'authenticated',
        'authenticated',
        seed.email,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW() - INTERVAL '30 days',
        pg_catalog.NOW(),
        FALSE
    FROM (
        VALUES
            (
                destination_user_id,
                'revenuecat-destination-test@example.invalid'
            ),
            (
                source_user_id,
                'revenuecat-source-test@example.invalid'
            )
    ) AS seed(user_id, email);

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
        destination_user_id,
        'revenuecat-destination-test@example.invalid',
        'rc_destination_b401',
        'RevenueCat Destination Test',
        'alias',
        NOW() - INTERVAL '30 days',
        'free'
    ), (
        source_user_id,
        'revenuecat-source-test@example.invalid',
        'rc_source_b402',
        'RevenueCat Source Test',
        'alias',
        NOW() - INTERVAL '30 days',
        'pro'
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        public_username = EXCLUDED.public_username,
        public_author_name = EXCLUDED.public_author_name,
        public_identity_source = EXCLUDED.public_identity_source,
        created_at = EXCLUDED.created_at,
        subscription_tier = EXCLUDED.subscription_tier;

    SELECT users.entitlement_version
    INTO STRICT initial_entitlement_version
    FROM public.users AS users
    WHERE users.id = destination_user_id;

    SELECT *
    INTO STRICT transition
    FROM public.apply_revenuecat_customer_state(
        'event-renewal',
        2000,
        'RENEWAL',
        pg_catalog.REPEAT('a', 64),
        4,
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'customer',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                'authoritative_snapshot_at_ms', 3000,
                'target_tier', 'pro',
                'target_expires_at', NULL
            )
        )
    );

    IF transition.outcome <> 'applied'
       OR transition.subject_count <> 1
       OR transition.applied_count <> 1
       OR transition.stale_count <> 0 THEN
        RAISE EXCEPTION 'authoritative renewal was not applied atomically';
    END IF;

    SELECT *
    INTO STRICT receipt
    FROM public.get_revenuecat_webhook_event_result(
        'event-renewal',
        2000,
        'RENEWAL',
        pg_catalog.REPEAT('a', 64)
    );

    IF receipt.outcome <> 'duplicate'
       OR receipt.subject_count <> 1
       OR receipt.applied_count <> 1
       OR receipt.stale_count <> 0 THEN
        RAISE EXCEPTION 'durable duplicate lookup returned the wrong receipt';
    END IF;

    SELECT *
    INTO STRICT replay
    FROM public.apply_revenuecat_customer_state(
        'event-renewal',
        2000,
        'RENEWAL',
        pg_catalog.REPEAT('a', 64),
        10,
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'customer',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                'authoritative_snapshot_at_ms', 9000,
                'target_tier', 'free',
                'target_expires_at', NULL
            )
        )
    );

    IF replay.outcome <> 'duplicate'
       OR replay.applied_count <> 1 THEN
        RAISE EXCEPTION 'duplicate event id was not idempotent';
    END IF;

    SELECT *
    INTO STRICT stale_transition
    FROM public.apply_revenuecat_customer_state(
        'event-delayed-expiration',
        1000,
        'EXPIRATION',
        pg_catalog.REPEAT('b', 64),
        11,
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'customer',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                'authoritative_snapshot_at_ms', 10000,
                'target_tier', 'free',
                'target_expires_at', NULL
            )
        )
    );

    IF stale_transition.outcome <> 'applied'
       OR stale_transition.applied_count <> 1 THEN
        RAISE EXCEPTION
            'newer authoritative snapshot was discarded by older event time';
    END IF;

    SELECT
        users.subscription_tier,
        users.subscription_expires_at,
        users.entitlement_version
    INTO STRICT stored_tier, stored_expiry, stored_version
    FROM public.users AS users
    WHERE users.id = destination_user_id;

    IF stored_tier <> 'free'::public.subscription_tier_enum
       OR stored_expiry IS NOT NULL
       OR stored_version <> initial_entitlement_version + 2 THEN
        RAISE EXCEPTION 'authoritative delayed snapshot did not replace renewal';
    END IF;

    SELECT *
    INTO STRICT refund_transition
    FROM public.apply_revenuecat_customer_state(
        'event-refund',
        4000,
        'REFUND',
        pg_catalog.REPEAT('c', 64),
        6,
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'customer',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                'authoritative_snapshot_at_ms', 5000,
                'target_tier', 'free',
                'target_expires_at', NULL
            )
        )
    );

    IF refund_transition.outcome <> 'stale'
       OR refund_transition.stale_count <> 1 THEN
        RAISE EXCEPTION 'older authoritative refund snapshot was not stale';
    END IF;

    SELECT *
    INTO STRICT delayed_purchase
    FROM public.apply_revenuecat_customer_state(
        'event-delayed-purchase',
        3500,
        'INITIAL_PURCHASE',
        pg_catalog.REPEAT('d', 64),
        9,
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'customer',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                'authoritative_snapshot_at_ms', 8000,
                'target_tier', 'pro',
                'target_expires_at', NULL
            )
        )
    );

    IF delayed_purchase.outcome <> 'stale' THEN
        RAISE EXCEPTION 'delayed purchase restored access after refund';
    END IF;

    SELECT
        users.subscription_tier,
        users.entitlement_version
    INTO STRICT stored_tier, stored_version
    FROM public.users AS users
    WHERE users.id = destination_user_id;

    IF stored_tier <> 'free'::public.subscription_tier_enum
       OR stored_version <> initial_entitlement_version + 2 THEN
        RAISE EXCEPTION 'refund state was not monotonic';
    END IF;

    -- RevenueCat sends only TRANSFER for the source/destination move. Both
    -- CustomerInfo snapshots must therefore commit under one event ID.
    SELECT *
    INTO STRICT transfer_transition
    FROM public.apply_revenuecat_customer_state(
        'event-transfer',
        6000,
        'TRANSFER',
        pg_catalog.REPEAT('e', 64),
        7,
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'transfer_source',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(source_user_id),
                'authoritative_snapshot_at_ms', 11000,
                'target_tier', 'free',
                'target_expires_at', NULL
            ),
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'transfer_destination',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                'authoritative_snapshot_at_ms', 11000,
                'target_tier', 'pro',
                'target_expires_at', NULL
            )
        )
    );

    IF transfer_transition.outcome <> 'applied'
       OR transfer_transition.subject_count <> 2
       OR transfer_transition.applied_count <> 2 THEN
        RAISE EXCEPTION 'transfer did not atomically reconcile both users';
    END IF;

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM public.users AS users
        WHERE (
            users.id = source_user_id
            AND users.subscription_tier =
                'free'::public.subscription_tier_enum
        ) OR (
            users.id = destination_user_id
            AND users.subscription_tier =
                'pro'::public.subscription_tier_enum
        )
    ) <> 2 THEN
        RAISE EXCEPTION 'transfer left source/destination access inconsistent';
    END IF;

    SELECT *
    INTO STRICT deleted_source_transfer
    FROM public.apply_revenuecat_customer_state(
        'event-transfer-deleted-source',
        7000,
        'TRANSFER',
        pg_catalog.REPEAT('f', 64),
        8,
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'transfer_source',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(missing_user_id),
                'authoritative_snapshot_at_ms', 12000,
                'target_tier', 'free',
                'target_expires_at', NULL
            ),
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'transfer_destination',
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                'authoritative_snapshot_at_ms', 12000,
                'target_tier', 'pro',
                'target_expires_at', NULL
            )
        )
    );

    IF deleted_source_transfer.outcome <> 'applied'
       OR deleted_source_transfer.subject_count <> 1
       OR deleted_source_transfer.applied_count <> 1 THEN
        RAISE EXCEPTION 'deleted transfer source blocked live destination';
    END IF;

    BEGIN
        PERFORM public.apply_revenuecat_customer_state(
            'event-renewal',
            2000,
            'RENEWAL',
            pg_catalog.REPEAT('2', 64),
            10,
            '[]'::JSONB
        );
        RAISE EXCEPTION 'conflicting reuse of an event id succeeded';
    EXCEPTION
        WHEN unique_violation THEN
            IF SQLERRM <> 'revenuecat_event_id_conflict' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        PERFORM public.apply_revenuecat_customer_state(
            'event-missing-user',
            7000,
            'RENEWAL',
            pg_catalog.REPEAT('0', 64),
            8,
            pg_catalog.JSONB_BUILD_ARRAY(
                pg_catalog.JSONB_BUILD_OBJECT(
                    'subject_kind', 'customer',
                    'candidate_user_ids',
                        pg_catalog.JSONB_BUILD_ARRAY(missing_user_id),
                    'authoritative_snapshot_at_ms', 8000,
                    'target_tier', 'pro',
                    'target_expires_at', NULL
                )
            )
        );
        RAISE EXCEPTION 'missing public user was synthesized by billing';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'revenuecat_user_not_found' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        PERFORM public.apply_revenuecat_customer_state(
            'event-ambiguous-user',
            8000,
            'RENEWAL',
            pg_catalog.REPEAT('1', 64),
            9,
            pg_catalog.JSONB_BUILD_ARRAY(
                pg_catalog.JSONB_BUILD_OBJECT(
                    'subject_kind', 'customer',
                    'candidate_user_ids',
                        pg_catalog.JSONB_BUILD_ARRAY(
                            source_user_id,
                            destination_user_id
                        ),
                    'authoritative_snapshot_at_ms', 9000,
                    'target_tier', 'pro',
                    'target_expires_at', NULL
                )
            )
        );
        RAISE EXCEPTION 'ambiguous customer mapping changed an entitlement';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'revenuecat_user_mapping_ambiguous' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        PERFORM public.apply_revenuecat_customer_state(
            'event-invalid-shape',
            9000,
            'RENEWAL',
            pg_catalog.REPEAT('3', 64),
            10,
            pg_catalog.JSONB_BUILD_ARRAY(
                pg_catalog.JSONB_BUILD_OBJECT(
                    'subject_kind', 'customer',
                    'candidate_user_ids',
                        pg_catalog.JSONB_BUILD_ARRAY(source_user_id),
                    'authoritative_snapshot_at_ms', 10000,
                    'target_tier', 'free',
                    'target_expires_at', NULL
                ),
                pg_catalog.JSONB_BUILD_OBJECT(
                    'subject_kind', 'customer',
                    'candidate_user_ids',
                        pg_catalog.JSONB_BUILD_ARRAY(destination_user_id),
                    'authoritative_snapshot_at_ms', 10000,
                    'target_tier', 'pro',
                    'target_expires_at', NULL
                )
            )
        );
        RAISE EXCEPTION 'non-transfer event accepted multiple user subjects';
    EXCEPTION
        WHEN invalid_parameter_value THEN
            IF SQLERRM <> 'revenuecat_invalid_customer_state' THEN
                RAISE;
        END IF;
    END;

    PERFORM public.schedule_revenuecat_reconciliation(
        pg_catalog.JSONB_BUILD_ARRAY(
            pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'customer',
                'lookup_app_user_id', destination_user_id::TEXT,
                'candidate_user_ids',
                    pg_catalog.JSONB_BUILD_ARRAY(destination_user_id)
            )
        )
    );

    UPDATE internal.revenuecat_reconciliation_queue AS queue
    SET next_reconcile_at = pg_catalog.NOW()
    WHERE queue.merian_user_id = destination_user_id;

    SELECT *
    INTO STRICT reconciliation_claim
    FROM public.claim_revenuecat_reconciliations(1);

    reconciliation_applied := public.apply_revenuecat_reconciliation(
        reconciliation_claim.user_id,
        reconciliation_claim.claim_token,
        13000,
        'free',
        NULL
    );

    IF reconciliation_applied IS NOT TRUE OR NOT EXISTS (
        SELECT 1
        FROM public.users AS users
        JOIN internal.revenuecat_customer_state AS state
          ON state.merian_user_id = users.id
        JOIN internal.revenuecat_reconciliation_queue AS queue
          ON queue.merian_user_id = users.id
        WHERE users.id = destination_user_id
          AND users.subscription_tier =
                'free'::public.subscription_tier_enum
          AND state.last_authoritative_snapshot_at_ms = 13000
          AND queue.claim_token IS NULL
          AND queue.last_snapshot_at_ms = 13000
          AND queue.next_reconcile_at > pg_catalog.NOW()
    ) THEN
        RAISE EXCEPTION
            'periodic reconciliation did not atomically apply and release';
    END IF;

    UPDATE internal.revenuecat_reconciliation_queue AS queue
    SET next_reconcile_at = pg_catalog.NOW()
    WHERE queue.merian_user_id = destination_user_id;

    SELECT *
    INTO STRICT reconciliation_claim
    FROM public.claim_revenuecat_reconciliations(1);

    reconciliation_applied := public.apply_revenuecat_reconciliation(
        reconciliation_claim.user_id,
        reconciliation_claim.claim_token,
        12500,
        'pro',
        NULL
    );

    IF reconciliation_applied IS NOT FALSE OR (
        SELECT users.subscription_tier
        FROM public.users AS users
        WHERE users.id = destination_user_id
    ) <> 'free'::public.subscription_tier_enum THEN
        RAISE EXCEPTION
            'stale periodic snapshot restored an older entitlement';
    END IF;

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM internal.revenuecat_webhook_events AS events
    ) <> 6 OR (
        SELECT pg_catalog.COUNT(*)
        FROM internal.revenuecat_webhook_event_subjects AS subjects
        WHERE subjects.merian_user_id = destination_user_id
    ) <> 6 THEN
        RAISE EXCEPTION 'RevenueCat event ledger lost idempotency';
    END IF;
END;
$test$;

SELECT extensions.pass(
    'RevenueCat deliveries are idempotent, ordered, transferred atomically, and service-owned'
);
SELECT * FROM extensions.finish();
ROLLBACK;
