-- Replace the calendar trial with three lifetime complimentary Pro scans.
--
-- Complimentary settlement is deliberately independent of provider quota
-- accounting. Provider counters are still finalized by the existing quota
-- lease after dispatch; this ledger only records whether one of the three
-- user-facing results is held, consumed, or released.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS complimentary_entitlement_epoch BIGINT
        NOT NULL DEFAULT 1;

COMMENT ON COLUMN public.users.complimentary_entitlement_epoch IS
    'Protected mutation epoch for complimentary holds and settlement. The entitlement trigger folds it into the public monotonic entitlement_version.';

CREATE OR REPLACE FUNCTION internal.bump_user_entitlement_version()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier
       OR NEW.subscription_expires_at IS DISTINCT FROM OLD.subscription_expires_at
       OR NEW.complimentary_entitlement_epoch
            IS DISTINCT FROM OLD.complimentary_entitlement_epoch THEN
        NEW.entitlement_version := OLD.entitlement_version + 1;
    ELSE
        -- A caller cannot forge a version independently of a real durable
        -- entitlement transition.
        NEW.entitlement_version := OLD.entitlement_version;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.bump_user_entitlement_version()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS bump_user_entitlement_version ON public.users;
CREATE TRIGGER bump_user_entitlement_version
BEFORE UPDATE OF
    subscription_tier,
    subscription_expires_at,
    complimentary_entitlement_epoch,
    entitlement_version
ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.bump_user_entitlement_version();

CREATE TABLE internal.entitlement_rollout_config (
    config_key TEXT PRIMARY KEY DEFAULT 'current'
        CHECK (config_key = 'current'),
    entitlement_mode TEXT NOT NULL DEFAULT 'legacy_trial'
        CHECK (entitlement_mode IN ('legacy_trial', 'complimentary')),
    complimentary_scan_grant INTEGER NOT NULL DEFAULT 3
        CHECK (complimentary_scan_grant = 3),
    required_client_protocol INTEGER NOT NULL DEFAULT 0
        CHECK (required_client_protocol BETWEEN 0 AND 1000),
    mode_version BIGINT NOT NULL DEFAULT 1
        CHECK (mode_version > 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT entitlement_rollout_mode_protocol_check CHECK (
        (
            entitlement_mode = 'legacy_trial'
            AND required_client_protocol = 0
        )
        OR (
            entitlement_mode = 'complimentary'
            AND required_client_protocol = 2
        )
    )
);

INSERT INTO internal.entitlement_rollout_config (
    config_key,
    entitlement_mode,
    complimentary_scan_grant,
    required_client_protocol
)
VALUES ('current', 'legacy_trial', 3, 0)
ON CONFLICT (config_key) DO NOTHING;

CREATE OR REPLACE FUNCTION internal.bump_entitlement_rollout_version()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF NEW.entitlement_mode IS DISTINCT FROM OLD.entitlement_mode
       OR NEW.required_client_protocol
            IS DISTINCT FROM OLD.required_client_protocol THEN
        NEW.mode_version := OLD.mode_version + 1;
        NEW.updated_at := pg_catalog.CLOCK_TIMESTAMP();
    ELSE
        NEW.mode_version := OLD.mode_version;
        NEW.updated_at := OLD.updated_at;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.bump_entitlement_rollout_version()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER bump_entitlement_rollout_version
BEFORE UPDATE OF
    entitlement_mode,
    required_client_protocol,
    mode_version,
    updated_at
ON internal.entitlement_rollout_config
FOR EACH ROW
EXECUTE FUNCTION internal.bump_entitlement_rollout_version();

ALTER TABLE internal.entitlement_rollout_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.entitlement_rollout_config
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.entitlement_rollout_config IS
    'Owner-only atomic rollout switch. legacy_trial/protocol 0 supports a schema-first deploy; complimentary/protocol 2 is the post-cutover state. mode_version advances every effective global transition.';

CREATE TABLE internal.complimentary_scan_usage (
    user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    client_scan_id UUID NOT NULL,
    state TEXT NOT NULL DEFAULT 'held'
        CHECK (state IN ('held', 'consumed', 'released')),
    held_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    settled_at TIMESTAMPTZ,
    settlement_reason TEXT,
    reacquisition_count INTEGER NOT NULL DEFAULT 0
        CHECK (reacquisition_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (user_id, client_scan_id),
    CONSTRAINT complimentary_scan_usage_settlement_check CHECK (
        (
            state = 'held'
            AND settled_at IS NULL
            AND settlement_reason IS NULL
        )
        OR (
            state IN ('consumed', 'released')
            AND settled_at IS NOT NULL
            AND settlement_reason ~ '^[a-z][a-z0-9_]{1,63}$'
        )
    ),
    CONSTRAINT complimentary_scan_usage_time_check CHECK (
        held_at >= created_at
        AND updated_at >= created_at
        AND (settled_at IS NULL OR settled_at >= held_at)
    )
);

CREATE INDEX complimentary_scan_usage_held_age_idx
    ON internal.complimentary_scan_usage (held_at, user_id, client_scan_id)
    WHERE state = 'held';

CREATE INDEX complimentary_scan_usage_settlement_reason_idx
    ON internal.complimentary_scan_usage (
        state,
        settlement_reason,
        settled_at DESC
    )
    WHERE state <> 'held';

ALTER TABLE internal.complimentary_scan_usage ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.complimentary_scan_usage
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.complimentary_scan_usage IS
    'Private lifetime ledger. The sole grant is three and all balances are derived from rows; no mutable balance counter exists.';
COMMENT ON COLUMN internal.complimentary_scan_usage.client_scan_id IS
    'Original user-initiated analysis linkage. Retries, replays, enrichment, and provider subcalls reuse this UUID.';

-- Preserve the historical resolver signature for reports and old rows. In
-- post-cutover mode it cannot emit pro_trial; the user-aware resolver below is
-- authoritative for current functional access.
CREATE OR REPLACE FUNCTION internal.effective_plan(
    p_subscription_tier public.subscription_tier_enum,
    p_created_at TIMESTAMPTZ,
    p_expires_at TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT CASE
        WHEN pg_catalog.CURRENT_SETTING(
                'merian.quota_v2_fence',
                TRUE
             ) = 'on'
          AND pg_catalog.CURRENT_SETTING(
                'merian.entitlement_plan_override',
                TRUE
             ) IN (
                'free',
                'pro_trial',
                'pro_complimentary',
                'pro_paid'
             ) THEN pg_catalog.CURRENT_SETTING(
                'merian.entitlement_plan_override',
                TRUE
             )
        WHEN p_subscription_tier = 'pro'::public.subscription_tier_enum
          AND (p_expires_at IS NULL OR p_expires_at > pg_catalog.NOW())
            THEN 'pro_paid'
        WHEN COALESCE(
                (
                    SELECT config.entitlement_mode = 'legacy_trial'
                    FROM internal.entitlement_rollout_config AS config
                    WHERE config.config_key = 'current'
                ),
                FALSE
             )
          AND p_subscription_tier = 'free'::public.subscription_tier_enum
          AND p_created_at <= pg_catalog.NOW()
          AND p_created_at >= pg_catalog.NOW() - INTERVAL '7 days'
            THEN 'pro_trial'
        ELSE 'free'
    END
$$;

REVOKE ALL ON FUNCTION internal.effective_plan(
    public.subscription_tier_enum,
    TIMESTAMPTZ,
    TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.resolve_effective_entitlement(
    p_user_id UUID
)
RETURNS TABLE (
    current_plan TEXT,
    current_tier TEXT,
    is_paid BOOLEAN,
    scans_remaining INTEGER,
    scans_available_to_start INTEGER,
    in_flight_count INTEGER,
    entitlement_version BIGINT
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    app_user RECORD;
    rollout RECORD;
    consumed_count INTEGER;
    held_count INTEGER;
    resolved_paid BOOLEAN;
    resolved_trial BOOLEAN;
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT
        users.subscription_tier,
        users.created_at,
        users.subscription_expires_at,
        users.entitlement_version
    INTO app_user
    FROM public.users AS users
    WHERE users.id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT
        config.entitlement_mode,
        config.complimentary_scan_grant,
        config.mode_version
    INTO rollout
    FROM internal.entitlement_rollout_config AS config
    WHERE config.config_key = 'current';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT
        pg_catalog.COUNT(*) FILTER (
            WHERE usage.state = 'consumed'
        )::INTEGER,
        pg_catalog.COUNT(*) FILTER (
            WHERE usage.state = 'held'
        )::INTEGER
    INTO consumed_count, held_count
    FROM internal.complimentary_scan_usage AS usage
    WHERE usage.user_id = p_user_id;

    consumed_count := COALESCE(consumed_count, 0);
    held_count := COALESCE(held_count, 0);
    resolved_paid := app_user.subscription_tier =
            'pro'::public.subscription_tier_enum
        AND (
            app_user.subscription_expires_at IS NULL
            OR app_user.subscription_expires_at > pg_catalog.NOW()
        );
    resolved_trial := rollout.entitlement_mode = 'legacy_trial'
        AND app_user.subscription_tier =
            'free'::public.subscription_tier_enum
        AND app_user.created_at <= pg_catalog.NOW()
        AND app_user.created_at >=
            pg_catalog.NOW() - INTERVAL '7 days';

    current_plan := CASE
        WHEN resolved_paid THEN 'pro_paid'
        WHEN resolved_trial THEN 'pro_trial'
        WHEN rollout.entitlement_mode = 'complimentary'
          AND (
              rollout.complimentary_scan_grant - consumed_count > 0
              OR held_count > 0
          ) THEN 'pro_complimentary'
        ELSE 'free'
    END;
    current_tier := CASE
        WHEN current_plan IN (
            'pro_paid',
            'pro_trial',
            'pro_complimentary'
        ) THEN 'pro'
        ELSE 'free'
    END;
    is_paid := resolved_paid;
    scans_remaining := GREATEST(
        rollout.complimentary_scan_grant - consumed_count,
        0
    );
    scans_available_to_start := GREATEST(
        rollout.complimentary_scan_grant - consumed_count - held_count,
        0
    );
    in_flight_count := held_count;
    -- A rollout transition changes every account's effective entitlement.
    -- Folding the protected singleton version into the per-user version keeps
    -- scan envelopes globally monotonic without rewriting the users table.
    entitlement_version := app_user.entitlement_version
        + rollout.mode_version;

    RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION internal.resolve_effective_entitlement(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.user_has_effective_pro(
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT entitlement.current_tier = 'pro'
    FROM internal.resolve_effective_entitlement(p_user_id) AS entitlement
$$;

REVOKE ALL ON FUNCTION internal.user_has_effective_pro(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_my_entitlement()
RETURNS TABLE (
    current_plan TEXT,
    current_tier TEXT,
    is_paid BOOLEAN,
    scans_remaining INTEGER,
    scans_available_to_start INTEGER,
    in_flight_count INTEGER,
    entitlement_version BIGINT
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    caller_id UUID := (SELECT auth.uid());
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'authentication_required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT entitlement.*
    FROM internal.resolve_effective_entitlement(caller_id) AS entitlement;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_entitlement()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_entitlement() TO authenticated;

COMMENT ON FUNCTION public.get_my_entitlement() IS
    'Authenticated own-account entitlement snapshot. Balances are derived from the private ledger and versioned monotonically.';

CREATE OR REPLACE FUNCTION public.get_user_entitlement_service(
    p_user_id UUID
)
RETURNS TABLE (
    current_plan TEXT,
    current_tier TEXT,
    is_paid BOOLEAN,
    scans_remaining INTEGER,
    scans_available_to_start INTEGER,
    in_flight_count INTEGER,
    entitlement_version BIGINT
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    SELECT entitlement.*
    FROM internal.resolve_effective_entitlement(p_user_id) AS entitlement;
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_entitlement_service(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_user_entitlement_service(UUID)
    TO service_role;

CREATE OR REPLACE FUNCTION public.get_entitlement_rollout_service()
RETURNS TABLE (
    entitlement_mode TEXT,
    required_client_protocol INTEGER,
    mode_version BIGINT
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    SELECT
        config.entitlement_mode,
        config.required_client_protocol,
        config.mode_version
    FROM internal.entitlement_rollout_config AS config
    WHERE config.config_key = 'current';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_entitlement_rollout_service()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_entitlement_rollout_service()
    TO service_role;

COMMENT ON FUNCTION public.get_entitlement_rollout_service() IS
    'Service-only rollout fence used to enforce protocol 2 only after the atomic complimentary cutover.';

-- pro_trial remains valid historical data. New policy and usage rows use the
-- explicit pro_complimentary label.
ALTER TABLE internal.ai_quota_policies
    DROP CONSTRAINT ai_quota_policies_effective_plan_check;
ALTER TABLE internal.ai_quota_policies
    ADD CONSTRAINT ai_quota_policies_effective_plan_check CHECK (
        effective_plan IN (
            'free',
            'pro_trial',
            'pro_complimentary',
            'pro_paid'
        )
    );

ALTER TABLE internal.ai_quota_reservations
    DROP CONSTRAINT ai_quota_reservations_effective_plan_check;
ALTER TABLE internal.ai_quota_reservations
    ADD CONSTRAINT ai_quota_reservations_effective_plan_check CHECK (
        effective_plan IN (
            'free',
            'pro_trial',
            'pro_complimentary',
            'pro_paid'
        )
    );

ALTER TABLE public.ai_usage_events
    DROP CONSTRAINT ai_usage_events_effective_plan_check;
ALTER TABLE public.ai_usage_events
    ADD CONSTRAINT ai_usage_events_effective_plan_check CHECK (
        effective_plan IN (
            'free',
            'pro_paid',
            'pro_trial',
            'pro_complimentary',
            'unknown'
        )
    );

INSERT INTO internal.ai_quota_policies (
    operation,
    effective_plan,
    model,
    allowed,
    enabled,
    policy_version,
    daily_bucket,
    daily_limit,
    user_rate_bucket,
    user_window_seconds,
    user_window_limit,
    ip_rate_bucket,
    ip_window_seconds,
    ip_window_limit,
    created_at,
    updated_at
)
SELECT
    policies.operation,
    'pro_complimentary',
    policies.model,
    policies.allowed,
    policies.enabled,
    policies.policy_version,
    pg_catalog.REPLACE(
        policies.daily_bucket,
        'pro_trial',
        'pro_complimentary'
    ),
    policies.daily_limit,
    pg_catalog.REPLACE(
        policies.user_rate_bucket,
        'pro_trial',
        'pro_complimentary'
    ),
    policies.user_window_seconds,
    policies.user_window_limit,
    pg_catalog.REPLACE(
        policies.ip_rate_bucket,
        'pro_trial',
        'pro_complimentary'
    ),
    policies.ip_window_seconds,
    policies.ip_window_limit,
    pg_catalog.NOW(),
    pg_catalog.NOW()
FROM internal.ai_quota_policies AS policies
WHERE policies.effective_plan = 'pro_trial'
ON CONFLICT (operation, effective_plan) DO UPDATE
SET model = EXCLUDED.model,
    allowed = EXCLUDED.allowed,
    enabled = EXCLUDED.enabled,
    daily_bucket = EXCLUDED.daily_bucket,
    daily_limit = EXCLUDED.daily_limit,
    user_rate_bucket = EXCLUDED.user_rate_bucket,
    user_window_seconds = EXCLUDED.user_window_seconds,
    user_window_limit = EXCLUDED.user_window_limit,
    ip_rate_bucket = EXCLUDED.ip_rate_bucket,
    ip_window_seconds = EXCLUDED.ip_window_seconds,
    ip_window_limit = EXCLUDED.ip_window_limit,
    policy_version = internal.ai_quota_policies.policy_version + 1,
    updated_at = pg_catalog.NOW();

ALTER TABLE internal.ai_quota_reservations
    ADD COLUMN IF NOT EXISTS original_analysis_id UUID,
    ADD COLUMN IF NOT EXISTS complimentary_client_scan_id UUID,
    ADD COLUMN IF NOT EXISTS client_protocol INTEGER,
    ADD COLUMN IF NOT EXISTS flash_fallback_used BOOLEAN
        NOT NULL DEFAULT FALSE;

ALTER TABLE internal.ai_quota_reservations
    ADD CONSTRAINT ai_quota_reservations_client_protocol_check CHECK (
        client_protocol IS NULL
        OR client_protocol BETWEEN 1 AND 1000
    ),
    ADD CONSTRAINT ai_quota_reservations_complimentary_link_check CHECK (
        complimentary_client_scan_id IS NULL
        OR original_analysis_id = complimentary_client_scan_id
    ),
    ADD CONSTRAINT ai_quota_reservations_flash_fallback_check CHECK (
        NOT flash_fallback_used
        OR (
            effective_plan = 'free'
            AND operation IN (
                'scan_identification',
                'scan_audio_identification'
            )
        )
    );

CREATE INDEX ai_quota_reservations_original_analysis_idx
    ON internal.ai_quota_reservations (
        user_id,
        original_analysis_id,
        created_at DESC
    )
    WHERE original_analysis_id IS NOT NULL;

COMMENT ON COLUMN internal.ai_quota_reservations.original_analysis_id IS
    'Original client_scan_id shared by retries and provider subcalls; distinct quota request UUIDs remain valid.';
COMMENT ON COLUMN internal.ai_quota_reservations.complimentary_client_scan_id IS
    'Nullable linkage to the private complimentary hold used by this analysis.';
COMMENT ON COLUMN internal.ai_quota_reservations.flash_fallback_used IS
    'Server-classified fallback to the separate daily Flash policy after complimentary exhaustion.';

CREATE OR REPLACE FUNCTION public.reserve_ai_quota(
    p_user_id UUID,
    p_operation TEXT,
    p_request_id UUID,
    p_ip_hash TEXT,
    p_original_analysis_id UUID,
    p_flash_fallback_eligible BOOLEAN,
    p_client_protocol INTEGER,
    p_internal_replay BOOLEAN
)
RETURNS TABLE (
    reservation_id UUID,
    request_id UUID,
    lease_token UUID,
    lease_expires_at TIMESTAMPTZ,
    reservation_state TEXT,
    is_replay BOOLEAN,
    attempt_count INTEGER,
    model TEXT,
    effective_plan TEXT,
    effective_tier TEXT,
    subscription_tier TEXT,
    trial_active BOOLEAN,
    entitlement_version BIGINT,
    policy_version BIGINT,
    daily_limit INTEGER,
    daily_remaining INTEGER,
    original_analysis_id UUID,
    complimentary_client_scan_id UUID,
    flash_fallback_used BOOLEAN,
    scans_remaining INTEGER,
    scans_available_to_start INTEGER,
    in_flight_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    app_user RECORD;
    rollout RECORD;
    active_reservation internal.ai_quota_reservations%ROWTYPE;
    usage_row internal.complimentary_scan_usage%ROWTYPE;
    quota_result RECORD;
    updated_reservation internal.ai_quota_reservations%ROWTYPE;
    entitlement_after RECORD;
    resolved_plan TEXT;
    resolved_link UUID;
    resolved_flash_fallback BOOLEAN := FALSE;
    main_scan_operation BOOLEAN;
    usage_changed BOOLEAN := FALSE;
    consumed_count INTEGER := 0;
    held_count INTEGER := 0;
    quota_now TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    main_scan_operation := p_operation IN (
        'scan_identification',
        'scan_audio_identification'
    );

    IF p_user_id IS NULL
       OR p_request_id IS NULL
       OR p_operation IS NULL
       OR p_operation !~ '^[a-z][a-z0-9_]{2,63}$'
       OR p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$'
       OR p_flash_fallback_eligible IS NULL
       OR p_internal_replay IS NULL
       OR (
            p_client_protocol IS NOT NULL
            AND p_client_protocol NOT BETWEEN 1 AND 1000
       ) THEN
        RAISE EXCEPTION 'ai_quota_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    -- Global lock order for complimentary completion, terminal settlement,
    -- quota reservation, RevenueCat mutation, and account merge starts with
    -- public.users. External provider work happens outside this transaction.
    SELECT
        users.subscription_tier,
        users.created_at,
        users.subscription_expires_at,
        users.entitlement_version
    INTO app_user
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT config.*
    INTO rollout
    FROM internal.entitlement_rollout_config AS config
    WHERE config.config_key = 'current'
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    IF main_scan_operation
       AND NOT p_internal_replay
       AND rollout.required_client_protocol > 0
       AND p_client_protocol IS DISTINCT FROM
            rollout.required_client_protocol THEN
        RAISE EXCEPTION 'client_update_required'
            USING ERRCODE = 'P0001';
    END IF;

    quota_now := pg_catalog.CLOCK_TIMESTAMP();

    -- An active idempotent reservation owns its original classification. A
    -- later purchase or newly available credit cannot change a replayed
    -- request from Flash to Pro (or acquire an orphaned hold).
    SELECT reservations.*
    INTO active_reservation
    FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.user_id = p_user_id
      AND reservations.operation = p_operation
      AND reservations.request_id = p_request_id
      AND (
          reservations.state = 'committed'
          OR (
              reservations.state = 'reserved'
              AND reservations.lease_expires_at > quota_now
          )
      );

    IF FOUND THEN
        resolved_plan := active_reservation.effective_plan;
        resolved_link := active_reservation.complimentary_client_scan_id;
        resolved_flash_fallback :=
            active_reservation.flash_fallback_used;
    ELSE
        IF app_user.subscription_tier =
                'pro'::public.subscription_tier_enum
           AND (
                app_user.subscription_expires_at IS NULL
                OR app_user.subscription_expires_at > quota_now
           ) THEN
            -- Paid scans never create, consume, or erase a complimentary hold.
            resolved_plan := 'pro_paid';
        ELSIF rollout.entitlement_mode = 'legacy_trial' THEN
            resolved_plan := internal.effective_plan(
                app_user.subscription_tier,
                app_user.created_at,
                app_user.subscription_expires_at
            );
        ELSIF main_scan_operation THEN
            IF p_original_analysis_id IS NULL THEN
                RAISE EXCEPTION 'ai_quota_invalid_request'
                    USING ERRCODE = '22023';
            END IF;

            SELECT usage.*
            INTO usage_row
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = p_user_id
              AND usage.client_scan_id = p_original_analysis_id
            FOR UPDATE;

            IF FOUND AND usage_row.state IN ('held', 'consumed') THEN
                resolved_plan := 'pro_complimentary';
                resolved_link := p_original_analysis_id;
            ELSE
                SELECT
                    pg_catalog.COUNT(*) FILTER (
                        WHERE usage.state = 'consumed'
                    )::INTEGER,
                    pg_catalog.COUNT(*) FILTER (
                        WHERE usage.state = 'held'
                    )::INTEGER
                INTO consumed_count, held_count
                FROM internal.complimentary_scan_usage AS usage
                WHERE usage.user_id = p_user_id;

                consumed_count := COALESCE(consumed_count, 0);
                held_count := COALESCE(held_count, 0);

                IF rollout.complimentary_scan_grant
                        - consumed_count - held_count > 0 THEN
                    IF usage_row.user_id IS NULL THEN
                        INSERT INTO internal.complimentary_scan_usage (
                            user_id,
                            client_scan_id,
                            state,
                            held_at,
                            created_at,
                            updated_at
                        )
                        VALUES (
                            p_user_id,
                            p_original_analysis_id,
                            'held',
                            quota_now,
                            quota_now,
                            quota_now
                        );
                    ELSE
                        UPDATE internal.complimentary_scan_usage AS usage
                        SET state = 'held',
                            held_at = quota_now,
                            settled_at = NULL,
                            settlement_reason = NULL,
                            reacquisition_count =
                                usage.reacquisition_count + 1,
                            updated_at = quota_now
                        WHERE usage.user_id = p_user_id
                          AND usage.client_scan_id =
                                p_original_analysis_id;
                    END IF;

                    resolved_plan := 'pro_complimentary';
                    resolved_link := p_original_analysis_id;
                    usage_changed := TRUE;
                ELSIF p_flash_fallback_eligible THEN
                    resolved_plan := 'free';
                    resolved_flash_fallback := TRUE;
                ELSE
                    RAISE EXCEPTION 'ai_entitlement_required'
                        USING ERRCODE = 'P0001';
                END IF;
            END IF;
        ELSE
            SELECT entitlement.*
            INTO entitlement_after
            FROM internal.resolve_effective_entitlement(
                p_user_id
            ) AS entitlement;

            resolved_plan := entitlement_after.current_plan;
            IF resolved_plan = 'free' THEN
                -- The policy matrix remains authoritative for whether this
                -- non-scan operation has a free implementation.
                resolved_plan := 'free';
            END IF;

            IF p_original_analysis_id IS NOT NULL
               AND EXISTS (
                    SELECT 1
                    FROM internal.complimentary_scan_usage AS usage
                    WHERE usage.user_id = p_user_id
                      AND usage.client_scan_id = p_original_analysis_id
                      AND usage.state IN ('held', 'consumed')
               ) THEN
                resolved_link := p_original_analysis_id;
            END IF;
        END IF;
    END IF;

    IF usage_changed THEN
        UPDATE public.users AS users
        SET complimentary_entitlement_epoch =
                users.complimentary_entitlement_epoch + 1
        WHERE users.id = p_user_id;
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'merian.quota_v2_fence',
        'on',
        TRUE
    );
    PERFORM pg_catalog.SET_CONFIG(
        'merian.entitlement_plan_override',
        resolved_plan,
        TRUE
    );

    -- Delegate idempotency, leases, policy lookup, and provider rate/cost
    -- counters to the established routine. The wrapper only owns functional
    -- entitlement and complimentary usage linkage.
    SELECT quota.*
    INTO STRICT quota_result
    FROM public.reserve_ai_quota(
        p_user_id,
        p_operation,
        p_request_id,
        p_ip_hash
    ) AS quota;

    SELECT entitlement.*
    INTO STRICT entitlement_after
    FROM internal.resolve_effective_entitlement(
        p_user_id
    ) AS entitlement;

    UPDATE internal.ai_quota_reservations AS reservations
    SET effective_plan = resolved_plan,
        effective_tier = CASE
            WHEN resolved_plan IN (
                'pro_paid',
                'pro_trial',
                'pro_complimentary'
            ) THEN 'pro'
            ELSE 'free'
        END,
        subscription_tier = CASE
            WHEN resolved_plan = 'pro_paid' THEN 'pro'
            ELSE 'free'
        END,
        trial_active = resolved_plan = 'pro_trial',
        original_analysis_id = COALESCE(
            reservations.original_analysis_id,
            p_original_analysis_id
        ),
        complimentary_client_scan_id = COALESCE(
            reservations.complimentary_client_scan_id,
            resolved_link
        ),
        client_protocol = COALESCE(
            reservations.client_protocol,
            p_client_protocol
        ),
        flash_fallback_used =
            reservations.flash_fallback_used
            OR resolved_flash_fallback,
        entitlement_version = entitlement_after.entitlement_version,
        updated_at = quota_now
    WHERE reservations.id = quota_result.reservation_id
    RETURNING reservations.* INTO STRICT updated_reservation;

    RETURN QUERY
    SELECT
        updated_reservation.id,
        updated_reservation.request_id,
        updated_reservation.lease_token,
        updated_reservation.lease_expires_at,
        updated_reservation.state,
        quota_result.is_replay,
        updated_reservation.attempt_count,
        updated_reservation.model,
        updated_reservation.effective_plan,
        updated_reservation.effective_tier,
        updated_reservation.subscription_tier,
        updated_reservation.trial_active,
        updated_reservation.entitlement_version,
        updated_reservation.policy_version,
        updated_reservation.daily_limit,
        updated_reservation.daily_remaining_after_reservation,
        updated_reservation.original_analysis_id,
        updated_reservation.complimentary_client_scan_id,
        updated_reservation.flash_fallback_used,
        entitlement_after.scans_remaining,
        entitlement_after.scans_available_to_start,
        entitlement_after.in_flight_count;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_ai_quota(
    UUID,
    TEXT,
    UUID,
    TEXT,
    UUID,
    BOOLEAN,
    INTEGER,
    BOOLEAN
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_ai_quota(
    UUID,
    TEXT,
    UUID,
    TEXT,
    UUID,
    BOOLEAN,
    INTEGER,
    BOOLEAN
) TO service_role;

COMMENT ON FUNCTION public.reserve_ai_quota(
    UUID,
    TEXT,
    UUID,
    TEXT,
    UUID,
    BOOLEAN,
    INTEGER,
    BOOLEAN
) IS
    'Service-only protocol-2 reservation. Locks user first, atomically acquires at most three lifetime holds, and delegates provider counters to the existing quota ledger.';

CREATE OR REPLACE FUNCTION public.fail_scan_ingestion_terminal(
    p_scan_id UUID,
    p_user_id UUID,
    p_stage TEXT,
    p_last_error TEXT,
    p_terminal_reason_code TEXT
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    usage_released BOOLEAN := FALSE;
    entitlement_after RECORD;
    settlement_now TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR p_stage IS NULL
       OR p_stage !~ '^[a-z][a-z0-9_]{1,79}$'
       OR p_terminal_reason_code IS NULL
       OR p_terminal_reason_code !~ '^[a-z][a-z0-9_]{1,63}$'
       OR pg_catalog.CHAR_LENGTH(COALESCE(p_last_error, '')) > 2000 THEN
        RAISE EXCEPTION 'invalid_scan_terminal_failure'
            USING ERRCODE = '22023';
    END IF;

    -- User -> ingestion job is the same order as reservation, completion,
    -- RevenueCat state changes, and Ghost merging.
    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'merian.complimentary_terminal_fence',
        p_user_id::TEXT || ':' || p_scan_id::TEXT,
        TRUE
    );
    settlement_now := pg_catalog.CLOCK_TIMESTAMP();

    UPDATE public.scan_ingestion_jobs AS jobs
    SET status = 'failed_terminal',
        stage = p_stage,
        last_error = p_last_error,
        retry_after = NULL,
        terminal_reason_code = p_terminal_reason_code,
        locked_at = NULL,
        lock_expires_at = NULL,
        completed_at = NULL,
        updated_at = settlement_now
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
      AND jobs.status NOT IN ('complete', 'failed_terminal');

    UPDATE internal.complimentary_scan_usage AS usage
    SET state = 'released',
        settled_at = settlement_now,
        settlement_reason = p_terminal_reason_code,
        updated_at = settlement_now
    WHERE usage.user_id = p_user_id
      AND usage.client_scan_id = p_scan_id
      AND usage.state = 'held';
    usage_released := FOUND;

    IF usage_released THEN
        UPDATE public.users AS users
        SET complimentary_entitlement_epoch =
                users.complimentary_entitlement_epoch + 1
        WHERE users.id = p_user_id;
    END IF;

    SELECT entitlement.*
    INTO STRICT entitlement_after
    FROM internal.resolve_effective_entitlement(
        p_user_id
    ) AS entitlement;

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'credit_released', usage_released,
        'settlement_reason', p_terminal_reason_code,
        'entitlement_after', pg_catalog.TO_JSONB(entitlement_after)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.fail_scan_ingestion_terminal(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fail_scan_ingestion_terminal(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT
) TO service_role;

COMMENT ON FUNCTION public.fail_scan_ingestion_terminal(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT
) IS
    'Service-only user-first terminal job transition and complimentary hold release. It never refunds provider quota counters.';

CREATE OR REPLACE FUNCTION public.complete_scan_ingestion_with_entitlement(
    p_scan_id UUID,
    p_user_id UUID,
    p_response_envelope JSONB,
    p_promoted_urls_by_storage_key JSONB,
    p_deleted_storage_keys TEXT[]
)
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    finalization_result TEXT;
    app_user RECORD;
    usage_row internal.complimentary_scan_usage%ROWTYPE;
    entitlement_after RECORD;
    plan_used TEXT;
    credit_consumed BOOLEAN := FALSE;
    usage_changed BOOLEAN := FALSE;
    entitlement_metadata JSONB;
    enriched_response JSONB;
    stored_response JSONB;
    response_is_required BOOLEAN;
    settlement_now TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL
       OR p_user_id IS NULL
       OR pg_catalog.JSONB_TYPEOF(
            COALESCE(p_promoted_urls_by_storage_key, '{}'::JSONB)
       ) <> 'object'
       OR pg_catalog.CARDINALITY(
            COALESCE(p_deleted_storage_keys, '{}'::TEXT[])
       ) > 128
       OR (
            p_response_envelope IS NOT NULL
            AND (
                pg_catalog.JSONB_TYPEOF(p_response_envelope) = 'object'
                AND pg_catalog.JSONB_TYPEOF(
                    p_response_envelope -> 'data'
                ) = 'object'
                AND pg_catalog.JSONB_TYPEOF(
                    p_response_envelope -> 'success'
                ) = 'boolean'
                AND p_response_envelope -> 'success' = 'true'::JSONB
                AND pg_catalog.JSONB_TYPEOF(
                    p_response_envelope #> '{data,scan_id}'
                ) = 'string'
                AND p_response_envelope #>> '{data,scan_id}' =
                    p_scan_id::TEXT
                AND pg_catalog.OCTET_LENGTH(
                    p_response_envelope::TEXT
                ) <= 262144
            ) IS NOT TRUE
       ) THEN
        RAISE EXCEPTION 'invalid_scan_response_envelope'
            USING ERRCODE = '22023';
    END IF;

    -- The only public completion entry point after cutover. This user lock is
    -- intentionally acquired before the established scan advisory/job/scan
    -- locks inside complete_scan_ingestion_finalization.
    SELECT
        users.subscription_tier,
        users.subscription_expires_at
    INTO app_user
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'merian.complimentary_completion_fence',
        p_user_id::TEXT || ':' || p_scan_id::TEXT,
        TRUE
    );

    finalization_result := public.complete_scan_ingestion_finalization(
        p_scan_id,
        p_user_id,
        COALESCE(p_promoted_urls_by_storage_key, '{}'::JSONB),
        COALESCE(p_deleted_storage_keys, '{}'::TEXT[])
    );

    response_is_required := finalization_result IN (
        'completed',
        'already_complete'
    ) AND EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = p_scan_id
          AND scans.user_id = p_user_id
    );

    IF NOT response_is_required THEN
        RETURN pg_catalog.JSONB_BUILD_OBJECT(
            'result', finalization_result,
            'response_envelope', NULL
        );
    END IF;

    SELECT usage.*
    INTO usage_row
    FROM internal.complimentary_scan_usage AS usage
    WHERE usage.user_id = p_user_id
      AND usage.client_scan_id = p_scan_id
    FOR UPDATE;
    settlement_now := pg_catalog.CLOCK_TIMESTAMP();

    IF FOUND AND usage_row.state = 'held' THEN
        IF app_user.subscription_tier =
                'pro'::public.subscription_tier_enum
           AND (
                app_user.subscription_expires_at IS NULL
                OR app_user.subscription_expires_at > settlement_now
           ) THEN
            UPDATE internal.complimentary_scan_usage AS usage
            SET state = 'released',
                settled_at = settlement_now,
                settlement_reason = 'paid_before_completion',
                updated_at = settlement_now
            WHERE usage.user_id = p_user_id
              AND usage.client_scan_id = p_scan_id;
        ELSE
            UPDATE internal.complimentary_scan_usage AS usage
            SET state = 'consumed',
                settled_at = settlement_now,
                settlement_reason = 'durable_result_complete',
                updated_at = settlement_now
            WHERE usage.user_id = p_user_id
              AND usage.client_scan_id = p_scan_id;
            credit_consumed := TRUE;
        END IF;
        usage_changed := TRUE;
    ELSIF FOUND AND usage_row.state = 'consumed' THEN
        -- A replay reports how the stored result was funded, not whether this
        -- invocation performed the already-durable transition.
        credit_consumed := TRUE;
    END IF;

    IF usage_changed THEN
        UPDATE public.users AS users
        SET complimentary_entitlement_epoch =
                users.complimentary_entitlement_epoch + 1
        WHERE users.id = p_user_id;
    END IF;

    SELECT reservations.effective_plan
    INTO plan_used
    FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.user_id = p_user_id
      AND reservations.original_analysis_id = p_scan_id
      AND reservations.operation IN (
          'scan_identification',
          'scan_audio_identification'
      )
    ORDER BY reservations.created_at DESC, reservations.id DESC
    LIMIT 1;

    IF plan_used IS NULL THEN
        plan_used := CASE
            WHEN usage_row.state IN ('held', 'consumed')
                THEN 'pro_complimentary'
            WHEN app_user.subscription_tier =
                    'pro'::public.subscription_tier_enum
                THEN 'pro_paid'
            ELSE 'free'
        END;
    END IF;

    SELECT entitlement.*
    INTO STRICT entitlement_after
    FROM internal.resolve_effective_entitlement(
        p_user_id
    ) AS entitlement;

    entitlement_metadata := pg_catalog.JSONB_BUILD_OBJECT(
        'user_id', p_user_id,
        'plan_used', plan_used,
        'credit_consumed', credit_consumed,
        'entitlement_after', pg_catalog.TO_JSONB(entitlement_after)
    );

    IF p_response_envelope IS NOT NULL THEN
        enriched_response := p_response_envelope
            || pg_catalog.JSONB_BUILD_OBJECT(
                'entitlement', entitlement_metadata
            );
    END IF;

    UPDATE public.scan_ingestion_jobs AS jobs
    SET response_envelope = CASE
            WHEN jobs.response_envelope IS NULL
                THEN enriched_response
            WHEN NOT jobs.response_envelope ? 'entitlement'
                THEN jobs.response_envelope
                    || pg_catalog.JSONB_BUILD_OBJECT(
                        'entitlement', entitlement_metadata
                    )
            ELSE jobs.response_envelope
        END,
        updated_at = CASE
            WHEN jobs.response_envelope IS NULL
              OR NOT jobs.response_envelope ? 'entitlement'
                THEN settlement_now
            ELSE jobs.updated_at
        END
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
      AND jobs.status = 'complete'
      AND (
          jobs.response_envelope IS NOT NULL
          OR enriched_response IS NOT NULL
      )
    RETURNING jobs.response_envelope INTO stored_response;

    IF p_response_envelope IS NOT NULL
       AND stored_response IS NULL THEN
        RAISE EXCEPTION 'scan_response_persistence_failed'
            USING ERRCODE = '55000';
    END IF;

    RETURN pg_catalog.JSONB_BUILD_OBJECT(
        'result', finalization_result,
        'response_envelope', COALESCE(
            stored_response,
            enriched_response
        ),
        'entitlement', entitlement_metadata
    );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_scan_ingestion_with_entitlement(
    UUID,
    UUID,
    JSONB,
    JSONB,
    TEXT[]
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.complete_scan_ingestion_with_entitlement(
    UUID,
    UUID,
    JSONB,
    JSONB,
    TEXT[]
) TO service_role;

COMMENT ON FUNCTION public.complete_scan_ingestion_with_entitlement(
    UUID,
    UUID,
    JSONB,
    JSONB,
    TEXT[]
) IS
    'Service-only user-first completion orchestrator. Finalizes required media, settles the complimentary hold, enriches the canonical response, and stores it in one transaction.';

-- Extend the existing completion fence instead of duplicating the substantial
-- media finalizer. Direct lower-level completion is rejected only when it
-- would bypass a held complimentary analysis after cutover.
CREATE OR REPLACE FUNCTION internal.enforce_scan_ingestion_completion_fence()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    expected_fence TEXT;
    active_fence TEXT;
    complimentary_fence TEXT;
    terminal_fence TEXT;
    reparenting_enabled BOOLEAN;
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.status = 'failed_terminal'
       AND OLD.status IS DISTINCT FROM 'failed_terminal'
       AND EXISTS (
            SELECT 1
            FROM internal.entitlement_rollout_config AS config
            JOIN internal.complimentary_scan_usage AS usage
              ON usage.user_id = NEW.user_id
             AND usage.client_scan_id::TEXT =
                    pg_catalog.LOWER(NEW.scan_id)
             AND usage.state = 'held'
            WHERE config.config_key = 'current'
              AND config.entitlement_mode = 'complimentary'
       ) THEN
        expected_fence := NEW.user_id::TEXT || ':' ||
            (NEW.scan_id::UUID)::TEXT;
        terminal_fence := pg_catalog.CURRENT_SETTING(
            'merian.complimentary_terminal_fence',
            TRUE
        );
        IF terminal_fence IS DISTINCT FROM expected_fence THEN
            RAISE EXCEPTION
                'complimentary_terminal_requires_orchestrator'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.status = 'complete' THEN
        IF NEW.status <> 'complete'
           OR NEW.scan_id IS DISTINCT FROM OLD.scan_id THEN
            RAISE EXCEPTION 'scan_ingestion_completed_generation_immutable'
                USING ERRCODE = '55000';
        END IF;

        IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
            reparenting_enabled :=
                pg_catalog.CURRENT_SETTING(
                    'internal.ai_usage_reparenting',
                    TRUE
                ) = 'on'
                AND pg_catalog.CURRENT_SETTING(
                    'internal.ai_usage_reparent_source',
                    TRUE
                ) = OLD.user_id::TEXT
                AND pg_catalog.CURRENT_SETTING(
                    'internal.ai_usage_reparent_target',
                    TRUE
                ) = NEW.user_id::TEXT;
            IF NOT COALESCE(reparenting_enabled, FALSE) THEN
                RAISE EXCEPTION
                    'scan_ingestion_completed_generation_immutable'
                    USING ERRCODE = '55000';
            END IF;
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.status <> 'complete' THEN
        RETURN NEW;
    END IF;

    expected_fence := NEW.user_id::TEXT || ':' || (NEW.scan_id::UUID)::TEXT;
    active_fence := pg_catalog.CURRENT_SETTING(
        'merian.scan_ingestion_completion_fence',
        TRUE
    );
    IF active_fence IS DISTINCT FROM expected_fence THEN
        RAISE EXCEPTION 'scan_ingestion_completion_requires_finalization'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.entitlement_rollout_config AS config
        JOIN internal.complimentary_scan_usage AS usage
          ON usage.user_id = NEW.user_id
         AND usage.client_scan_id = NEW.scan_id::UUID
         AND usage.state = 'held'
        WHERE config.config_key = 'current'
          AND config.entitlement_mode = 'complimentary'
    ) THEN
        complimentary_fence := pg_catalog.CURRENT_SETTING(
            'merian.complimentary_completion_fence',
            TRUE
        );
        IF complimentary_fence IS DISTINCT FROM expected_fence THEN
            RAISE EXCEPTION
                'complimentary_completion_requires_orchestrator'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'scan_ingestion_completion_requires_finalization'
            USING ERRCODE = '55000';
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_scan_ingestion_completion_fence()
    FROM PUBLIC, anon, authenticated, service_role;

-- The historical replay claimer terminalized exhausted jobs while already
-- holding their job rows. Settle those rows through the user-first
-- orchestrator before claiming the remaining retryable work.
CREATE OR REPLACE FUNCTION public.claim_replayable_scan_ingestion_jobs(
    p_limit INTEGER DEFAULT 5,
    p_lease_seconds INTEGER DEFAULT 300
)
RETURNS TABLE (
    scan_id TEXT,
    user_id UUID,
    endpoint TEXT,
    status TEXT,
    stage TEXT,
    attempt_count INTEGER,
    media_counts JSONB,
    media_object_keys JSONB,
    upload_session_ids UUID[],
    manifest_checksum TEXT,
    request_payload JSONB,
    payload_checksum TEXT,
    replay_attempt_count INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    claim_limit INTEGER := LEAST(
        GREATEST(COALESCE(p_limit, 5), 1),
        50
    );
    lease_seconds INTEGER := GREATEST(
        COALESCE(p_lease_seconds, 300),
        30
    );
    max_replay_attempts INTEGER := 10;
    over_budget_job RECORD;
BEGIN
    PERFORM internal.require_service_role();

    FOR over_budget_job IN
        SELECT jobs.scan_id, jobs.user_id
        FROM public.scan_ingestion_jobs AS jobs
        JOIN public.scan_ingestion_intents AS intents
          ON intents.user_id = jobs.user_id
         AND intents.scan_id = jobs.scan_id
         AND intents.endpoint = jobs.endpoint
        WHERE jobs.endpoint = 'identify-multimodal'
          AND jobs.status IN (
              'processing',
              'finalizing',
              'retrying',
              'failed_retryable'
          )
          AND intents.resumable
          AND NOT intents.inline_media_redacted
          AND pg_catalog.JSONB_TYPEOF(intents.request_payload) = 'object'
          AND intents.replay_attempt_count >= max_replay_attempts
          AND (
              (
                  jobs.status IN ('failed_retryable', 'retrying')
                  AND (
                      jobs.retry_after IS NULL
                      OR jobs.retry_after <= pg_catalog.NOW()
                  )
              )
              OR (
                  jobs.status IN ('processing', 'finalizing')
                  AND jobs.lock_expires_at IS NOT NULL
                  AND jobs.lock_expires_at <= pg_catalog.NOW()
              )
          )
        ORDER BY
            jobs.user_id,
            COALESCE(
                jobs.retry_after,
                jobs.lock_expires_at,
                jobs.updated_at
            ),
            jobs.scan_id
        LIMIT claim_limit
    LOOP
        PERFORM public.fail_scan_ingestion_terminal(
            over_budget_job.scan_id::UUID,
            over_budget_job.user_id,
            'server_replay_limit_reached',
            'Server replay retry limit reached after 10 attempts.',
            'replay_exhausted'
        );
    END LOOP;

    RETURN QUERY
    WITH candidates AS (
        SELECT
            jobs.id AS job_id,
            intents.id AS intent_id
        FROM public.scan_ingestion_jobs AS jobs
        JOIN public.scan_ingestion_intents AS intents
          ON intents.user_id = jobs.user_id
         AND intents.scan_id = jobs.scan_id
         AND intents.endpoint = jobs.endpoint
        WHERE jobs.endpoint = 'identify-multimodal'
          AND jobs.status IN (
              'processing',
              'finalizing',
              'retrying',
              'failed_retryable'
          )
          AND intents.resumable
          AND NOT intents.inline_media_redacted
          AND pg_catalog.JSONB_TYPEOF(intents.request_payload) = 'object'
          AND intents.replay_attempt_count < max_replay_attempts
          AND (
              (
                  jobs.status IN ('failed_retryable', 'retrying')
                  AND (
                      jobs.retry_after IS NULL
                      OR jobs.retry_after <= pg_catalog.NOW()
                  )
              )
              OR (
                  jobs.status IN ('processing', 'finalizing')
                  AND jobs.lock_expires_at IS NOT NULL
                  AND jobs.lock_expires_at <= pg_catalog.NOW()
              )
          )
        ORDER BY
            COALESCE(
                jobs.retry_after,
                jobs.lock_expires_at,
                jobs.updated_at
            ),
            jobs.updated_at
        LIMIT claim_limit
        FOR UPDATE OF jobs SKIP LOCKED
    ), updated_jobs AS (
        UPDATE public.scan_ingestion_jobs AS jobs
        SET status = 'retrying',
            stage = 'server_replay_claimed',
            locked_at = pg_catalog.NOW(),
            lock_expires_at = pg_catalog.NOW()
                + pg_catalog.MAKE_INTERVAL(secs => lease_seconds),
            retry_after = NULL,
            last_error = NULL,
            terminal_reason_code = NULL,
            updated_at = pg_catalog.NOW()
        FROM candidates
        WHERE jobs.id = candidates.job_id
          AND jobs.status NOT IN ('complete', 'failed_terminal')
        RETURNING jobs.*
    ), updated_intents AS (
        UPDATE public.scan_ingestion_intents AS intents
        SET last_replayed_at = pg_catalog.NOW(),
            replay_attempt_count = intents.replay_attempt_count + 1,
            last_replay_error = NULL,
            updated_at = pg_catalog.NOW()
        FROM candidates
        WHERE intents.id = candidates.intent_id
        RETURNING intents.*
    )
    SELECT
        updated_jobs.scan_id,
        updated_jobs.user_id,
        updated_jobs.endpoint,
        updated_jobs.status,
        updated_jobs.stage,
        updated_jobs.attempt_count,
        updated_jobs.media_counts,
        updated_jobs.media_object_keys,
        updated_jobs.upload_session_ids,
        updated_jobs.manifest_checksum,
        updated_intents.request_payload,
        updated_intents.payload_checksum,
        updated_intents.replay_attempt_count
    FROM updated_jobs
    JOIN updated_intents
      ON updated_intents.user_id = updated_jobs.user_id
     AND updated_intents.scan_id = updated_jobs.scan_id
     AND updated_intents.endpoint = updated_jobs.endpoint;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_replayable_scan_ingestion_jobs(
    INTEGER,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_replayable_scan_ingestion_jobs(
    INTEGER,
    INTEGER
) TO service_role;

COMMENT ON FUNCTION public.claim_replayable_scan_ingestion_jobs(
    INTEGER,
    INTEGER
) IS
    'Service-only replay claimer. Exhausted work is settled user-first before remaining retryable jobs are leased.';

-- Scan deletion can race media finalization. Lock the user before the existing
-- advisory/scan locks and terminalize an incomplete generation through the
-- same complimentary settlement routine.
CREATE OR REPLACE FUNCTION public.request_scan_deletion(
    p_scan_id UUID,
    p_user_id UUID
)
RETURNS TEXT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    scan_owner UUID;
    tombstone_owner UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_scan_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'invalid_scan_deletion_identity'
            USING ERRCODE = '22023';
    END IF;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'scan_deletion_user_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'merian-scan-ingestion:' || p_scan_id::TEXT,
            0::BIGINT
        )
    );

    SELECT scans.user_id
    INTO scan_owner
    FROM public.scans AS scans
    WHERE scans.id = p_scan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        SELECT tombstones.user_id
        INTO tombstone_owner
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = p_scan_id;

        IF FOUND AND tombstone_owner IS NOT DISTINCT FROM p_user_id THEN
            RETURN 'already_deleted';
        END IF;
        RETURN 'not_found';
    END IF;

    IF scan_owner IS DISTINCT FROM p_user_id THEN
        RETURN 'forbidden';
    END IF;

    INSERT INTO internal.scan_deletion_tombstones (
        scan_id,
        user_id
    )
    VALUES (
        p_scan_id,
        p_user_id
    )
    ON CONFLICT (scan_id) DO NOTHING;

    SELECT tombstones.user_id
    INTO STRICT tombstone_owner
    FROM internal.scan_deletion_tombstones AS tombstones
    WHERE tombstones.scan_id = p_scan_id;

    IF tombstone_owner IS DISTINCT FROM p_user_id THEN
        RETURN 'forbidden';
    END IF;

    PERFORM public.fail_scan_ingestion_terminal(
        p_scan_id,
        p_user_id,
        'user_deleted',
        NULL,
        'user_deleted'
    );

    UPDATE public.scan_ingestion_jobs AS jobs
    SET completed_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE jobs.scan_id = p_scan_id::TEXT
      AND jobs.user_id = p_user_id
      AND jobs.status = 'failed_terminal'
      AND jobs.terminal_reason_code = 'user_deleted';

    RETURN 'accepted';
END;
$$;

REVOKE ALL ON FUNCTION public.request_scan_deletion(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.request_scan_deletion(UUID, UUID)
    TO service_role;

COMMENT ON FUNCTION public.request_scan_deletion(UUID, UUID) IS
    'Service-only user-first owner verification, terminal settlement, and permanent scan-generation fence before media erasure.';

INSERT INTO internal.ghost_profile_merge_reference_policies (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column,
    strategy,
    execution_order,
    handler_key,
    purpose
)
VALUES (
    'internal',
    'complimentary_scan_usage',
    'user_id',
    'public',
    'users',
    'id',
    'handler_then_reparent',
    240,
    'complimentary_scan_usage',
    'Deduplicates original analyses, preserves historical consumption, and derives one fixed three-scan grant for the merged permanent account.'
)
ON CONFLICT (
    source_schema,
    source_table,
    source_column,
    referenced_schema,
    referenced_table,
    referenced_column
) DO UPDATE
SET strategy = EXCLUDED.strategy,
    execution_order = EXCLUDED.execution_order,
    handler_key = EXCLUDED.handler_key,
    purpose = EXCLUDED.purpose;

CREATE OR REPLACE FUNCTION internal.merge_ghost_complimentary_scan_usage(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    source_usage_count INTEGER;
    merge_now TIMESTAMPTZ;
BEGIN
    IF p_ghost_user_id IS NULL
       OR p_target_user_id IS NULL
       OR p_ghost_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'ghost_merge_invalid_identity_pair'
            USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO STRICT source_usage_count
    FROM internal.complimentary_scan_usage AS usage
    WHERE usage.user_id = p_ghost_user_id;

    IF source_usage_count = 0 THEN
        RETURN;
    END IF;

    PERFORM usage.client_scan_id
    FROM internal.complimentary_scan_usage AS usage
    WHERE usage.user_id IN (
        p_ghost_user_id,
        p_target_user_id
    )
    ORDER BY usage.user_id, usage.client_scan_id
    FOR UPDATE;
    merge_now := pg_catalog.CLOCK_TIMESTAMP();

    -- Resolve only duplicate original analyses. Distinct consumed rows from
    -- both profiles remain historical evidence; derived balances clamp the
    -- merged account to one grant of three rather than adding two grants.
    UPDATE internal.complimentary_scan_usage AS target_usage
    SET state = CASE
            WHEN target_usage.state = 'consumed'
              OR source_usage.state = 'consumed' THEN 'consumed'
            WHEN target_usage.state = 'held'
              OR source_usage.state = 'held' THEN 'held'
            ELSE 'released'
        END,
        held_at = LEAST(
            target_usage.held_at,
            source_usage.held_at
        ),
        settled_at = CASE
            WHEN (
                target_usage.state = 'held'
                OR source_usage.state = 'held'
            )
              AND target_usage.state <> 'consumed'
              AND source_usage.state <> 'consumed' THEN NULL
            ELSE COALESCE(
                GREATEST(
                    target_usage.settled_at,
                    source_usage.settled_at
                ),
                target_usage.settled_at,
                source_usage.settled_at,
                merge_now
            )
        END,
        settlement_reason = CASE
            WHEN target_usage.state = 'consumed' THEN
                target_usage.settlement_reason
            WHEN source_usage.state = 'consumed' THEN
                source_usage.settlement_reason
            WHEN target_usage.state = 'held'
              OR source_usage.state = 'held' THEN NULL
            ELSE COALESCE(
                target_usage.settlement_reason,
                source_usage.settlement_reason,
                'ghost_merge_released'
            )
        END,
        reacquisition_count =
            target_usage.reacquisition_count
            + source_usage.reacquisition_count,
        created_at = LEAST(
            target_usage.created_at,
            source_usage.created_at
        ),
        updated_at = merge_now
    FROM internal.complimentary_scan_usage AS source_usage
    WHERE target_usage.user_id = p_target_user_id
      AND source_usage.user_id = p_ghost_user_id
      AND source_usage.client_scan_id = target_usage.client_scan_id;

    DELETE FROM internal.complimentary_scan_usage AS source_usage
    USING internal.complimentary_scan_usage AS target_usage
    WHERE source_usage.user_id = p_ghost_user_id
      AND target_usage.user_id = p_target_user_id
      AND target_usage.client_scan_id = source_usage.client_scan_id;

    UPDATE internal.complimentary_scan_usage AS usage
    SET user_id = p_target_user_id,
        updated_at = merge_now
    WHERE usage.user_id = p_ghost_user_id;

    -- A merge combines history, not grants. Keep only the oldest in-flight
    -- analyses that still fit inside one lifetime grant after all historical
    -- consumption is counted; release any excess holds deterministically.
    WITH ranked_holds AS (
        SELECT
            usage.client_scan_id,
            pg_catalog.ROW_NUMBER() OVER (
                ORDER BY usage.held_at, usage.client_scan_id
            ) AS hold_rank,
            GREATEST(
                3 - (
                    SELECT pg_catalog.COUNT(*)::INTEGER
                    FROM internal.complimentary_scan_usage AS consumed_usage
                    WHERE consumed_usage.user_id = p_target_user_id
                      AND consumed_usage.state = 'consumed'
                ),
                0
            ) AS allowed_holds
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.user_id = p_target_user_id
          AND usage.state = 'held'
    )
    UPDATE internal.complimentary_scan_usage AS usage
    SET state = 'released',
        settled_at = merge_now,
        settlement_reason = 'ghost_merge_grant_cap',
        updated_at = merge_now
    FROM ranked_holds
    WHERE usage.user_id = p_target_user_id
      AND usage.client_scan_id = ranked_holds.client_scan_id
      AND ranked_holds.hold_rank > ranked_holds.allowed_holds;

    UPDATE public.users AS users
    SET complimentary_entitlement_epoch =
            users.complimentary_entitlement_epoch + 1
    WHERE users.id = p_target_user_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.merge_ghost_complimentary_scan_usage(
    UUID,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

-- Keep handler dispatch reviewed and hardcoded. The catalog assertion rejects
-- every handler key outside its allowlist, so extend that allowlist before the
-- new policy becomes eligible for merge preflight.
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    guarded_fragment TEXT :=
        '              ''community_activity_actors'',';
    replacement_fragment TEXT :=
        '              ''community_activity_actors'','
        || pg_catalog.CHR(10)
        || '              ''complimentary_scan_usage'',';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
    INTO STRICT function_definition
    FROM (
        SELECT pg_catalog.TO_REGPROCEDURE(
            'internal.assert_ghost_profile_merge_reference_policy_coverage()'
        ) AS routine_oid
    ) AS resolved
    WHERE routine_oid IS NOT NULL;

    IF pg_catalog.STRPOS(
        function_definition,
        '''complimentary_scan_usage'''
    ) <> 0
       OR (
            pg_catalog.LENGTH(function_definition)
            - pg_catalog.LENGTH(
                pg_catalog.REPLACE(
                    function_definition,
                    guarded_fragment,
                    ''
                )
            )
          ) / pg_catalog.LENGTH(guarded_fragment) <> 1 THEN
        RAISE EXCEPTION 'ghost_merge_handler_allowlist_source_drift'
            USING ERRCODE = '55000';
    END IF;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        guarded_fragment,
        replacement_fragment
    );

    IF pg_catalog.STRPOS(
        rewritten_definition,
        '''complimentary_scan_usage'''
    ) = 0 THEN
        RAISE EXCEPTION 'ghost_merge_handler_allowlist_rewrite_failed'
            USING ERRCODE = '55000';
    END IF;

    EXECUTE rewritten_definition;
END;
$migration$;

-- The reviewed Ghost orchestrator already holds both user rows in UUID order.
-- Insert the ledger handler before other conflict handlers and before the
-- policy-driven reparent pass.
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    guarded_fragment TEXT :=
        '    PERFORM internal.merge_ghost_chat_conversations(';
    replacement_fragment TEXT :=
        '    PERFORM internal.merge_ghost_complimentary_scan_usage('
        || pg_catalog.CHR(10)
        || '        p_ghost_user_id,'
        || pg_catalog.CHR(10)
        || '        p_target_user_id'
        || pg_catalog.CHR(10)
        || '    );'
        || pg_catalog.CHR(10)
        || pg_catalog.CHR(10)
        || '    PERFORM internal.merge_ghost_chat_conversations(';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
    INTO STRICT function_definition
    FROM (
        SELECT pg_catalog.TO_REGPROCEDURE(
            'internal.perform_ghost_profile_merge(uuid,uuid)'
        ) AS routine_oid
    ) AS resolved
    WHERE routine_oid IS NOT NULL;

    IF pg_catalog.STRPOS(
        function_definition,
        'merge_ghost_complimentary_scan_usage('
    ) <> 0
       OR (
            pg_catalog.LENGTH(function_definition)
            - pg_catalog.LENGTH(
                pg_catalog.REPLACE(
                    function_definition,
                    guarded_fragment,
                    ''
                )
            )
          ) / pg_catalog.LENGTH(guarded_fragment) <> 1 THEN
        RAISE EXCEPTION 'ghost_merge_complimentary_source_drift'
            USING ERRCODE = '55000';
    END IF;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        guarded_fragment,
        replacement_fragment
    );
    EXECUTE rewritten_definition;
END;
$migration$;

COMMENT ON FUNCTION internal.merge_ghost_complimentary_scan_usage(
    UUID,
    UUID
) IS
    'Deduplicates original analysis rows, reparents the lifetime ledger, preserves consumption, releases excess merged holds, and never adds grants during Ghost-account merge.';

-- Rewire only functional Field Trip and Challenge gates. Public author/profile
-- Pro badges and billing/ghost protection intentionally keep reading the paid
-- subscription_tier directly.
DO $migration$
DECLARE
    routine_row RECORD;
    function_definition TEXT;
    rewritten_definition TEXT;
    rewritten_count INTEGER := 0;
    volatility_rewritten_count INTEGER := 0;
BEGIN
    FOR routine_row IN
        SELECT function_row.oid, function_row.provolatile
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.proname IN (
              'apply_field_trip_scan_progress',
              'apply_field_trip_scan_progress_v2',
              'apply_field_trip_scan_progress_v2_unchecked',
              'apply_field_trip_scan_progress_atomic',
              'apply_field_trip_challenge_scan_progress',
              'get_field_trip_catalog',
              'get_field_trip_template_detail',
              'get_field_trip_capture_context',
              'get_field_trip_community_publications',
              'get_field_trip_challenges_catalog',
              'get_field_trip_challenge_detail',
              'start_field_trip',
              'join_field_trip_challenge'
          )
        ORDER BY function_row.oid
    LOOP
        function_definition := pg_catalog.PG_GET_FUNCTIONDEF(
            routine_row.oid
        );
        rewritten_definition := pg_catalog.REGEXP_REPLACE(
            function_definition,
            $pattern$COALESCE[(]([a-z_][a-z0-9_]*)[.]subscription_tier[[:space:]]*=[[:space:]]*'pro'::(public[.])?subscription_tier_enum,[[:space:]]*FALSE[)]$pattern$,
            $replacement$internal.user_has_effective_pro(\1.id)$replacement$,
            'g'
        );

        IF rewritten_definition IS DISTINCT FROM function_definition THEN
            EXECUTE rewritten_definition;
            IF routine_row.provolatile = 's' THEN
                EXECUTE pg_catalog.FORMAT(
                    'ALTER FUNCTION %s VOLATILE',
                    routine_row.oid::pg_catalog.REGPROCEDURE
                );
                volatility_rewritten_count :=
                    volatility_rewritten_count + 1;
            END IF;
            rewritten_count := rewritten_count + 1;
        END IF;
    END LOOP;

    -- Nine current routines contain an independent paid-tier gate. Keep this
    -- count strict so a renamed or newly wrapped gate cannot silently remain
    -- paid-only after complimentary cutover.
    IF rewritten_count <> 9 THEN
        RAISE EXCEPTION 'functional_entitlement_gate_source_drift'
            USING ERRCODE = '55000';
    END IF;
    -- Six read routines were STABLE before their gate began calling the
    -- VOLATILE resolver. Promote every rewritten stable caller, including the
    -- SQL capture-context routine that plpgsql_check does not report.
    IF volatility_rewritten_count <> 6 THEN
        RAISE EXCEPTION 'functional_entitlement_volatility_source_drift'
            USING ERRCODE = '55000';
    END IF;
END;
$migration$;

-- This stable SQL compatibility wrapper delegates to the now-volatile
-- community catalog. Keep its optimizer contract aligned with that callee.
ALTER FUNCTION public.get_recent_field_trip_publications(
    UUID,
    TEXT,
    TEXT[],
    INTEGER,
    TIMESTAMPTZ,
    UUID
) VOLATILE;

-- Current admin account views must use the user-aware resolver. Retain
-- pro_trial as a valid explicit filter for historical AI usage events.
CREATE OR REPLACE FUNCTION internal.effective_plan_for_user_or_free(
    p_user_id UUID
)
RETURNS TEXT
LANGUAGE PLPGSQL
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    resolved_plan TEXT;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN 'free';
    END IF;

    SELECT entitlement.current_plan
    INTO STRICT resolved_plan
    FROM internal.resolve_effective_entitlement(p_user_id) AS entitlement;
    RETURN resolved_plan;
END;
$$;

REVOKE ALL ON FUNCTION internal.effective_plan_for_user_or_free(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

DO $migration$
DECLARE
    routine_row RECORD;
    function_definition TEXT;
    rewritten_definition TEXT;
    resolver_fragment TEXT :=
        'internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at)';
    replacement_fragment TEXT :=
        'internal.effective_plan_for_user_or_free(app_user.id)';
    overview_trial_fragment TEXT :=
        '''pro_trial'', COUNT(*) FILTER (WHERE internal.effective_plan_for_user_or_free(app_user.id) = ''pro_trial''),';
    overview_plan_fragment TEXT :=
        overview_trial_fragment
        || pg_catalog.CHR(10)
        || '        ''pro_complimentary'', COUNT(*) FILTER (WHERE internal.effective_plan_for_user_or_free(app_user.id) = ''pro_complimentary''),';
BEGIN
    FOR routine_row IN
        SELECT function_row.oid, function_row.proname
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.proname IN (
              'admin_get_overview',
              'admin_list_users',
              'admin_get_user_detail'
          )
    LOOP
        function_definition := pg_catalog.PG_GET_FUNCTIONDEF(
            routine_row.oid
        );
        rewritten_definition := pg_catalog.REPLACE(
            function_definition,
            resolver_fragment,
            replacement_fragment
        );
        rewritten_definition := pg_catalog.REPLACE(
            rewritten_definition,
            'CASE WHEN app_user.id IS NULL THEN ''pro_trial''',
            'CASE WHEN app_user.id IS NULL THEN ''free'''
        );

        IF routine_row.proname = 'admin_get_overview' THEN
            rewritten_definition := pg_catalog.REPLACE(
                rewritten_definition,
                'app_user.id IS NOT NULL AND internal.effective_plan_for_user_or_free(app_user.id) = ''pro_paid''',
                'internal.effective_plan_for_user_or_free(app_user.id) = ''pro_paid'''
            );
            rewritten_definition := pg_catalog.REPLACE(
                rewritten_definition,
                'app_user.id IS NULL OR internal.effective_plan_for_user_or_free(app_user.id) = ''pro_trial''',
                'internal.effective_plan_for_user_or_free(app_user.id) = ''pro_trial'''
            );
            rewritten_definition := pg_catalog.REPLACE(
                rewritten_definition,
                'app_user.id IS NOT NULL AND internal.effective_plan_for_user_or_free(app_user.id) = ''free''',
                'internal.effective_plan_for_user_or_free(app_user.id) = ''free'''
            );
            rewritten_definition := pg_catalog.REPLACE(
                rewritten_definition,
                overview_trial_fragment,
                overview_plan_fragment
            );
        END IF;

        IF routine_row.proname = 'admin_get_user_detail' THEN
            rewritten_definition := pg_catalog.REPLACE(
                rewritten_definition,
                '    ''recent_scans'', (',
                '    ''complimentary_entitlement'', ('
                    || pg_catalog.CHR(10)
                    || '      SELECT pg_catalog.TO_JSONB(entitlement)'
                    || pg_catalog.CHR(10)
                    || '      FROM internal.resolve_effective_entitlement(p_user_id) AS entitlement'
                    || pg_catalog.CHR(10)
                    || '    ),'
                    || pg_catalog.CHR(10)
                    || '    ''complimentary_usage'', ('
                    || pg_catalog.CHR(10)
                    || '      SELECT COALESCE(pg_catalog.JSONB_AGG(pg_catalog.TO_JSONB(usage) ORDER BY usage.created_at DESC), ''[]''::JSONB)'
                    || pg_catalog.CHR(10)
                    || '      FROM internal.complimentary_scan_usage AS usage'
                    || pg_catalog.CHR(10)
                    || '      WHERE usage.user_id = p_user_id'
                    || pg_catalog.CHR(10)
                    || '    ),'
                    || pg_catalog.CHR(10)
                    || '    ''recent_scans'', ('
            );
        END IF;

        IF rewritten_definition IS NOT DISTINCT FROM function_definition
           OR pg_catalog.STRPOS(
                rewritten_definition,
                resolver_fragment
           ) <> 0
           OR (
                routine_row.proname = 'admin_get_overview'
                AND pg_catalog.STRPOS(
                    rewritten_definition,
                    '''pro_complimentary'', COUNT(*) FILTER'
                ) = 0
           )
           OR (
                routine_row.proname = 'admin_get_user_detail'
                AND pg_catalog.STRPOS(
                    rewritten_definition,
                    '''complimentary_entitlement'', ('
                ) = 0
           ) THEN
            RAISE EXCEPTION 'admin_entitlement_resolver_source_drift: %',
                routine_row.proname
                USING ERRCODE = '55000';
        END IF;

        EXECUTE rewritten_definition;
    END LOOP;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.admin_complimentary_entitlement_summary()
RETURNS JSONB
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
    caller_role TEXT;
    result JSONB;
BEGIN
    caller_role := internal.require_admin('analyst');

    WITH per_user AS MATERIALIZED (
        SELECT
            users.id,
            entitlement.is_paid,
            entitlement.scans_remaining,
            entitlement.scans_available_to_start,
            entitlement.in_flight_count,
            entitlement.current_plan
        FROM public.users AS users
        CROSS JOIN LATERAL internal.resolve_effective_entitlement(
            users.id
        ) AS entitlement
    ), state_counts AS (
        SELECT usage.state, pg_catalog.COUNT(*)::BIGINT AS count
        FROM internal.complimentary_scan_usage AS usage
        GROUP BY usage.state
    ), reason_counts AS (
        SELECT
            usage.settlement_reason,
            pg_catalog.COUNT(*)::BIGINT AS count
        FROM internal.complimentary_scan_usage AS usage
        WHERE usage.settlement_reason IS NOT NULL
        GROUP BY usage.settlement_reason
    ), balance_counts AS (
        SELECT
            per_user.scans_available_to_start AS balance,
            pg_catalog.COUNT(*)::BIGINT AS count
        FROM per_user
        GROUP BY per_user.scans_available_to_start
    )
    SELECT pg_catalog.JSONB_BUILD_OBJECT(
        'grant', 3,
        'accounts', (SELECT pg_catalog.COUNT(*) FROM per_user),
        'accounts_with_complimentary_access', (
            SELECT pg_catalog.COUNT(*)
            FROM per_user
            WHERE per_user.current_plan = 'pro_complimentary'
        ),
        'exhausted_accounts', (
            SELECT pg_catalog.COUNT(*)
            FROM per_user
            WHERE per_user.scans_remaining = 0
        ),
        'exhausted_paid_accounts', (
            SELECT pg_catalog.COUNT(*)
            FROM per_user
            WHERE per_user.scans_remaining = 0
              AND per_user.is_paid
        ),
        'in_flight', (
            SELECT COALESCE(pg_catalog.SUM(per_user.in_flight_count), 0)
            FROM per_user
        ),
        'stale_holds_15m', (
            SELECT pg_catalog.COUNT(*)
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.state = 'held'
              AND usage.held_at < pg_catalog.NOW() - INTERVAL '15 minutes'
        ),
        'stale_holds_1h', (
            SELECT pg_catalog.COUNT(*)
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.state = 'held'
              AND usage.held_at < pg_catalog.NOW() - INTERVAL '1 hour'
        ),
        'oldest_hold_at', (
            SELECT pg_catalog.MIN(usage.held_at)
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.state = 'held'
        ),
        'flash_fallback_reservations', (
            SELECT pg_catalog.COUNT(*)
            FROM internal.ai_quota_reservations AS reservations
            WHERE reservations.flash_fallback_used
        ),
        'states', (
            SELECT COALESCE(
                pg_catalog.JSONB_OBJECT_AGG(
                    state_counts.state,
                    state_counts.count
                ),
                '{}'::JSONB
            )
            FROM state_counts
        ),
        'settlement_reasons', (
            SELECT COALESCE(
                pg_catalog.JSONB_OBJECT_AGG(
                    reason_counts.settlement_reason,
                    reason_counts.count
                ),
                '{}'::JSONB
            )
            FROM reason_counts
        ),
        'available_balance_histogram', (
            SELECT COALESCE(
                pg_catalog.JSONB_OBJECT_AGG(
                    balance_counts.balance::TEXT,
                    balance_counts.count
                ),
                '{}'::JSONB
            )
            FROM balance_counts
        )
    ) INTO STRICT result;

    PERFORM internal.write_admin_audit(
        caller_role,
        'complimentary_entitlement_summary_viewed',
        'complimentary_entitlement',
        NULL
    );
    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_complimentary_entitlement_summary()
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_complimentary_entitlement_summary()
    TO authenticated;

COMMENT ON FUNCTION public.admin_complimentary_entitlement_summary() IS
    'Analyst-authorized complimentary balances, hold age, settlement reasons, Flash fallback, exhaustion, and paid-conversion snapshot.';

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'authenticated',
        'public.get_my_entitlement()',
        'Current caller only; returns a versioned snapshot derived from the private complimentary ledger.'
    ),
    (
        'authenticated',
        'public.admin_complimentary_entitlement_summary()',
        'Admin UI; analyst membership, AAL2, and active admin session are checked in-function.'
    ),
    (
        'service_role',
        'public.get_user_entitlement_service(uuid)',
        'Edge-only durable entitlement resolver for a validated authenticated user.'
    ),
    (
        'service_role',
        'public.get_entitlement_rollout_service()',
        'Edge-only rollout fence for atomic legacy-to-complimentary protocol enforcement.'
    ),
    (
        'service_role',
        'public.reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
        'Edge-only protocol-2 quota reservation with original analysis and complimentary usage linkage.'
    ),
    (
        'service_role',
        'public.fail_scan_ingestion_terminal(uuid,uuid,text,text,text)',
        'Edge-only user-first terminal settlement that releases a held complimentary result.'
    ),
    (
        'service_role',
        'public.complete_scan_ingestion_with_entitlement(uuid,uuid,jsonb,jsonb,text[])',
        'Edge-only user-first media completion, complimentary settlement, response enrichment, and immutable replay storage.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

SELECT internal.assert_ghost_profile_merge_reference_policy_coverage();

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;
