-- Preserve StoreKit-backed purchase continuity across a real user sign-out.
-- The linked source issues a one-use proof before its local session closes;
-- one fresh anonymous destination binds that proof, synchronizes the receipt
-- through RevenueCat, and then durably schedules authoritative reconciliation
-- for both identities. This protocol never moves account data and never clones
-- account-bound promotional entitlements.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE TABLE internal.signout_purchase_handoffs (
    id UUID PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
    source_user_id UUID NOT NULL,
    destination_user_id UUID,
    secret_hash TEXT NOT NULL UNIQUE,
    source_snapshot_at_ms BIGINT NOT NULL,
    expected_store_tier TEXT NOT NULL,
    expected_store_expires_at TIMESTAMPTZ,
    destination_verified_snapshot_at_ms BIGINT,
    destination_verified_store_tier TEXT,
    destination_verified_store_expires_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'prepared',
    expires_at TIMESTAMPTZ NOT NULL,
    bound_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT signout_purchase_handoff_secret_check CHECK (
        secret_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT signout_purchase_handoff_snapshot_check CHECK (
        source_snapshot_at_ms BETWEEN 0 AND 253402300799999
        AND (
            destination_verified_snapshot_at_ms IS NULL
            OR destination_verified_snapshot_at_ms BETWEEN
                source_snapshot_at_ms AND 253402300799999
        )
    ),
    CONSTRAINT signout_purchase_handoff_store_access_check CHECK (
        expected_store_tier IN ('free', 'pro')
        AND (
            expected_store_tier = 'pro'
            OR expected_store_expires_at IS NULL
        )
        AND (
            expected_store_expires_at IS NULL
            OR expected_store_expires_at > pg_catalog.TO_TIMESTAMP(
                source_snapshot_at_ms::DOUBLE PRECISION / 1000.0
            )
        )
    ),
    CONSTRAINT signout_purchase_handoff_verified_store_access_check CHECK (
        destination_verified_store_tier IS NULL
        OR (
            destination_verified_store_tier IN ('free', 'pro')
            AND (
                destination_verified_store_tier = 'pro'
                OR destination_verified_store_expires_at IS NULL
            )
            AND (
                destination_verified_store_expires_at IS NULL
                OR destination_verified_store_expires_at >
                    pg_catalog.TO_TIMESTAMP(
                        destination_verified_snapshot_at_ms::DOUBLE PRECISION /
                            1000.0
                    )
            )
        )
    ),
    CONSTRAINT signout_purchase_handoff_status_check CHECK (
        status IN (
            'prepared',
            'bound',
            'completed',
            'superseded',
            'expired'
        )
    ),
    CONSTRAINT signout_purchase_handoff_expiry_check CHECK (
        expires_at > created_at
    ),
    CONSTRAINT signout_purchase_handoff_state_check CHECK (
        (
            status IN ('prepared', 'superseded', 'expired')
            AND destination_user_id IS NULL
            AND destination_verified_snapshot_at_ms IS NULL
            AND destination_verified_store_tier IS NULL
            AND destination_verified_store_expires_at IS NULL
            AND bound_at IS NULL
            AND completed_at IS NULL
        )
        OR (
            status = 'bound'
            AND destination_user_id IS NOT NULL
            AND destination_verified_snapshot_at_ms IS NULL
            AND destination_verified_store_tier IS NULL
            AND destination_verified_store_expires_at IS NULL
            AND bound_at IS NOT NULL
            AND completed_at IS NULL
        )
        OR (
            status = 'completed'
            AND destination_user_id IS NOT NULL
            AND destination_verified_snapshot_at_ms IS NOT NULL
            AND destination_verified_store_tier IS NOT NULL
            AND bound_at IS NOT NULL
            AND completed_at IS NOT NULL
        )
    )
);

CREATE UNIQUE INDEX signout_purchase_handoff_one_active_source_idx
    ON internal.signout_purchase_handoffs (source_user_id)
    WHERE status IN ('prepared', 'bound');

CREATE UNIQUE INDEX signout_purchase_handoff_one_destination_idx
    ON internal.signout_purchase_handoffs (destination_user_id)
    WHERE status IN ('bound', 'completed');

CREATE INDEX signout_purchase_handoff_expiry_idx
    ON internal.signout_purchase_handoffs (expires_at, id)
    WHERE status IN ('prepared', 'bound');

CREATE INDEX signout_purchase_handoff_pending_age_idx
    ON internal.signout_purchase_handoffs (created_at, id)
    WHERE status IN ('prepared', 'bound');

ALTER TABLE internal.signout_purchase_handoffs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.signout_purchase_handoffs
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.signout_purchase_handoffs IS
    'Private one-use proofs binding a linked sign-out source to one fresh anonymous purchase destination without moving account data or promotional grants.';

CREATE OR REPLACE FUNCTION public.issue_signout_purchase_handoff(
    p_source_user_id UUID,
    p_secret_hash TEXT,
    p_source_snapshot_at_ms BIGINT,
    p_expected_store_tier TEXT,
    p_expected_store_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    handoff_id UUID,
    expires_at TIMESTAMPTZ
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    source_id UUID := p_source_user_id;
BEGIN
    PERFORM internal.require_service_role();

    IF source_id IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_invalid_source'
            USING ERRCODE = '22023';
    END IF;

    IF p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'signout_handoff_invalid_secret_hash'
            USING ERRCODE = '22023';
    END IF;

    IF p_source_snapshot_at_ms IS NULL
       OR p_source_snapshot_at_ms NOT BETWEEN 0 AND 253402300799999
       OR p_expected_store_tier NOT IN ('free', 'pro')
       OR (
           p_expected_store_tier = 'free'
           AND p_expected_store_expires_at IS NOT NULL
       )
       OR (
           p_expected_store_expires_at IS NOT NULL
           AND p_expected_store_expires_at <= pg_catalog.TO_TIMESTAMP(
               p_source_snapshot_at_ms::DOUBLE PRECISION / 1000.0
           )
       ) THEN
        RAISE EXCEPTION 'signout_handoff_invalid_store_access'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'signout-purchase-handoff:' || source_id::TEXT,
            0
        )
    );

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = source_id
          AND auth_user.is_anonymous IS FALSE
    ) THEN
        RAISE EXCEPTION 'signout_handoff_linked_source_required'
            USING ERRCODE = '42501';
    END IF;

    UPDATE internal.signout_purchase_handoffs AS handoff
    SET status = CASE
            WHEN handoff.expires_at <= pg_catalog.NOW() THEN 'expired'
            ELSE 'superseded'
        END,
        destination_user_id = NULL,
        bound_at = NULL,
        completed_at = NULL,
        updated_at = pg_catalog.NOW()
    WHERE handoff.source_user_id = source_id
      AND handoff.status = 'prepared';

    IF EXISTS (
        SELECT 1
        FROM internal.signout_purchase_handoffs AS handoff
        WHERE handoff.source_user_id = source_id
          AND handoff.status = 'bound'
    ) THEN
        RAISE EXCEPTION 'signout_handoff_already_bound'
            USING ERRCODE = '55000';
    END IF;

    RETURN QUERY
    INSERT INTO internal.signout_purchase_handoffs AS handoff (
        source_user_id,
        secret_hash,
        source_snapshot_at_ms,
        expected_store_tier,
        expected_store_expires_at,
        expires_at
    )
    VALUES (
        source_id,
        p_secret_hash,
        p_source_snapshot_at_ms,
        p_expected_store_tier,
        p_expected_store_expires_at,
        pg_catalog.NOW() + INTERVAL '30 days'
    )
    RETURNING handoff.id, handoff.expires_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_signout_purchase_handoff(
    p_handoff_id UUID,
    p_secret_hash TEXT
)
RETURNS TABLE (
    handoff_id UUID,
    cancelled_at TIMESTAMPTZ,
    already_cancelled BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    caller_id UUID := auth.uid();
    source_id UUID;
    handoff_record internal.signout_purchase_handoffs%ROWTYPE;
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_authentication_required'
            USING ERRCODE = '42501';
    END IF;

    IF p_handoff_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT handoff.source_user_id
    INTO source_id
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id;

    IF source_id IS NULL OR source_id <> caller_id THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'signout-purchase-handoff:' || source_id::TEXT,
            0
        )
    );

    SELECT handoff.*
    INTO STRICT handoff_record
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id
    FOR UPDATE;

    IF handoff_record.secret_hash <> p_secret_hash
       OR handoff_record.source_user_id <> caller_id THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    IF handoff_record.status = 'superseded' THEN
        RETURN QUERY SELECT
            handoff_record.id,
            handoff_record.updated_at,
            TRUE;
        RETURN;
    END IF;

    IF handoff_record.status <> 'prepared' THEN
        RAISE EXCEPTION 'signout_handoff_not_cancelable'
            USING ERRCODE = '55000';
    END IF;

    UPDATE internal.signout_purchase_handoffs AS handoff
    SET status = CASE
            WHEN handoff.expires_at <= pg_catalog.NOW() THEN 'expired'
            ELSE 'superseded'
        END,
        updated_at = pg_catalog.NOW()
    WHERE handoff.id = handoff_record.id
    RETURNING handoff.*
    INTO handoff_record;

    RETURN QUERY SELECT
        handoff_record.id,
        handoff_record.updated_at,
        FALSE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bind_signout_purchase_handoff(
    p_handoff_id UUID,
    p_secret_hash TEXT
)
RETURNS TABLE (
    handoff_id UUID,
    source_user_id UUID,
    destination_user_id UUID,
    source_snapshot_at_ms BIGINT,
    expected_store_tier TEXT,
    expected_store_expires_at TIMESTAMPTZ,
    handoff_status TEXT,
    destination_verified_snapshot_at_ms BIGINT,
    destination_verified_store_tier TEXT,
    destination_verified_store_expires_at TIMESTAMPTZ,
    bound_at TIMESTAMPTZ,
    already_bound BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    caller_id UUID := auth.uid();
    source_id UUID;
    handoff_record internal.signout_purchase_handoffs%ROWTYPE;
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_authentication_required'
            USING ERRCODE = '42501';
    END IF;

    IF p_handoff_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT handoff.source_user_id
    INTO source_id
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id;

    IF source_id IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'signout-purchase-handoff:' || source_id::TEXT,
            0
        )
    );

    SELECT handoff.*
    INTO STRICT handoff_record
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id
    FOR UPDATE;

    IF handoff_record.secret_hash <> p_secret_hash THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    IF handoff_record.status IN ('bound', 'completed') THEN
        IF handoff_record.destination_user_id <> caller_id THEN
            RAISE EXCEPTION 'signout_handoff_invalid'
                USING ERRCODE = 'P0002';
        END IF;

        RETURN QUERY SELECT
            handoff_record.id,
            handoff_record.source_user_id,
            handoff_record.destination_user_id,
            handoff_record.source_snapshot_at_ms,
            handoff_record.expected_store_tier,
            handoff_record.expected_store_expires_at,
            handoff_record.status,
            handoff_record.destination_verified_snapshot_at_ms,
            handoff_record.destination_verified_store_tier,
            handoff_record.destination_verified_store_expires_at,
            handoff_record.bound_at,
            TRUE;
        RETURN;
    END IF;

    IF handoff_record.status = 'expired'
       OR (
           handoff_record.status = 'prepared'
           AND handoff_record.expires_at <= pg_catalog.NOW()
       ) THEN
        RAISE EXCEPTION 'signout_handoff_expired'
            USING ERRCODE = 'P0001';
    END IF;

    IF handoff_record.status <> 'prepared'
       OR caller_id = handoff_record.source_user_id THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id IN (handoff_record.source_user_id, caller_id)
    ORDER BY auth_user.id
    FOR UPDATE;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = handoff_record.source_user_id
          AND auth_user.is_anonymous IS FALSE
    ) THEN
        RAISE EXCEPTION 'signout_handoff_source_not_available'
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = caller_id
          AND auth_user.is_anonymous IS TRUE
    ) THEN
        RAISE EXCEPTION 'signout_handoff_anonymous_destination_required'
            USING ERRCODE = '42501';
    END IF;

    UPDATE internal.signout_purchase_handoffs AS handoff
    SET destination_user_id = caller_id,
        status = 'bound',
        bound_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE handoff.id = handoff_record.id
    RETURNING handoff.*
    INTO handoff_record;

    RETURN QUERY SELECT
        handoff_record.id,
        handoff_record.source_user_id,
        handoff_record.destination_user_id,
        handoff_record.source_snapshot_at_ms,
        handoff_record.expected_store_tier,
        handoff_record.expected_store_expires_at,
        handoff_record.status,
        handoff_record.destination_verified_snapshot_at_ms,
        handoff_record.destination_verified_store_tier,
        handoff_record.destination_verified_store_expires_at,
        handoff_record.bound_at,
        FALSE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_signout_purchase_handoff(
    p_handoff_id UUID,
    p_secret_hash TEXT,
    p_destination_user_id UUID,
    p_destination_snapshot_at_ms BIGINT,
    p_destination_store_tier TEXT,
    p_destination_store_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    handoff_id UUID,
    completed_at TIMESTAMPTZ,
    already_completed BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
DECLARE
    source_id UUID;
    handoff_record internal.signout_purchase_handoffs%ROWTYPE;
    was_completed BOOLEAN;
    locked_user_count INTEGER;
BEGIN
    PERFORM internal.require_service_role();

    IF p_handoff_id IS NULL
       OR p_destination_user_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$'
       OR p_destination_snapshot_at_ms IS NULL
       OR p_destination_snapshot_at_ms NOT BETWEEN 0 AND 253402300799999
       OR p_destination_store_tier IS NULL
       OR p_destination_store_tier NOT IN ('free', 'pro')
       OR (
           p_destination_store_tier = 'free'
           AND p_destination_store_expires_at IS NOT NULL
       )
       OR (
           p_destination_store_expires_at IS NOT NULL
           AND p_destination_store_expires_at <= pg_catalog.TO_TIMESTAMP(
               p_destination_snapshot_at_ms::DOUBLE PRECISION / 1000.0
           )
       ) THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT handoff.source_user_id
    INTO source_id
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id;

    IF source_id IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'signout-purchase-handoff:' || source_id::TEXT,
            0
        )
    );

    SELECT handoff.*
    INTO STRICT handoff_record
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id
    FOR UPDATE;

    IF handoff_record.secret_hash <> p_secret_hash
       OR handoff_record.destination_user_id <> p_destination_user_id THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    was_completed := handoff_record.status = 'completed';

    -- Expiry limits only the unbound bearer capability. Once one anonymous
    -- destination has bound the proof, completion must remain retryable: the
    -- StoreKit receipt may already have moved and the source cannot safely
    -- cancel or issue a replacement handoff.
    IF handoff_record.status = 'expired' THEN
        RAISE EXCEPTION 'signout_handoff_expired'
            USING ERRCODE = 'P0001';
    END IF;

    IF handoff_record.status NOT IN ('bound', 'completed') THEN
        RAISE EXCEPTION 'signout_handoff_not_bound'
            USING ERRCODE = '55000';
    END IF;

    IF p_destination_snapshot_at_ms < handoff_record.source_snapshot_at_ms THEN
        RAISE EXCEPTION 'signout_handoff_invalid_destination_snapshot'
            USING ERRCODE = '22023';
    END IF;

    IF was_completed
       AND (
           handoff_record.destination_verified_snapshot_at_ms
                <> p_destination_snapshot_at_ms
           OR handoff_record.destination_verified_store_tier
                <> p_destination_store_tier
           OR handoff_record.destination_verified_store_expires_at
                IS DISTINCT FROM p_destination_store_expires_at
       ) THEN
        RAISE EXCEPTION 'signout_handoff_invalid_destination_snapshot'
            USING ERRCODE = '22023';
    END IF;

    -- Match RevenueCat apply ordering: lock every surviving parent user first,
    -- then any queue rows, always in UUID order. External provider work occurs
    -- before this RPC in the client and never while these locks are held.
    PERFORM users.id
    FROM public.users AS users
    WHERE users.id IN (
        handoff_record.source_user_id,
        handoff_record.destination_user_id
    )
    ORDER BY users.id
    FOR UPDATE;
    GET DIAGNOSTICS locked_user_count = ROW_COUNT;

    IF locked_user_count <> 2 THEN
        RAISE EXCEPTION 'signout_handoff_profile_not_available'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM queue.merian_user_id
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id IN (
        handoff_record.source_user_id,
        handoff_record.destination_user_id
    )
    ORDER BY queue.merian_user_id
    FOR UPDATE;

    INSERT INTO internal.revenuecat_reconciliation_queue AS queue (
        merian_user_id,
        lookup_app_user_id,
        next_reconcile_at,
        attempt_count,
        claim_token,
        claimed_at,
        claim_expires_at,
        last_error_code
    )
    SELECT
        users.id,
        internal.canonical_revenuecat_app_user_id(users.id),
        pg_catalog.NOW(),
        0,
        NULL,
        NULL,
        NULL,
        NULL
    FROM public.users AS users
    WHERE users.id IN (
        handoff_record.source_user_id,
        handoff_record.destination_user_id
    )
    ORDER BY users.id
    ON CONFLICT (merian_user_id) DO UPDATE
    SET lookup_app_user_id = EXCLUDED.lookup_app_user_id,
        next_reconcile_at = pg_catalog.NOW(),
        attempt_count = 0,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = NULL,
        updated_at = pg_catalog.NOW();

    IF NOT was_completed THEN
        UPDATE internal.signout_purchase_handoffs AS handoff
        SET status = 'completed',
            destination_verified_snapshot_at_ms =
                p_destination_snapshot_at_ms,
            destination_verified_store_tier = p_destination_store_tier,
            destination_verified_store_expires_at =
                p_destination_store_expires_at,
            completed_at = pg_catalog.NOW(),
            updated_at = pg_catalog.NOW()
        WHERE handoff.id = handoff_record.id
        RETURNING handoff.*
        INTO handoff_record;
    END IF;

    RETURN QUERY SELECT
        handoff_record.id,
        handoff_record.completed_at,
        was_completed;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_revenuecat_reconciliation_for_user(
    p_user_id UUID
)
RETURNS TABLE (
    user_id UUID,
    lookup_app_user_id TEXT,
    claim_token UUID,
    claim_expires_at TIMESTAMPTZ,
    allow_non_subscription_pass_grant BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_user'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.revenuecat_reconciliation_queue AS queue
    SET claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        next_reconcile_at = LEAST(
            queue.next_reconcile_at,
            pg_catalog.NOW()
        ),
        updated_at = pg_catalog.NOW()
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_expires_at <= pg_catalog.NOW();

    RETURN QUERY
    WITH due AS (
        SELECT queue.merian_user_id
        FROM internal.revenuecat_reconciliation_queue AS queue
        WHERE queue.merian_user_id = p_user_id
          AND queue.claim_token IS NULL
          AND queue.next_reconcile_at <= pg_catalog.NOW()
        FOR UPDATE SKIP LOCKED
    ),
    claimed AS (
        UPDATE internal.revenuecat_reconciliation_queue AS queue
        SET claim_token = extensions.gen_random_uuid(),
            claimed_at = pg_catalog.NOW(),
            claim_expires_at = pg_catalog.NOW() + INTERVAL '2 minutes',
            updated_at = pg_catalog.NOW()
        FROM due
        WHERE queue.merian_user_id = due.merian_user_id
        RETURNING
            queue.merian_user_id,
            queue.lookup_app_user_id,
            queue.claim_token,
            queue.claim_expires_at
    )
    SELECT
        claimed.merian_user_id,
        claimed.lookup_app_user_id,
        claimed.claim_token,
        claimed.claim_expires_at,
        (
            users.subscription_tier =
                'pro'::public.subscription_tier_enum
            OR states.merian_user_id IS NULL
        )
    FROM claimed
    JOIN public.users AS users
      ON users.id = claimed.merian_user_id
    LEFT JOIN internal.revenuecat_customer_state AS states
      ON states.merian_user_id = claimed.merian_user_id;
END;
$function$;

-- Extend the existing scheduled RevenueCat monitor without introducing a
-- second workflow or RPC round-trip. Clients deployed before this migration
-- ignore the extra columns; the updated monitor treats missing columns from an
-- older catalog as unavailable/zero until this forward migration lands.
DROP FUNCTION IF EXISTS public.get_revenuecat_reconciliation_health();

CREATE FUNCTION public.get_revenuecat_reconciliation_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    due_count BIGINT,
    expired_claim_count BIGINT,
    oldest_due_at TIMESTAMPTZ,
    oldest_due_age_seconds BIGINT,
    signout_prepared_count BIGINT,
    signout_bound_count BIGINT,
    oldest_signout_pending_at TIMESTAMPTZ,
    oldest_signout_pending_age_seconds BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH health_clock AS MATERIALIZED (
        SELECT pg_catalog.STATEMENT_TIMESTAMP() AS observed_at
    ),
    unclaimed_due AS (
        SELECT
            pg_catalog.COUNT(*) AS due_count,
            pg_catalog.MIN(queue.next_reconcile_at) AS oldest_due_at
        FROM internal.revenuecat_reconciliation_queue AS queue
        CROSS JOIN health_clock AS clock
        WHERE queue.claim_token IS NULL
          AND queue.next_reconcile_at <= clock.observed_at
    ),
    expired_due AS (
        SELECT
            pg_catalog.COUNT(*) AS due_count,
            pg_catalog.MIN(queue.next_reconcile_at) AS oldest_due_at
        FROM internal.revenuecat_reconciliation_queue AS queue
        CROSS JOIN health_clock AS clock
        WHERE queue.claim_token IS NOT NULL
          AND queue.claim_expires_at <= clock.observed_at
          AND queue.next_reconcile_at <= clock.observed_at
    ),
    expired_claims AS (
        SELECT pg_catalog.COUNT(*) AS expired_claim_count
        FROM internal.revenuecat_reconciliation_queue AS queue
        CROSS JOIN health_clock AS clock
        WHERE queue.claim_token IS NOT NULL
          AND queue.claim_expires_at <= clock.observed_at
    ),
    oldest_due AS (
        SELECT pg_catalog.MIN(candidates.due_at) AS due_at
        FROM (
            VALUES
                ((SELECT due.oldest_due_at FROM unclaimed_due AS due)),
                ((SELECT due.oldest_due_at FROM expired_due AS due))
        ) AS candidates(due_at)
    ),
    signout_pending AS (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE handoff.status = 'prepared'
            ) AS prepared_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE handoff.status = 'bound'
            ) AS bound_count,
            pg_catalog.MIN(handoff.created_at) AS oldest_pending_at
        FROM internal.signout_purchase_handoffs AS handoff
        CROSS JOIN health_clock AS clock
        WHERE handoff.status = 'bound'
           OR (
                handoff.status = 'prepared'
                AND handoff.expires_at > clock.observed_at
           )
    )
    SELECT
        clock.observed_at,
        unclaimed.due_count + expired.due_count,
        expired_claims.expired_claim_count,
        oldest.due_at,
        CASE
            WHEN oldest.due_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(EPOCH FROM clock.observed_at - oldest.due_at)
                )::BIGINT
            )
        END,
        signout.prepared_count,
        signout.bound_count,
        signout.oldest_pending_at,
        CASE
            WHEN signout.oldest_pending_at IS NULL THEN NULL
            ELSE GREATEST(
                0,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM
                            clock.observed_at - signout.oldest_pending_at
                    )
                )::BIGINT
            )
        END
    FROM health_clock AS clock
    CROSS JOIN unclaimed_due AS unclaimed
    CROSS JOIN expired_due AS expired
    CROSS JOIN expired_claims
    CROSS JOIN oldest_due AS oldest
    CROSS JOIN signout_pending AS signout;
END;
$function$;

COMMENT ON FUNCTION public.issue_signout_purchase_handoff(
    UUID,
    TEXT,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
) IS
    'Issues a hashed one-use purchase-continuity proof for the current linked source account.';
COMMENT ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT) IS
    'Binds one prepared sign-out proof to the current anonymous destination without accepting caller-selected identities.';
COMMENT ON FUNCTION public.cancel_signout_purchase_handoff(UUID, TEXT) IS
    'Cancels an unbound sign-out proof only for its restored linked source; bound and completed handoffs fail closed.';
COMMENT ON FUNCTION public.complete_signout_purchase_handoff(
    UUID,
    TEXT,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
) IS
    'Service-attests the exact destination StoreKit state and snapshot for a bound sign-out handoff, then schedules RevenueCat reconciliation for both identities.';
COMMENT ON FUNCTION public.claim_revenuecat_reconciliation_for_user(UUID) IS
    'Leases one exact due RevenueCat customer for foreground handoff reconciliation; service role only.';
COMMENT ON FUNCTION public.get_revenuecat_reconciliation_health() IS
    'Returns service-only RevenueCat queue plus unexpired prepared and all bound sign-out purchase-handoff age telemetry for scheduled alerting.';

REVOKE ALL ON FUNCTION public.issue_signout_purchase_handoff(
    UUID,
    TEXT,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cancel_signout_purchase_handoff(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_signout_purchase_handoff(
    UUID,
    TEXT,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_revenuecat_reconciliation_for_user(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_revenuecat_reconciliation_health()
    FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.issue_signout_purchase_handoff(
    UUID,
    TEXT,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_signout_purchase_handoff(UUID, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_signout_purchase_handoff(
    UUID,
    TEXT,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_revenuecat_reconciliation_for_user(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.get_revenuecat_reconciliation_health()
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.issue_signout_purchase_handoff(uuid,text,bigint,text,timestamp with time zone)',
        'Linked user sign-out; the authenticated Edge boundary issues a one-use StoreKit purchase continuity proof for its derived source.'
    ),
    (
        'authenticated',
        'public.bind_signout_purchase_handoff(uuid,text)',
        'Linked user sign-out; current anonymous destination binds a prepared purchase continuity proof.'
    ),
    (
        'authenticated',
        'public.cancel_signout_purchase_handoff(uuid,text)',
        'Linked user sign-out; a restored source may cancel only its own still-unbound proof.'
    ),
    (
        'service_role',
        'public.complete_signout_purchase_handoff(uuid,text,uuid,bigint,text,timestamp with time zone)',
        'Linked user sign-out; the authenticated Edge boundary attests authoritative destination StoreKit state for the proof-bound identity and schedules reconciliation.'
    ),
    (
        'service_role',
        'public.claim_revenuecat_reconciliation_for_user(uuid)',
        'Foreground sign-out purchase handoff; leases one exact destination for authoritative CustomerInfo application.'
    ),
    (
        'service_role',
        'public.get_revenuecat_reconciliation_health()',
        'Scheduled RevenueCat health monitor; reports queue backlog and pending sign-out purchase-handoff age without identity data.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

RESET statement_timeout;
RESET lock_timeout;
