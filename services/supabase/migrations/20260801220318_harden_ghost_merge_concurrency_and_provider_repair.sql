-- Complete the schema-aware Ghost merge with one parent-before-child lock
-- order, collision-only Community actor normalization, and unconditional
-- destination RevenueCat repair. These routines replace committed definitions;
-- historical migration files remain immutable.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION internal.merge_ghost_community_activity_actors(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
BEGIN
    IF p_ghost_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_ghost_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'ghost_merge_invalid_identity_pair'
            USING ERRCODE = '22023';
    END IF;

    -- The orchestrator already holds both public.users rows. Lock actor rows in
    -- one deterministic order, then touch only collisions. A normal Community
    -- writer locks its activity group before inserting/updating its actor; this
    -- handler must not acquire an activity-group FK lock after actor locks.
    PERFORM actor.user_id
    FROM internal.community_identification_activity_actors AS actor
    WHERE actor.user_id IN (p_ghost_user_id, p_target_user_id)
    ORDER BY actor.activity_group_id, actor.user_id
    FOR UPDATE;

    UPDATE internal.community_identification_activity_actors AS target_actor
    SET suggestion_count =
            target_actor.suggestion_count + source_actor.suggestion_count,
        last_suggested_at = GREATEST(
            target_actor.last_suggested_at,
            source_actor.last_suggested_at
        )
    FROM internal.community_identification_activity_actors AS source_actor
    WHERE source_actor.user_id = p_ghost_user_id
      AND target_actor.user_id = p_target_user_id
      AND target_actor.activity_group_id = source_actor.activity_group_id;

    DELETE FROM internal.community_identification_activity_actors
        AS source_actor
    USING internal.community_identification_activity_actors AS target_actor
    WHERE source_actor.user_id = p_ghost_user_id
      AND target_actor.user_id = p_target_user_id
      AND target_actor.activity_group_id = source_actor.activity_group_id;

    -- Non-colliding source actors intentionally remain. The reviewed
    -- handler_then_reparent policy changes their user_id after this helper.
END;
$function$;

CREATE OR REPLACE FUNCTION internal.merge_ghost_revenuecat_state(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
DECLARE
    source_last_snapshot_at_ms BIGINT;
    source_last_reconciled_at TIMESTAMPTZ;
    source_queue_created_at TIMESTAMPTZ;
BEGIN
    IF p_ghost_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_ghost_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'ghost_merge_invalid_identity_pair'
            USING ERRCODE = '22023';
    END IF;

    -- A transfer event can already contain both source and destination. Keep
    -- the destination subject so changing the source identity cannot violate
    -- the per-event primary key.
    DELETE FROM internal.revenuecat_webhook_event_subjects AS source_subject
    USING internal.revenuecat_webhook_event_subjects AS target_subject
    WHERE source_subject.merian_user_id = p_ghost_user_id
      AND target_subject.merian_user_id = p_target_user_id
      AND target_subject.event_id = source_subject.event_id;

    -- Preserve the newest authoritative ordering watermark when both users
    -- already have state. If the target has no row, the reviewed policy pass
    -- reparents the remaining source row.
    UPDATE internal.revenuecat_customer_state AS target_state
    SET last_event_id = source_state.last_event_id,
        last_event_timestamp_ms = source_state.last_event_timestamp_ms,
        last_authoritative_snapshot_at_ms =
            source_state.last_authoritative_snapshot_at_ms,
        updated_at = GREATEST(
            target_state.updated_at,
            source_state.updated_at
        )
    FROM internal.revenuecat_customer_state AS source_state
    WHERE target_state.merian_user_id = p_target_user_id
      AND source_state.merian_user_id = p_ghost_user_id
      AND (
          source_state.last_authoritative_snapshot_at_ms
              > target_state.last_authoritative_snapshot_at_ms
          OR (
              source_state.last_authoritative_snapshot_at_ms
                  = target_state.last_authoritative_snapshot_at_ms
              AND source_state.last_event_timestamp_ms
                  > target_state.last_event_timestamp_ms
          )
          OR (
              source_state.last_authoritative_snapshot_at_ms
                  = target_state.last_authoritative_snapshot_at_ms
              AND source_state.last_event_timestamp_ms
                  = target_state.last_event_timestamp_ms
              AND source_state.last_event_id COLLATE pg_catalog."C"
                  > target_state.last_event_id COLLATE pg_catalog."C"
          )
      );

    DELETE FROM internal.revenuecat_customer_state AS source_state
    USING internal.revenuecat_customer_state AS target_state
    WHERE source_state.merian_user_id = p_ghost_user_id
      AND target_state.merian_user_id = p_target_user_id;

    -- The orchestrator holds source/target public.users before child state.
    -- Lock both possible queue rows in UUID order so every merge uses the same
    -- child-row order and so an apply callback cannot hold queue-before-user.
    PERFORM queue.merian_user_id
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id IN (p_ghost_user_id, p_target_user_id)
    ORDER BY queue.merian_user_id
    FOR UPDATE;

    SELECT
        source_queue.last_snapshot_at_ms,
        source_queue.last_reconciled_at,
        source_queue.created_at
    INTO
        source_last_snapshot_at_ms,
        source_last_reconciled_at,
        source_queue_created_at
    FROM internal.revenuecat_reconciliation_queue AS source_queue
    WHERE source_queue.merian_user_id = p_ghost_user_id;

    -- This upsert is unconditional: anonymous sources legitimately may have no
    -- queue row. The permanent destination must be due now even when provider
    -- webhook delivery and foreground Purchases.logIn both fail.
    INSERT INTO internal.revenuecat_reconciliation_queue
        AS destination_queue (
            merian_user_id,
            lookup_app_user_id,
            next_reconcile_at,
            attempt_count,
            claim_token,
            claimed_at,
            claim_expires_at,
            last_snapshot_at_ms,
            last_reconciled_at,
            last_error_code,
            created_at,
            updated_at
        )
    VALUES (
        p_target_user_id,
        p_target_user_id::TEXT,
        pg_catalog.NOW(),
        0,
        NULL,
        NULL,
        NULL,
        source_last_snapshot_at_ms,
        source_last_reconciled_at,
        NULL,
        COALESCE(source_queue_created_at, pg_catalog.NOW()),
        pg_catalog.NOW()
    )
    ON CONFLICT (merian_user_id) DO UPDATE
    SET lookup_app_user_id = EXCLUDED.lookup_app_user_id,
        next_reconcile_at = pg_catalog.NOW(),
        attempt_count = 0,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_snapshot_at_ms = GREATEST(
            destination_queue.last_snapshot_at_ms,
            EXCLUDED.last_snapshot_at_ms
        ),
        last_reconciled_at = GREATEST(
            destination_queue.last_reconciled_at,
            EXCLUDED.last_reconciled_at
        ),
        last_error_code = NULL,
        created_at = LEAST(
            destination_queue.created_at,
            EXCLUDED.created_at
        ),
        updated_at = pg_catalog.NOW();

    DELETE FROM internal.revenuecat_reconciliation_queue AS source_queue
    WHERE source_queue.merian_user_id = p_ghost_user_id;
END;
$function$;

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
    queue_row internal.revenuecat_reconciliation_queue%ROWTYPE;
    watermark internal.revenuecat_customer_state%ROWTYPE;
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
    IF (
        target_tier = 'free'::public.subscription_tier_enum
        AND p_target_expires_at IS NOT NULL
    ) OR (
        target_tier = 'pro'::public.subscription_tier_enum
        AND p_target_expires_at IS NOT NULL
        AND p_target_expires_at <= pg_catalog.TO_TIMESTAMP(
            p_authoritative_snapshot_at_ms::DOUBLE PRECISION / 1000.0
        )
    ) THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_state'
            USING ERRCODE = '22023';
    END IF;

    -- Match Ghost merge ordering: parent user first, queue lease second.
    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_user_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    -- Revalidate the exact, unexpired claim only after the parent lock. If a
    -- merge won the user lock and reset the lease, no provider state is applied.
    SELECT queue.*
    INTO queue_row
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    SELECT states.*
    INTO watermark
    FROM internal.revenuecat_customer_state AS states
    WHERE states.merian_user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND
       OR p_authoritative_snapshot_at_ms
            > watermark.last_authoritative_snapshot_at_ms THEN
        UPDATE public.users AS users
        SET subscription_tier = target_tier,
            subscription_expires_at = p_target_expires_at
        WHERE users.id = p_user_id
          AND (
              users.subscription_tier IS DISTINCT FROM target_tier
              OR users.subscription_expires_at
                    IS DISTINCT FROM p_target_expires_at
          );

        IF watermark.merian_user_id IS NULL THEN
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
                'applied',
                0,
                0,
                0
            )
            ON CONFLICT (event_id) DO NOTHING;

            INSERT INTO internal.revenuecat_customer_state (
                merian_user_id,
                last_event_id,
                last_event_timestamp_ms,
                last_authoritative_snapshot_at_ms,
                updated_at
            )
            VALUES (
                p_user_id,
                seed_event_id,
                p_authoritative_snapshot_at_ms,
                p_authoritative_snapshot_at_ms,
                pg_catalog.NOW()
            );
        ELSE
            UPDATE internal.revenuecat_customer_state AS states
            SET last_authoritative_snapshot_at_ms =
                    p_authoritative_snapshot_at_ms,
                updated_at = pg_catalog.NOW()
            WHERE states.merian_user_id = p_user_id;
        END IF;

        state_applied := TRUE;
    END IF;

    -- Recheck token and expiry in the completion write. If the claim expires
    -- while this transaction is running, every prior state change rolls back.
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
        updated_at = pg_catalog.NOW()
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

COMMENT ON FUNCTION internal.merge_ghost_community_activity_actors(UUID, UUID)
IS 'Coalesces only colliding source/destination Community actor rows with update/delete; non-colliding source rows remain for reviewed reparenting.';
COMMENT ON FUNCTION internal.merge_ghost_revenuecat_state(UUID, UUID)
IS 'Normalizes RevenueCat state and unconditionally schedules immediate, claim-free reconciliation for the permanent merge destination.';
COMMENT ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
) IS 'Applies a claim-fenced authoritative RevenueCat snapshot using public-user-before-queue lock order.';

REVOKE ALL ON FUNCTION
    internal.merge_ghost_community_activity_actors(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.merge_ghost_revenuecat_state(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
) TO service_role;

RESET lock_timeout;
RESET statement_timeout;
