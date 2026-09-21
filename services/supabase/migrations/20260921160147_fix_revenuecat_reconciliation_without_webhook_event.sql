-- Repeat reconciliation must also work for accounts that never received a
-- webhook. Reuse the existing ignored, zero-subject seed; it grants no access.
-- No customer backfill or payment-history conversion is needed.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.apply_revenuecat_reconciliation(
    p_user_id UUID,
    p_claim_token UUID,
    p_authoritative_snapshot_at_ms BIGINT,
    p_target_tier TEXT,
    p_target_expires_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    legacy_state internal.legacy_revenuecat_entitlement_state%ROWTYPE;
    target_tier public.subscription_tier_enum;
    seed_event_id TEXT;
    state_applied BOOLEAN := FALSE;
BEGIN
    PERFORM internal.require_service_role();
    IF p_user_id IS NULL
       OR p_claim_token IS NULL
       OR p_authoritative_snapshot_at_ms IS NULL
       OR p_authoritative_snapshot_at_ms NOT BETWEEN 0 AND 253402300799999
       OR p_target_tier NOT IN ('free', 'pro') THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_state'
            USING ERRCODE = '22023';
    END IF;
    target_tier := p_target_tier::public.subscription_tier_enum;
    IF (target_tier = 'free'::public.subscription_tier_enum
            AND p_target_expires_at IS NOT NULL)
       OR (target_tier = 'pro'::public.subscription_tier_enum
            AND p_target_expires_at IS NOT NULL
            AND p_target_expires_at <= pg_catalog.TO_TIMESTAMP(
                p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
            )) THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_state'
            USING ERRCODE = '22023';
    END IF;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_user_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM 1
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    SELECT state.*
    INTO legacy_state
    FROM internal.legacy_revenuecat_entitlement_state AS state
    WHERE state.merian_user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND OR p_authoritative_snapshot_at_ms >
            legacy_state.authoritative_snapshot_at_ms THEN
        INSERT INTO internal.legacy_revenuecat_entitlement_state (
            merian_user_id,
            target_tier,
            target_expires_at,
            authoritative_snapshot_at_ms,
            last_event_id,
            last_event_timestamp_ms,
            updated_at
        )
        VALUES (
            p_user_id,
            target_tier,
            p_target_expires_at,
            p_authoritative_snapshot_at_ms,
            legacy_state.last_event_id,
            COALESCE(legacy_state.last_event_timestamp_ms, 0),
            pg_catalog.CLOCK_TIMESTAMP()
        )
        ON CONFLICT (merian_user_id) DO UPDATE
        SET target_tier = EXCLUDED.target_tier,
            target_expires_at = EXCLUDED.target_expires_at,
            authoritative_snapshot_at_ms =
                EXCLUDED.authoritative_snapshot_at_ms,
            updated_at = EXCLUDED.updated_at;

        -- Reconciled beta accounts may have state but no webhook history.
        -- The compatibility watermark still requires a non-null event FK.
        IF legacy_state.last_event_id IS NULL THEN
            seed_event_id := 'reconcile-seed:' || p_user_id::TEXT;
            INSERT INTO internal.revenuecat_webhook_events (
                event_id,
                event_timestamp_ms,
                event_type,
                payload_sha256,
                signature_timestamp_s,
                outcome,
                subject_count,
                applied_count,
                stale_count
            )
            VALUES (
                seed_event_id,
                p_authoritative_snapshot_at_ms,
                'RECONCILIATION',
                pg_catalog.REPEAT('0', 64),
                pg_catalog.FLOOR(
                    p_authoritative_snapshot_at_ms::NUMERIC / 1000
                )::BIGINT,
                'ignored',
                0,
                0,
                0
            )
            ON CONFLICT (event_id) DO NOTHING;
        END IF;

        INSERT INTO internal.revenuecat_customer_state (
            merian_user_id,
            last_event_id,
            last_event_timestamp_ms,
            last_authoritative_snapshot_at_ms,
            updated_at
        )
        VALUES (
            p_user_id,
            COALESCE(legacy_state.last_event_id, seed_event_id),
            COALESCE(
                legacy_state.last_event_timestamp_ms,
                p_authoritative_snapshot_at_ms
            ),
            p_authoritative_snapshot_at_ms,
            pg_catalog.CLOCK_TIMESTAMP()
        )
        ON CONFLICT (merian_user_id) DO UPDATE
        SET last_authoritative_snapshot_at_ms =
                EXCLUDED.last_authoritative_snapshot_at_ms,
            updated_at = EXCLUDED.updated_at;

        PERFORM internal.recompute_purchase_principal_entitlement(p_user_id);
        state_applied := TRUE;
    END IF;

    UPDATE internal.revenuecat_reconciliation_queue AS queue
    SET next_reconcile_at = pg_catalog.NOW() + CASE
            WHEN target_tier = 'pro'::public.subscription_tier_enum
                THEN INTERVAL '6 hours'
            ELSE INTERVAL '24 hours'
        END,
        attempt_count = 0,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_snapshot_at_ms = GREATEST(
            COALESCE(queue.last_snapshot_at_ms, 0),
            p_authoritative_snapshot_at_ms
        ),
        last_reconciled_at = pg_catalog.NOW(),
        last_error_code = NULL,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;
    RETURN state_applied;
END;
$function$;

REVOKE ALL ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID, UUID, BIGINT, TEXT, TIMESTAMPTZ
) TO service_role;

RESET statement_timeout;
RESET lock_timeout;
