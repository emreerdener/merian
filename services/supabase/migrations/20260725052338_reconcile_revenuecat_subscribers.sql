BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- CustomerInfo is the entitlement authority. Webhook event time only orders
-- snapshots captured at the exact same provider version.
DO $migration$
DECLARE
    routine_body TEXT;
    old_ordering TEXT :=
'incoming_is_newer :=
            NOT FOUND
            OR p_event_timestamp_ms > watermark.last_event_timestamp_ms
            OR (
                p_event_timestamp_ms = watermark.last_event_timestamp_ms
                AND snapshot_time
                    > watermark.last_authoritative_snapshot_at_ms
            )
            OR (
                p_event_timestamp_ms = watermark.last_event_timestamp_ms
                AND snapshot_time
                    = watermark.last_authoritative_snapshot_at_ms
                AND p_event_id COLLATE pg_catalog."C"
                    > watermark.last_event_id COLLATE pg_catalog."C"
            );';
    new_ordering TEXT :=
'incoming_is_newer :=
            NOT FOUND
            OR snapshot_time > watermark.last_authoritative_snapshot_at_ms
            OR (
                snapshot_time = watermark.last_authoritative_snapshot_at_ms
                AND p_event_timestamp_ms > watermark.last_event_timestamp_ms
            )
            OR (
                snapshot_time = watermark.last_authoritative_snapshot_at_ms
                AND p_event_timestamp_ms = watermark.last_event_timestamp_ms
                AND p_event_id COLLATE pg_catalog."C"
                    > watermark.last_event_id COLLATE pg_catalog."C"
            );';
BEGIN
    SELECT procedure_row.prosrc
    INTO STRICT routine_body
    FROM pg_catalog.pg_proc AS procedure_row
    JOIN pg_catalog.pg_namespace AS namespace_row
      ON namespace_row.oid = procedure_row.pronamespace
    WHERE namespace_row.nspname = 'public'
      AND procedure_row.proname = 'apply_revenuecat_customer_state'
      AND pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(procedure_row.oid) =
          'p_event_id text, p_event_timestamp_ms bigint, p_event_type text, p_payload_sha256 text, p_signature_timestamp_s bigint, p_subjects jsonb';

    IF pg_catalog.STRPOS(routine_body, old_ordering) = 0 THEN
        RAISE EXCEPTION 'revenuecat_ordering_source_drift'
            USING ERRCODE = '55000';
    END IF;

    routine_body := pg_catalog.REPLACE(
        routine_body,
        old_ordering,
        new_ordering
    );

    EXECUTE pg_catalog.FORMAT(
        $ddl$
        CREATE OR REPLACE FUNCTION public.apply_revenuecat_customer_state(
            p_event_id TEXT,
            p_event_timestamp_ms BIGINT,
            p_event_type TEXT,
            p_payload_sha256 TEXT,
            p_signature_timestamp_s BIGINT,
            p_subjects JSONB
        )
        RETURNS TABLE (
            outcome TEXT,
            subject_count INTEGER,
            applied_count INTEGER,
            stale_count INTEGER
        )
        LANGUAGE PLPGSQL
        SECURITY DEFINER
        SET search_path = ''
        SET statement_timeout = '5s'
        AS %L
        $ddl$,
        routine_body
    );
END;
$migration$;

COMMENT ON TABLE internal.revenuecat_customer_state IS
    'Per-user RevenueCat ordering watermark. Authoritative CustomerInfo snapshot time is primary; webhook event time and event id only break exact snapshot ties.';

CREATE TABLE internal.revenuecat_reconciliation_queue (
    merian_user_id UUID PRIMARY KEY
        REFERENCES public.users(id) ON DELETE CASCADE,
    lookup_app_user_id TEXT NOT NULL,
    next_reconcile_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    attempt_count INTEGER NOT NULL DEFAULT 0,
    claim_token UUID,
    claimed_at TIMESTAMPTZ,
    claim_expires_at TIMESTAMPTZ,
    last_snapshot_at_ms BIGINT,
    last_reconciled_at TIMESTAMPTZ,
    last_error_code TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT revenuecat_reconciliation_lookup_check
        CHECK (
            pg_catalog.CHAR_LENGTH(lookup_app_user_id) BETWEEN 1 AND 1500
            AND lookup_app_user_id !~ '[[:cntrl:]]'
        ),
    CONSTRAINT revenuecat_reconciliation_attempt_check
        CHECK (attempt_count BETWEEN 0 AND 1000000),
    CONSTRAINT revenuecat_reconciliation_claim_check
        CHECK (
            (
                claim_token IS NULL
                AND claimed_at IS NULL
                AND claim_expires_at IS NULL
            )
            OR (
                claim_token IS NOT NULL
                AND claimed_at IS NOT NULL
                AND claim_expires_at IS NOT NULL
                AND claim_expires_at > claimed_at
            )
        ),
    CONSTRAINT revenuecat_reconciliation_snapshot_check
        CHECK (
            last_snapshot_at_ms IS NULL
            OR last_snapshot_at_ms BETWEEN 0 AND 253402300799999
        ),
    CONSTRAINT revenuecat_reconciliation_error_check
        CHECK (
            last_error_code IS NULL
            OR pg_catalog.CHAR_LENGTH(last_error_code) BETWEEN 1 AND 120
        )
);

COMMENT ON TABLE internal.revenuecat_reconciliation_queue IS
    'Durable per-customer RevenueCat CustomerInfo sweep queue. Claims are leased and every state write is claim-fenced.';

CREATE INDEX revenuecat_reconciliation_due_idx
    ON internal.revenuecat_reconciliation_queue (
        next_reconcile_at,
        merian_user_id
    )
    WHERE claim_token IS NULL;

ALTER TABLE internal.revenuecat_reconciliation_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.revenuecat_reconciliation_queue
    FROM PUBLIC, anon, authenticated, service_role;

-- Poll every identified account, not only rows already marked Pro. Otherwise a
-- completely missed purchase webhook could never be repaired.
INSERT INTO internal.revenuecat_reconciliation_queue (
    merian_user_id,
    lookup_app_user_id,
    next_reconcile_at
)
SELECT users.id, users.id::TEXT, pg_catalog.NOW()
FROM public.users AS users
JOIN auth.users AS auth_user
  ON auth_user.id = users.id
WHERE auth_user.is_anonymous IS NOT TRUE
ON CONFLICT (merian_user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION internal.enqueue_revenuecat_reconciliation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = NEW.id
          AND auth_user.is_anonymous IS NOT TRUE
    ) THEN
        INSERT INTO internal.revenuecat_reconciliation_queue (
            merian_user_id,
            lookup_app_user_id,
            next_reconcile_at
        )
        VALUES (
            NEW.id,
            NEW.id::TEXT,
            pg_catalog.NOW() + INTERVAL '15 minutes'
        )
        ON CONFLICT (merian_user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enqueue_revenuecat_reconciliation()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS enqueue_revenuecat_reconciliation_on_user_insert
    ON public.users;
CREATE TRIGGER enqueue_revenuecat_reconciliation_on_user_insert
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.enqueue_revenuecat_reconciliation();

DROP TRIGGER IF EXISTS enqueue_revenuecat_reconciliation_on_identity_update
    ON public.users;
CREATE TRIGGER enqueue_revenuecat_reconciliation_on_identity_update
AFTER UPDATE OF email, public_identity_source ON public.users
FOR EACH ROW
EXECUTE FUNCTION internal.enqueue_revenuecat_reconciliation();

CREATE OR REPLACE FUNCTION public.schedule_revenuecat_reconciliation(
    p_subjects JSONB
)
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
DECLARE
    subject RECORD;
    subject_kind TEXT;
    lookup_app_user_id TEXT;
    candidate_user_ids UUID[];
    matching_user_count INTEGER;
    resolved_user_id UUID;
    scheduled_count INTEGER := 0;
BEGIN
    PERFORM internal.require_service_role();

    IF pg_catalog.JSONB_TYPEOF(p_subjects) IS DISTINCT FROM 'array'
       OR pg_catalog.JSONB_ARRAY_LENGTH(p_subjects) > 2 THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
            USING ERRCODE = '22023';
    END IF;

    FOR subject IN
        SELECT item.value, item.position
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_subjects)
            WITH ORDINALITY AS item(value, position)
        ORDER BY item.position
    LOOP
        IF pg_catalog.JSONB_TYPEOF(subject.value) IS DISTINCT FROM 'object'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'candidate_user_ids'
           ) IS DISTINCT FROM 'array'
           OR pg_catalog.JSONB_ARRAY_LENGTH(
               subject.value -> 'candidate_user_ids'
           ) NOT BETWEEN 1 AND 32 THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;

        subject_kind := subject.value ->> 'subject_kind';
        lookup_app_user_id := subject.value ->> 'lookup_app_user_id';
        IF subject_kind NOT IN (
            'customer',
            'transfer_source',
            'transfer_destination'
        )
           OR lookup_app_user_id IS NULL
           OR pg_catalog.CHAR_LENGTH(lookup_app_user_id) NOT BETWEEN 1 AND 1500
           OR lookup_app_user_id ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;

        candidate_user_ids := ARRAY(
            SELECT candidate.value::UUID
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                subject.value -> 'candidate_user_ids'
            ) WITH ORDINALITY AS candidate(value, position)
            ORDER BY candidate.position
        );

        IF '00000000-0000-0000-0000-000000000000'::UUID =
            ANY(candidate_user_ids)
           OR pg_catalog.CARDINALITY(candidate_user_ids) <>
                (
                    SELECT pg_catalog.COUNT(DISTINCT candidate_id)::INTEGER
                    FROM pg_catalog.UNNEST(candidate_user_ids)
                        AS candidates(candidate_id)
                ) THEN
            RAISE EXCEPTION 'revenuecat_invalid_reconciliation_subjects'
                USING ERRCODE = '22023';
        END IF;

        SELECT
            pg_catalog.COUNT(*)::INTEGER,
            (pg_catalog.ARRAY_AGG(users.id ORDER BY users.id))[1]
        INTO matching_user_count, resolved_user_id
        FROM public.users AS users
        WHERE users.id = ANY(candidate_user_ids);

        IF matching_user_count = 0 AND subject_kind = 'transfer_source' THEN
            CONTINUE;
        END IF;
        IF matching_user_count = 0 THEN
            RAISE EXCEPTION 'revenuecat_user_not_found'
                USING ERRCODE = 'P0001';
        END IF;
        IF matching_user_count <> 1 THEN
            RAISE EXCEPTION 'revenuecat_user_mapping_ambiguous'
                USING ERRCODE = 'P0001';
        END IF;

        INSERT INTO internal.revenuecat_reconciliation_queue (
            merian_user_id,
            lookup_app_user_id,
            next_reconcile_at,
            updated_at
        )
        VALUES (
            resolved_user_id,
            lookup_app_user_id,
            pg_catalog.NOW() + INTERVAL '6 hours',
            pg_catalog.NOW()
        )
        ON CONFLICT (merian_user_id) DO UPDATE
        SET lookup_app_user_id = EXCLUDED.lookup_app_user_id,
            next_reconcile_at = LEAST(
                internal.revenuecat_reconciliation_queue.next_reconcile_at,
                EXCLUDED.next_reconcile_at
            ),
            updated_at = EXCLUDED.updated_at;

        scheduled_count := scheduled_count + 1;
    END LOOP;

    RETURN scheduled_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_revenuecat_reconciliations(
    p_limit INTEGER DEFAULT 10
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
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 25 THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_limit'
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
    WHERE queue.claim_expires_at <= pg_catalog.NOW();

    RETURN QUERY
    WITH due AS (
        SELECT queue.merian_user_id
        FROM internal.revenuecat_reconciliation_queue AS queue
        WHERE queue.claim_token IS NULL
          AND queue.next_reconcile_at <= pg_catalog.NOW()
        ORDER BY queue.next_reconcile_at, queue.merian_user_id
        FOR UPDATE SKIP LOCKED
        LIMIT p_limit
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
      ON states.merian_user_id = claimed.merian_user_id
    ORDER BY claimed.merian_user_id;
END;
$$;

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
AS $$
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

    SELECT queue.*
    INTO queue_row
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.NOW()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    PERFORM users.id
    FROM public.users AS users
    WHERE users.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_user_not_found'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT states.*
    INTO watermark
    FROM internal.revenuecat_customer_state AS states
    WHERE states.merian_user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND
       OR p_authoritative_snapshot_at_ms >
            watermark.last_authoritative_snapshot_at_ms THEN
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
      AND queue.claim_token = p_claim_token;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;

    RETURN state_applied;
END;
$$;

CREATE OR REPLACE FUNCTION public.fail_revenuecat_reconciliation(
    p_user_id UUID,
    p_claim_token UUID,
    p_error_code TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL OR p_claim_token IS NULL THEN
        RAISE EXCEPTION 'revenuecat_invalid_reconciliation_failure'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.revenuecat_reconciliation_queue AS queue
    SET attempt_count = LEAST(queue.attempt_count + 1, 100),
        next_reconcile_at = pg_catalog.NOW() + CASE
            WHEN queue.attempt_count < 2 THEN INTERVAL '1 minute'
            WHEN queue.attempt_count < 5 THEN INTERVAL '5 minutes'
            WHEN queue.attempt_count < 10 THEN INTERVAL '15 minutes'
            ELSE INTERVAL '1 hour'
        END,
        claim_token = NULL,
        claimed_at = NULL,
        claim_expires_at = NULL,
        last_error_code = pg_catalog.LEFT(
            COALESCE(
                NULLIF(pg_catalog.BTRIM(p_error_code), ''),
                'reconciliation_failed'
            ),
            120
        ),
        updated_at = pg_catalog.NOW()
    WHERE queue.merian_user_id = p_user_id
      AND queue.claim_token = p_claim_token
      AND queue.claim_expires_at > pg_catalog.NOW();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_claim_lost'
            USING ERRCODE = '55000';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.schedule_revenuecat_reconciliation(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_revenuecat_reconciliations(INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.fail_revenuecat_reconciliation(
    UUID,
    UUID,
    TEXT
) FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.schedule_revenuecat_reconciliation(JSONB)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_revenuecat_reconciliations(INTEGER)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_revenuecat_reconciliation(
    UUID,
    UUID,
    BIGINT,
    TEXT,
    TIMESTAMPTZ
) TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_revenuecat_reconciliation(
    UUID,
    UUID,
    TEXT
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.schedule_revenuecat_reconciliation(jsonb)',
        'Durably records RevenueCat CustomerInfo subscribers after webhook processing.'
    ),
    (
        'service_role',
        'public.claim_revenuecat_reconciliations(integer)',
        'Leases bounded CustomerInfo reconciliation sweeps.'
    ),
    (
        'service_role',
        'public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)',
        'Applies claim-fenced authoritative CustomerInfo snapshots.'
    ),
    (
        'service_role',
        'public.fail_revenuecat_reconciliation(uuid,uuid,text)',
        'Releases failed CustomerInfo reconciliation claims with durable backoff.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;

DO $schedule$
BEGIN
    PERFORM cron.unschedule(
        'reconcile_revenuecat_subscribers_every_fifteen_minutes'
    );
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
$schedule$;

SELECT cron.schedule(
    'reconcile_revenuecat_subscribers_every_fifteen_minutes',
    '*/15 * * * *',
    $cron$
    DO $job$
    DECLARE
        project_url TEXT;
        service_role_key TEXT;
    BEGIN
        SELECT secrets.decrypted_secret
        INTO project_url
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_URL'
        LIMIT 1;

        SELECT secrets.decrypted_secret
        INTO service_role_key
        FROM vault.decrypted_secrets AS secrets
        WHERE secrets.name = 'SUPABASE_SERVICE_ROLE_KEY'
        LIMIT 1;

        IF project_url IS NULL THEN
            project_url :=
                pg_catalog.CURRENT_SETTING(
                    'app.settings.supabase_url',
                    TRUE
                );
        END IF;
        IF service_role_key IS NULL THEN
            service_role_key :=
                pg_catalog.CURRENT_SETTING(
                    'app.settings.service_role_key',
                    TRUE
                );
        END IF;

        IF project_url IS NOT NULL AND service_role_key IS NOT NULL THEN
            PERFORM net.http_post(
                url := project_url ||
                    '/functions/v1/reconcile-revenuecat-subscribers',
                headers := pg_catalog.JSONB_BUILD_OBJECT(
                    'Content-Type',
                    'application/json',
                    'Authorization',
                    'Bearer ' || service_role_key
                ),
                body := '{}'::JSONB
            );
        END IF;
    END;
    $job$;
    $cron$
);

NOTIFY pgrst, 'reload schema';

COMMIT;
