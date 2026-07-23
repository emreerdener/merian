-- Make paid-model access a server-owned, transactional decision.
--
-- Every public AI request reserves its quota in the same database transaction
-- that resolves the caller's current entitlement. A reservation is idempotent
-- for (user, operation, request_id). Only a proven pre-provider no-op refunds
-- counters; provider failures remain charged but permit a newly metered retry.

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS entitlement_version BIGINT NOT NULL DEFAULT 1;

COMMENT ON COLUMN public.users.entitlement_version IS
    'Monotonic version of subscription_tier/subscription_expires_at. AI authorization reads this durable value; Edge-isolate caches are not authoritative.';

-- Keep the durable plan resolver authoritative for quota enforcement and
-- operational reporting. A future-dated profile is invalid, not an extended
-- trial.
CREATE OR REPLACE FUNCTION internal.effective_plan(
    p_subscription_tier public.subscription_tier_enum,
    p_created_at TIMESTAMPTZ,
    p_expires_at TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE SQL
STABLE
SET search_path = ''
AS $$
    SELECT CASE
        WHEN p_subscription_tier = 'pro'::public.subscription_tier_enum
          AND (p_expires_at IS NULL OR p_expires_at > pg_catalog.NOW()) THEN 'pro_paid'
        WHEN p_subscription_tier = 'free'::public.subscription_tier_enum
          AND p_created_at <= pg_catalog.NOW()
          AND p_created_at >= pg_catalog.NOW() - INTERVAL '7 days' THEN 'pro_trial'
        ELSE 'free'
    END
$$;

REVOKE ALL ON FUNCTION internal.effective_plan(
    public.subscription_tier_enum, TIMESTAMPTZ, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.bump_user_entitlement_version()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier
       OR NEW.subscription_expires_at IS DISTINCT FROM OLD.subscription_expires_at THEN
        NEW.entitlement_version := OLD.entitlement_version + 1;
    ELSE
        -- Callers cannot forge a new version independently of an entitlement
        -- transition, even when they use a privileged database connection.
        NEW.entitlement_version := OLD.entitlement_version;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.bump_user_entitlement_version()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS bump_user_entitlement_version ON public.users;
CREATE TRIGGER bump_user_entitlement_version
BEFORE UPDATE OF subscription_tier, subscription_expires_at, entitlement_version
ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.bump_user_entitlement_version();

-- The original table-level UPDATE grant allowed a caller to write its own
-- subscription_tier. Preserve only the two user-editable preference columns;
-- identity and billing mutations remain behind reviewed Edge Functions.
REVOKE INSERT, DELETE ON TABLE public.users
    FROM PUBLIC, anon, authenticated;
REVOKE UPDATE ON TABLE public.users FROM PUBLIC, anon, authenticated;

-- Table-level REVOKE does not clear a historical per-column grant. Remove all
-- API-role INSERT/UPDATE column ACLs before adding back the reviewed preference
-- surface.
DO $revoke_user_column_writes$
DECLARE
    column_list TEXT;
BEGIN
    SELECT pg_catalog.STRING_AGG(
        pg_catalog.QUOTE_IDENT(attributes.attname),
        ', '
        ORDER BY attributes.attnum
    )
    INTO column_list
    FROM pg_catalog.pg_attribute AS attributes
    WHERE attributes.attrelid = 'public.users'::pg_catalog.REGCLASS
      AND attributes.attnum > 0
      AND NOT attributes.attisdropped;

    IF column_list IS NOT NULL THEN
        EXECUTE pg_catalog.FORMAT(
            'REVOKE INSERT (%1$s), UPDATE (%1$s) ON TABLE public.users FROM PUBLIC, anon, authenticated',
            column_list
        );
    END IF;
END;
$revoke_user_column_writes$;

GRANT UPDATE (default_geoprivacy, marketing_opt_in)
    ON TABLE public.users TO authenticated;

CREATE TABLE internal.ai_quota_policies (
    operation TEXT NOT NULL,
    effective_plan TEXT NOT NULL,
    model TEXT,
    allowed BOOLEAN NOT NULL DEFAULT TRUE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    policy_version BIGINT NOT NULL DEFAULT 1,
    daily_bucket TEXT,
    daily_limit INTEGER,
    user_rate_bucket TEXT,
    user_window_seconds INTEGER,
    user_window_limit INTEGER,
    ip_rate_bucket TEXT,
    ip_window_seconds INTEGER,
    ip_window_limit INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (operation, effective_plan),
    CONSTRAINT ai_quota_policies_operation_check
        CHECK (
            operation ~ '^[a-z][a-z0-9_]{2,63}$'
        ),
    CONSTRAINT ai_quota_policies_effective_plan_check
        CHECK (effective_plan IN ('free', 'pro_trial', 'pro_paid')),
    CONSTRAINT ai_quota_policies_model_check
        CHECK (
            (
                allowed
                AND model IN ('gemini-2.5-flash', 'gemini-2.5-pro')
            )
            OR (NOT allowed AND model IS NULL)
        ),
    CONSTRAINT ai_quota_policies_policy_version_check
        CHECK (policy_version > 0),
    CONSTRAINT ai_quota_policies_daily_limit_check
        CHECK (
            (daily_bucket IS NULL AND daily_limit IS NULL)
            OR (
                NULLIF(pg_catalog.BTRIM(daily_bucket), '') IS NOT NULL
                AND daily_limit > 0
            )
        ),
    CONSTRAINT ai_quota_policies_user_rate_check
        CHECK (
            (NOT allowed)
            OR (
                NULLIF(pg_catalog.BTRIM(user_rate_bucket), '') IS NOT NULL
                AND user_window_seconds BETWEEN 1 AND 3600
                AND user_window_limit > 0
            )
        ),
    CONSTRAINT ai_quota_policies_ip_rate_check
        CHECK (
            (NOT allowed)
            OR (
                NULLIF(pg_catalog.BTRIM(ip_rate_bucket), '') IS NOT NULL
                AND ip_window_seconds BETWEEN 1 AND 3600
                AND ip_window_limit > 0
            )
        )
);

COMMENT ON TABLE internal.ai_quota_policies IS
    'Database-owned model selection, daily safety ceilings, and per-user/IP rate limits for every externally reachable paid AI operation.';

CREATE TABLE internal.ai_quota_counters (
    scope_type TEXT NOT NULL,
    scope_key TEXT NOT NULL,
    bucket TEXT NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    window_seconds INTEGER NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    PRIMARY KEY (scope_type, scope_key, bucket, window_start),
    CONSTRAINT ai_quota_counters_scope_type_check
        CHECK (scope_type IN ('user_daily', 'user_rate', 'ip_rate')),
    CONSTRAINT ai_quota_counters_scope_key_check
        CHECK (NULLIF(pg_catalog.BTRIM(scope_key), '') IS NOT NULL),
    CONSTRAINT ai_quota_counters_bucket_check
        CHECK (NULLIF(pg_catalog.BTRIM(bucket), '') IS NOT NULL),
    CONSTRAINT ai_quota_counters_window_seconds_check
        CHECK (window_seconds BETWEEN 1 AND 86400),
    CONSTRAINT ai_quota_counters_request_count_check
        CHECK (request_count >= 0)
);

CREATE TABLE internal.ai_quota_reservations (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    operation TEXT NOT NULL,
    request_id UUID NOT NULL,
    state TEXT NOT NULL DEFAULT 'reserved',
    lease_token UUID NOT NULL DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    lease_expires_at TIMESTAMPTZ NOT NULL
        DEFAULT pg_catalog.NOW() + INTERVAL '10 minutes',
    attempt_count INTEGER NOT NULL DEFAULT 1,
    refund_count INTEGER NOT NULL DEFAULT 0,
    stale_recovery_count INTEGER NOT NULL DEFAULT 0,
    model TEXT NOT NULL,
    effective_plan TEXT NOT NULL,
    effective_tier TEXT NOT NULL,
    subscription_tier TEXT NOT NULL,
    trial_active BOOLEAN NOT NULL,
    entitlement_version BIGINT NOT NULL,
    policy_version BIGINT NOT NULL,
    daily_limit INTEGER,
    daily_remaining_after_reservation INTEGER,
    reserved_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    committed_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    refunded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    UNIQUE (user_id, operation, request_id),
    CONSTRAINT ai_quota_reservations_operation_check
        CHECK (operation ~ '^[a-z][a-z0-9_]{2,63}$'),
    CONSTRAINT ai_quota_reservations_state_check
        CHECK (state IN ('reserved', 'committed', 'failed', 'refunded')),
    CONSTRAINT ai_quota_reservations_attempt_count_check
        CHECK (attempt_count > 0),
    CONSTRAINT ai_quota_reservations_refund_count_check
        CHECK (refund_count >= 0),
    CONSTRAINT ai_quota_reservations_stale_recovery_count_check
        CHECK (stale_recovery_count >= 0),
    CONSTRAINT ai_quota_reservations_effective_plan_check
        CHECK (effective_plan IN ('free', 'pro_trial', 'pro_paid')),
    CONSTRAINT ai_quota_reservations_effective_tier_check
        CHECK (effective_tier IN ('free', 'pro')),
    CONSTRAINT ai_quota_reservations_subscription_tier_check
        CHECK (subscription_tier IN ('free', 'pro')),
    CONSTRAINT ai_quota_reservations_entitlement_version_check
        CHECK (entitlement_version > 0),
    CONSTRAINT ai_quota_reservations_policy_version_check
        CHECK (policy_version > 0),
    CONSTRAINT ai_quota_reservations_daily_remaining_check
        CHECK (
            daily_remaining_after_reservation IS NULL
            OR daily_remaining_after_reservation >= 0
        )
);

CREATE INDEX ai_quota_reservations_cleanup_idx
    ON internal.ai_quota_reservations (updated_at, id);

CREATE INDEX ai_quota_reservations_expired_lease_idx
    ON internal.ai_quota_reservations (lease_expires_at, id)
    WHERE state = 'reserved';

CREATE TABLE internal.ai_quota_reservation_counters (
    reservation_id UUID NOT NULL
        REFERENCES internal.ai_quota_reservations(id) ON DELETE CASCADE,
    scope_type TEXT NOT NULL,
    scope_key TEXT NOT NULL,
    bucket TEXT NOT NULL,
    window_start TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (reservation_id, scope_type, scope_key, bucket, window_start),
    CONSTRAINT ai_quota_reservation_counters_scope_type_check
        CHECK (scope_type IN ('user_daily', 'user_rate', 'ip_rate'))
);

CREATE INDEX ai_quota_reservation_counters_lookup_idx
    ON internal.ai_quota_reservation_counters (
        scope_type,
        scope_key,
        bucket,
        window_start
    );

CREATE INDEX ai_quota_counters_cleanup_idx
    ON internal.ai_quota_counters (
        window_start,
        scope_type,
        scope_key,
        bucket
    );

REVOKE ALL ON TABLE
    internal.ai_quota_policies,
    internal.ai_quota_counters,
    internal.ai_quota_reservations,
    internal.ai_quota_reservation_counters
FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.ai_quota_policies (
    operation,
    effective_plan,
    model,
    allowed,
    daily_bucket,
    daily_limit,
    user_rate_bucket,
    user_window_seconds,
    user_window_limit,
    ip_rate_bucket,
    ip_window_seconds,
    ip_window_limit
)
VALUES
    -- One free scan per UTC day. Trial and paid plans receive deliberately
    -- high fair-use ceilings that bound automation without affecting normal use.
    ('scan_identification', 'free', 'gemini-2.5-flash', TRUE, 'scan_inference:free', 1, 'all_ai:free', 60, 4, 'all_ai:free', 60, 30),
    ('scan_identification', 'pro_trial', 'gemini-2.5-pro', TRUE, 'scan_inference:pro_trial', 50, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('scan_identification', 'pro_paid', 'gemini-2.5-pro', TRUE, 'scan_inference:pro_paid', 500, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),
    ('scan_audio_identification', 'free', 'gemini-2.5-flash', TRUE, 'scan_inference:free', 1, 'all_ai:free', 60, 4, 'all_ai:free', 60, 30),
    ('scan_audio_identification', 'pro_trial', 'gemini-2.5-flash', TRUE, 'scan_inference:pro_trial', 50, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('scan_audio_identification', 'pro_paid', 'gemini-2.5-flash', TRUE, 'scan_inference:pro_paid', 500, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),

    -- Cache-miss enrichment calls are paid calls too and must not be an
    -- alternate path around the primary scan quota.
    ('scan_overview_enrichment', 'free', 'gemini-2.5-flash', TRUE, 'scan_enrichment:free', 4, 'all_ai:free', 60, 4, 'all_ai:free', 60, 30),
    ('scan_overview_enrichment', 'pro_trial', 'gemini-2.5-flash', TRUE, 'scan_enrichment:pro_trial', 100, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('scan_overview_enrichment', 'pro_paid', 'gemini-2.5-flash', TRUE, 'scan_enrichment:pro_paid', 500, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),
    ('scan_lookalike_enrichment', 'free', 'gemini-2.5-flash', TRUE, 'scan_enrichment:free', 4, 'all_ai:free', 60, 4, 'all_ai:free', 60, 30),
    ('scan_lookalike_enrichment', 'pro_trial', 'gemini-2.5-flash', TRUE, 'scan_enrichment:pro_trial', 100, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('scan_lookalike_enrichment', 'pro_paid', 'gemini-2.5-flash', TRUE, 'scan_enrichment:pro_paid', 500, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),
    ('scan_group_tag_enrichment', 'free', 'gemini-2.5-flash', TRUE, 'scan_enrichment:free', 4, 'all_ai:free', 60, 4, 'all_ai:free', 60, 30),
    ('scan_group_tag_enrichment', 'pro_trial', 'gemini-2.5-flash', TRUE, 'scan_enrichment:pro_trial', 100, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('scan_group_tag_enrichment', 'pro_paid', 'gemini-2.5-flash', TRUE, 'scan_enrichment:pro_paid', 500, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),
    ('explore_audio_moderation', 'free', 'gemini-2.5-flash', TRUE, 'explore_audio_moderation:free', 3, 'all_ai:free', 60, 4, 'all_ai:free', 60, 30),
    ('explore_audio_moderation', 'pro_trial', 'gemini-2.5-flash', TRUE, 'explore_audio_moderation:pro_trial', 25, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('explore_audio_moderation', 'pro_paid', 'gemini-2.5-flash', TRUE, 'explore_audio_moderation:pro_paid', 100, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),

    -- Chat remains a Pro feature. The shared daily bucket includes replies,
    -- suggestions, and summaries across saved-scan and Explore chat.
    ('insight_chat_reply', 'free', NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('insight_chat_reply', 'pro_trial', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_trial', 60, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('insight_chat_reply', 'pro_paid', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_paid', 120, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),
    ('insight_chat_prompt_suggestions', 'free', NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('insight_chat_prompt_suggestions', 'pro_trial', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_trial', 60, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('insight_chat_prompt_suggestions', 'pro_paid', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_paid', 120, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),
    ('insight_chat_summary', 'free', NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('insight_chat_summary', 'pro_trial', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_trial', 60, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('insight_chat_summary', 'pro_paid', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_paid', 120, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120),
    ('explore_post_chat_reply', 'free', NULL, FALSE, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    ('explore_post_chat_reply', 'pro_trial', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_trial', 60, 'all_ai:pro_trial', 60, 10, 'all_ai:pro_trial', 60, 60),
    ('explore_post_chat_reply', 'pro_paid', 'gemini-2.5-flash', TRUE, 'ai_chat:pro_paid', 120, 'all_ai:pro_paid', 60, 20, 'all_ai:pro_paid', 60, 120)
ON CONFLICT (operation, effective_plan) DO UPDATE
SET
    model = EXCLUDED.model,
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

CREATE OR REPLACE FUNCTION internal.consume_ai_quota_counter(
    p_scope_type TEXT,
    p_scope_key TEXT,
    p_bucket TEXT,
    p_window_start TIMESTAMPTZ,
    p_window_seconds INTEGER,
    p_limit INTEGER,
    p_error_code TEXT
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    resulting_count INTEGER;
BEGIN
    INSERT INTO internal.ai_quota_counters (
        scope_type,
        scope_key,
        bucket,
        window_start,
        window_seconds,
        request_count
    )
    VALUES (
        p_scope_type,
        p_scope_key,
        p_bucket,
        p_window_start,
        p_window_seconds,
        1
    )
    ON CONFLICT (scope_type, scope_key, bucket, window_start)
    DO UPDATE
    SET
        request_count =
            internal.ai_quota_counters.request_count + 1,
        updated_at = pg_catalog.NOW()
    WHERE internal.ai_quota_counters.request_count < p_limit
    RETURNING request_count INTO resulting_count;

    IF resulting_count IS NULL THEN
        RAISE EXCEPTION '%', p_error_code
            USING ERRCODE = 'P0001';
    END IF;

    RETURN resulting_count;
END;
$$;

REVOKE ALL ON FUNCTION internal.consume_ai_quota_counter(
    TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER, INTEGER, TEXT
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.release_ai_quota_reservation_counters(
    p_reservation_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    counter_link RECORD;
BEGIN
    -- Every caller holds the reservation row lock first. Counter rows are then
    -- acquired in the same daily -> user -> IP order as reservation, avoiding
    -- lock-order inversions between explicit refunds and stale-lease recovery.
    FOR counter_link IN
        SELECT links.*
        FROM internal.ai_quota_reservation_counters AS links
        WHERE links.reservation_id = p_reservation_id
        ORDER BY
            CASE links.scope_type
                WHEN 'user_daily' THEN 1
                WHEN 'user_rate' THEN 2
                WHEN 'ip_rate' THEN 3
                ELSE 4
            END,
            links.scope_key,
            links.bucket,
            links.window_start
    LOOP
        UPDATE internal.ai_quota_counters AS counters
        SET
            request_count = GREATEST(counters.request_count - 1, 0),
            updated_at = pg_catalog.NOW()
        WHERE counters.scope_type = counter_link.scope_type
          AND counters.scope_key = counter_link.scope_key
          AND counters.bucket = counter_link.bucket
          AND counters.window_start = counter_link.window_start;

        DELETE FROM internal.ai_quota_counters AS counters
        WHERE counters.scope_type = counter_link.scope_type
          AND counters.scope_key = counter_link.scope_key
          AND counters.bucket = counter_link.bucket
          AND counters.window_start = counter_link.window_start
          AND counters.request_count = 0;
    END LOOP;

    DELETE FROM internal.ai_quota_reservation_counters AS links
    WHERE links.reservation_id = p_reservation_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.release_ai_quota_reservation_counters(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.reserve_ai_quota(
    p_user_id UUID,
    p_operation TEXT,
    p_request_id UUID,
    p_ip_hash TEXT
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
    daily_remaining INTEGER
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    app_user RECORD;
    policy_row internal.ai_quota_policies%ROWTYPE;
    reservation_row internal.ai_quota_reservations%ROWTYPE;
    resolved_plan TEXT;
    resolved_effective_tier TEXT;
    resolved_trial_active BOOLEAN;
    quota_now TIMESTAMPTZ;
    daily_window_start TIMESTAMPTZ;
    user_window_start TIMESTAMPTZ;
    ip_window_start TIMESTAMPTZ;
    resulting_daily_count INTEGER;
    ignored_count INTEGER;
    replayed BOOLEAN := FALSE;
    reservation_found BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_request_id IS NULL
       OR p_operation IS NULL
       OR p_operation !~ '^[a-z][a-z0-9_]{2,63}$'
       OR p_ip_hash IS NULL
       OR p_ip_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'ai_quota_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    SELECT
        users.subscription_tier::TEXT AS subscription_tier,
        users.created_at,
        users.subscription_expires_at,
        users.entitlement_version
    INTO app_user
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR SHARE;

    IF NOT FOUND THEN
        -- A successful Auth signup creates public.users transactionally. A
        -- missing row is therefore an entitlement-system fault, never a trial.
        RAISE EXCEPTION 'ai_entitlement_unavailable'
            USING ERRCODE = 'P0001';
    END IF;

    resolved_plan := internal.effective_plan(
        app_user.subscription_tier::public.subscription_tier_enum,
        app_user.created_at,
        app_user.subscription_expires_at
    );
    resolved_effective_tier :=
        CASE WHEN resolved_plan IN ('pro_trial', 'pro_paid')
            THEN 'pro' ELSE 'free' END;
    resolved_trial_active := resolved_plan = 'pro_trial';

    SELECT policies.*
    INTO policy_row
    FROM internal.ai_quota_policies AS policies
    WHERE policies.operation = p_operation
      AND policies.effective_plan = resolved_plan
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_quota_policy_missing'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.enabled THEN
        RAISE EXCEPTION 'ai_quota_policy_disabled'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.allowed THEN
        RAISE EXCEPTION 'ai_entitlement_required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Serialize only identical idempotency keys. All quota counters still use
    -- conditional UPSERTs, so unrelated requests never share this lock.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTENDED(
            p_user_id::TEXT || ':' || p_operation || ':' || p_request_id::TEXT,
            0
        )
    );

    SELECT reservations.*
    INTO reservation_row
    FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.user_id = p_user_id
      AND reservations.operation = p_operation
      AND reservations.request_id = p_request_id
    FOR UPDATE;
    reservation_found := FOUND;

    -- CLOCK_TIMESTAMP must be read after any advisory/row-lock wait. Using a
    -- timestamp captured before the wait can incorrectly extend a stale lease.
    quota_now := pg_catalog.CLOCK_TIMESTAMP();

    IF reservation_found AND (
        reservation_row.state = 'committed'
        OR (
            reservation_row.state = 'reserved'
            AND reservation_row.lease_expires_at > quota_now
        )
    ) THEN
        replayed := TRUE;
        RETURN QUERY
        SELECT
            reservation_row.id,
            reservation_row.request_id,
            reservation_row.lease_token,
            reservation_row.lease_expires_at,
            reservation_row.state,
            replayed,
            reservation_row.attempt_count,
            reservation_row.model,
            reservation_row.effective_plan,
            reservation_row.effective_tier,
            reservation_row.subscription_tier,
            reservation_row.trial_active,
            reservation_row.entitlement_version,
            reservation_row.policy_version,
            reservation_row.daily_limit,
            reservation_row.daily_remaining_after_reservation;
        RETURN;
    END IF;

    IF reservation_found THEN
        -- Explicitly refunded/failed attempts and expired reservations may
        -- retry with the same idempotency key. Only an expired reservation has
        -- live counter links to release.
        IF reservation_row.state = 'reserved' THEN
            PERFORM internal.release_ai_quota_reservation_counters(
                reservation_row.id
            );
        ELSE
            DELETE FROM internal.ai_quota_reservation_counters AS links
            WHERE links.reservation_id = reservation_row.id;
        END IF;

        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'reserved',
            lease_token = pg_catalog.GEN_RANDOM_UUID(),
            lease_expires_at = quota_now + INTERVAL '10 minutes',
            attempt_count = reservations.attempt_count + 1,
            stale_recovery_count = reservations.stale_recovery_count
                + CASE WHEN reservation_row.state = 'reserved' THEN 1 ELSE 0 END,
            model = policy_row.model,
            effective_plan = resolved_plan,
            effective_tier = resolved_effective_tier,
            subscription_tier =
                CASE WHEN resolved_plan = 'pro_paid' THEN 'pro' ELSE 'free' END,
            trial_active = resolved_trial_active,
            entitlement_version = app_user.entitlement_version,
            policy_version = policy_row.policy_version,
            daily_limit = policy_row.daily_limit,
            daily_remaining_after_reservation = NULL,
            reserved_at = quota_now,
            committed_at = NULL,
            failed_at = NULL,
            refunded_at = NULL,
            updated_at = quota_now
        WHERE reservations.id = reservation_row.id
        RETURNING reservations.* INTO reservation_row;
    ELSE
        INSERT INTO internal.ai_quota_reservations (
            user_id,
            operation,
            request_id,
            lease_token,
            lease_expires_at,
            model,
            effective_plan,
            effective_tier,
            subscription_tier,
            trial_active,
            entitlement_version,
            policy_version,
            daily_limit,
            reserved_at,
            created_at,
            updated_at
        )
        VALUES (
            p_user_id,
            p_operation,
            p_request_id,
            pg_catalog.GEN_RANDOM_UUID(),
            quota_now + INTERVAL '10 minutes',
            policy_row.model,
            resolved_plan,
            resolved_effective_tier,
            CASE WHEN resolved_plan = 'pro_paid' THEN 'pro' ELSE 'free' END,
            resolved_trial_active,
            app_user.entitlement_version,
            policy_row.policy_version,
            policy_row.daily_limit,
            quota_now,
            quota_now,
            quota_now
        )
        RETURNING * INTO reservation_row;
    END IF;

    IF policy_row.daily_limit IS NOT NULL THEN
        daily_window_start :=
            pg_catalog.DATE_TRUNC('day', quota_now, 'UTC');
        resulting_daily_count := internal.consume_ai_quota_counter(
            'user_daily',
            p_user_id::TEXT,
            policy_row.daily_bucket,
            daily_window_start,
            86400,
            policy_row.daily_limit,
            'ai_quota_daily_exceeded'
        );
        INSERT INTO internal.ai_quota_reservation_counters (
            reservation_id,
            scope_type,
            scope_key,
            bucket,
            window_start
        )
        VALUES (
            reservation_row.id,
            'user_daily',
            p_user_id::TEXT,
            policy_row.daily_bucket,
            daily_window_start
        );
    END IF;

    user_window_start := pg_catalog.TO_TIMESTAMP(
        pg_catalog.FLOOR(
            pg_catalog.DATE_PART('epoch', quota_now)
            / policy_row.user_window_seconds
        ) * policy_row.user_window_seconds
    );
    ignored_count := internal.consume_ai_quota_counter(
        'user_rate',
        p_user_id::TEXT,
        policy_row.user_rate_bucket,
        user_window_start,
        policy_row.user_window_seconds,
        policy_row.user_window_limit,
        'ai_user_rate_limit_exceeded'
    );
    INSERT INTO internal.ai_quota_reservation_counters (
        reservation_id,
        scope_type,
        scope_key,
        bucket,
        window_start
    )
    VALUES (
        reservation_row.id,
        'user_rate',
        p_user_id::TEXT,
        policy_row.user_rate_bucket,
        user_window_start
    );

    ip_window_start := pg_catalog.TO_TIMESTAMP(
        pg_catalog.FLOOR(
            pg_catalog.DATE_PART('epoch', quota_now)
            / policy_row.ip_window_seconds
        ) * policy_row.ip_window_seconds
    );
    ignored_count := internal.consume_ai_quota_counter(
        'ip_rate',
        p_ip_hash,
        policy_row.ip_rate_bucket,
        ip_window_start,
        policy_row.ip_window_seconds,
        policy_row.ip_window_limit,
        'ai_ip_rate_limit_exceeded'
    );
    INSERT INTO internal.ai_quota_reservation_counters (
        reservation_id,
        scope_type,
        scope_key,
        bucket,
        window_start
    )
    VALUES (
        reservation_row.id,
        'ip_rate',
        p_ip_hash,
        policy_row.ip_rate_bucket,
        ip_window_start
    );

    UPDATE internal.ai_quota_reservations AS reservations
    SET
        daily_remaining_after_reservation =
            CASE
                WHEN policy_row.daily_limit IS NULL THEN NULL
                ELSE GREATEST(
                    policy_row.daily_limit - resulting_daily_count,
                    0
                )
            END,
        updated_at = quota_now
    WHERE reservations.id = reservation_row.id
    RETURNING reservations.* INTO reservation_row;

    RETURN QUERY
    SELECT
        reservation_row.id,
        reservation_row.request_id,
        reservation_row.lease_token,
        reservation_row.lease_expires_at,
        reservation_row.state,
        FALSE,
        reservation_row.attempt_count,
        reservation_row.model,
        reservation_row.effective_plan,
        reservation_row.effective_tier,
        reservation_row.subscription_tier,
        reservation_row.trial_active,
        reservation_row.entitlement_version,
        reservation_row.policy_version,
        reservation_row.daily_limit,
        reservation_row.daily_remaining_after_reservation;
END;
$$;

COMMENT ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT) IS
    'Service-only atomic entitlement resolution, idempotent AI quota reservation, and per-user/IP rate-limit boundary.';

REVOKE ALL ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reserve_ai_quota(UUID, TEXT, UUID, TEXT)
    TO service_role;

CREATE OR REPLACE FUNCTION public.finalize_ai_quota_reservation(
    p_reservation_id UUID,
    p_user_id UUID,
    p_lease_token UUID,
    p_final_state TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    reservation_row internal.ai_quota_reservations%ROWTYPE;
    quota_now TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_reservation_id IS NULL
       OR p_user_id IS NULL
       OR p_lease_token IS NULL
       OR p_final_state IS NULL
       OR p_final_state NOT IN ('committed', 'failed', 'refunded') THEN
        RAISE EXCEPTION 'ai_quota_invalid_finalization'
            USING ERRCODE = '22023';
    END IF;

    SELECT reservations.*
    INTO reservation_row
    FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.id = p_reservation_id
      AND reservations.user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_quota_reservation_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    -- Read the wall clock only after the row-lock wait. Otherwise a finalizer
    -- that started before expiry could wait behind cleanup and commit after the
    -- lease boundary using a stale timestamp.
    quota_now := pg_catalog.CLOCK_TIMESTAMP();

    -- A new token is generated for every retry. This fencing check prevents a
    -- delayed commit/refund from an older attempt from mutating the newer
    -- reservation (the classic ABA race).
    IF reservation_row.lease_token <> p_lease_token THEN
        RAISE EXCEPTION 'ai_quota_finalization_conflict'
            USING ERRCODE = 'P0001';
    END IF;

    IF reservation_row.state = p_final_state THEN
        RETURN TRUE;
    END IF;

    IF p_final_state = 'committed' THEN
        IF reservation_row.state <> 'reserved'
           OR reservation_row.lease_expires_at <= quota_now THEN
            RAISE EXCEPTION 'ai_quota_finalization_conflict'
                USING ERRCODE = 'P0001';
        END IF;
        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'committed',
            committed_at = quota_now,
            updated_at = quota_now
        WHERE reservations.id = p_reservation_id;

        -- Committed counters remain consumed, so only their mutable links are
        -- removed.
        DELETE FROM internal.ai_quota_reservation_counters AS links
        WHERE links.reservation_id = p_reservation_id;
    ELSIF p_final_state = 'failed' THEN
        IF reservation_row.state <> 'committed' THEN
            RAISE EXCEPTION 'ai_quota_finalization_conflict'
                USING ERRCODE = 'P0001';
        END IF;
        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'failed',
            failed_at = quota_now,
            updated_at = quota_now
        WHERE reservations.id = p_reservation_id;
    ELSE
        IF reservation_row.state <> 'reserved' THEN
            RAISE EXCEPTION 'ai_quota_finalization_conflict'
                USING ERRCODE = 'P0001';
        END IF;
        PERFORM internal.release_ai_quota_reservation_counters(
            p_reservation_id
        );
        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'refunded',
            refund_count = reservations.refund_count + 1,
            refunded_at = quota_now,
            updated_at = quota_now
        WHERE reservations.id = p_reservation_id;
    END IF;

    RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.finalize_ai_quota_reservation(
    UUID, UUID, UUID, TEXT
) IS
    'Service-only, lease-fenced AI quota transition. Commit charges before provider work; failed permits a metered retry; refund decrements counters exactly once.';

REVOKE ALL ON FUNCTION public.finalize_ai_quota_reservation(
    UUID, UUID, UUID, TEXT
)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finalize_ai_quota_reservation(
    UUID, UUID, UUID, TEXT
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.reserve_ai_quota(uuid,text,uuid,text)',
        'Atomic server-side AI entitlement, quota, and rate-limit reservation.'
    ),
    (
        'service_role',
        'public.finalize_ai_quota_reservation(uuid,uuid,uuid,text)',
        'Lease-fenced AI quota commit/fail/refund transition.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

CREATE OR REPLACE FUNCTION internal.refund_expired_ai_quota_reservations(
    p_limit INTEGER DEFAULT 1000
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    reservation_row internal.ai_quota_reservations%ROWTYPE;
    refunded_count INTEGER := 0;
    quota_now TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
BEGIN
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 10000 THEN
        RAISE EXCEPTION 'ai_quota_invalid_cleanup_limit'
            USING ERRCODE = '22023';
    END IF;

    FOR reservation_row IN
        SELECT reservations.*
        FROM internal.ai_quota_reservations AS reservations
        WHERE reservations.state = 'reserved'
          AND reservations.lease_expires_at <= quota_now
        ORDER BY reservations.lease_expires_at, reservations.id
        LIMIT p_limit
        FOR UPDATE SKIP LOCKED
    LOOP
        PERFORM internal.release_ai_quota_reservation_counters(
            reservation_row.id
        );
        UPDATE internal.ai_quota_reservations AS reservations
        SET
            state = 'refunded',
            refund_count = reservations.refund_count + 1,
            refunded_at = quota_now,
            updated_at = quota_now
        WHERE reservations.id = reservation_row.id
          AND reservations.state = 'reserved'
          AND reservations.lease_token = reservation_row.lease_token;
        refunded_count := refunded_count + 1;
    END LOOP;

    RETURN refunded_count;
END;
$$;

REVOKE ALL ON FUNCTION internal.refund_expired_ai_quota_reservations(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.prune_ai_quota_state()
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
BEGIN
    PERFORM internal.refund_expired_ai_quota_reservations(1000);

    DELETE FROM internal.ai_quota_reservations AS reservations
    WHERE reservations.id IN (
        SELECT candidates.id
        FROM internal.ai_quota_reservations AS candidates
        WHERE candidates.state IN ('committed', 'failed', 'refunded')
          AND candidates.updated_at < pg_catalog.NOW() - INTERVAL '30 days'
        ORDER BY candidates.updated_at, candidates.id
        LIMIT 10000
    );

    DELETE FROM internal.ai_quota_counters AS counters
    WHERE (counters.scope_type, counters.scope_key, counters.bucket, counters.window_start)
        IN (
            SELECT
                candidates.scope_type,
                candidates.scope_key,
                candidates.bucket,
                candidates.window_start
            FROM internal.ai_quota_counters AS candidates
            WHERE candidates.window_start < pg_catalog.NOW() - INTERVAL '2 days'
              AND NOT EXISTS (
                  SELECT 1
                  FROM internal.ai_quota_reservation_counters AS links
                  WHERE links.scope_type = candidates.scope_type
                    AND links.scope_key = candidates.scope_key
                    AND links.bucket = candidates.bucket
                    AND links.window_start = candidates.window_start
              )
            ORDER BY candidates.window_start
            LIMIT 10000
        );
END;
$$;

REVOKE ALL ON FUNCTION internal.prune_ai_quota_state()
    FROM PUBLIC, anon, authenticated, service_role;

DO $migration$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM cron.job
        WHERE jobname = 'prune_ai_quota_state_hourly'
    ) THEN
        PERFORM cron.unschedule('prune_ai_quota_state_hourly');
    END IF;
    IF EXISTS (
        SELECT 1
        FROM cron.job
        WHERE jobname = 'refund_expired_ai_quota_reservations'
    ) THEN
        PERFORM cron.unschedule('refund_expired_ai_quota_reservations');
    END IF;
END;
$migration$;

SELECT cron.schedule(
    'refund_expired_ai_quota_reservations',
    '*/5 * * * *',
    $cron$SELECT internal.refund_expired_ai_quota_reservations();$cron$
);

SELECT cron.schedule(
    'prune_ai_quota_state_hourly',
    '17 * * * *',
    $cron$SELECT internal.prune_ai_quota_state();$cron$
);
