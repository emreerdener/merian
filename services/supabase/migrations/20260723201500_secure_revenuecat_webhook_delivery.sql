-- Make RevenueCat delivery idempotent, monotonically ordered, and auditable.
--
-- The Edge Function verifies both the configured Authorization header and
-- RevenueCat's raw-body HMAC, then fetches the latest CustomerInfo snapshot.
-- This migration is the final write boundary: one service-only transaction
-- records the immutable event identifier, serializes updates per Merian user,
-- rejects older events, and advances the durable entitlement version.
--
-- A TRANSFER event has no app_user_id and changes both the source and the
-- destination customer. The event ledger is therefore separate from its
-- per-user subjects so both sides can be reconciled in one transaction.

CREATE TABLE internal.revenuecat_webhook_events (
    event_id TEXT PRIMARY KEY,
    event_timestamp_ms BIGINT NOT NULL,
    event_type TEXT NOT NULL,
    payload_sha256 TEXT NOT NULL,
    signature_timestamp_s BIGINT NOT NULL,
    outcome TEXT NOT NULL,
    subject_count SMALLINT NOT NULL,
    applied_count SMALLINT NOT NULL,
    stale_count SMALLINT NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT revenuecat_webhook_events_event_id_check
        CHECK (
            pg_catalog.CHAR_LENGTH(event_id) BETWEEN 1 AND 255
            AND event_id !~ '[[:cntrl:]]'
        ),
    CONSTRAINT revenuecat_webhook_events_event_timestamp_check
        CHECK (event_timestamp_ms BETWEEN 0 AND 253402300799999),
    CONSTRAINT revenuecat_webhook_events_event_type_check
        CHECK (
            pg_catalog.CHAR_LENGTH(event_type) BETWEEN 1 AND 100
            AND event_type !~ '[[:cntrl:]]'
        ),
    CONSTRAINT revenuecat_webhook_events_payload_hash_check
        CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT revenuecat_webhook_events_signature_timestamp_check
        CHECK (signature_timestamp_s BETWEEN 0 AND 253402300799),
    CONSTRAINT revenuecat_webhook_events_counts_check
        CHECK (
            subject_count BETWEEN 0 AND 2
            AND applied_count BETWEEN 0 AND subject_count
            AND stale_count BETWEEN 0 AND subject_count
            AND applied_count + stale_count = subject_count
        ),
    CONSTRAINT revenuecat_webhook_events_outcome_check
        CHECK (
            (outcome = 'ignored'
                AND subject_count = 0)
            OR (outcome = 'applied'
                AND subject_count > 0
                AND applied_count = subject_count)
            OR (outcome = 'stale'
                AND subject_count > 0
                AND stale_count = subject_count)
            OR (outcome = 'mixed'
                AND applied_count > 0
                AND stale_count > 0)
        )
);

COMMENT ON TABLE internal.revenuecat_webhook_events IS
    'Service-owned, immutable RevenueCat delivery ledger. event_id is the durable idempotency key; raw webhook bodies are represented only by a SHA-256 digest.';

CREATE INDEX revenuecat_webhook_events_received_at_idx
    ON internal.revenuecat_webhook_events (received_at DESC);

ALTER TABLE internal.revenuecat_webhook_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.revenuecat_webhook_events
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE internal.revenuecat_webhook_event_subjects (
    event_id TEXT NOT NULL
        REFERENCES internal.revenuecat_webhook_events(event_id)
        ON DELETE CASCADE,
    merian_user_id UUID NOT NULL
        REFERENCES public.users(id) ON DELETE CASCADE,
    subject_kind TEXT NOT NULL,
    authoritative_snapshot_at_ms BIGINT NOT NULL,
    target_tier public.subscription_tier_enum NOT NULL,
    target_expires_at TIMESTAMPTZ,
    outcome TEXT NOT NULL,
    entitlement_version BIGINT NOT NULL,
    PRIMARY KEY (event_id, merian_user_id),
    UNIQUE (event_id, subject_kind),
    CONSTRAINT revenuecat_webhook_event_subjects_kind_check
        CHECK (
            subject_kind IN (
                'customer',
                'transfer_source',
                'transfer_destination'
            )
        ),
    CONSTRAINT revenuecat_webhook_event_subjects_snapshot_timestamp_check
        CHECK (authoritative_snapshot_at_ms BETWEEN 0 AND 253402300799999),
    CONSTRAINT revenuecat_webhook_event_subjects_expiry_check
        CHECK (
            (target_tier = 'free'::public.subscription_tier_enum
                AND target_expires_at IS NULL)
            OR target_tier = 'pro'::public.subscription_tier_enum
        ),
    CONSTRAINT revenuecat_webhook_event_subjects_outcome_check
        CHECK (outcome IN ('applied', 'stale')),
    CONSTRAINT revenuecat_webhook_event_subjects_version_check
        CHECK (entitlement_version > 0)
);

COMMENT ON TABLE internal.revenuecat_webhook_event_subjects IS
    'Per-user authoritative transitions produced by a RevenueCat delivery. TRANSFER source and destination rows commit atomically.';

CREATE INDEX revenuecat_webhook_event_subjects_user_idx
    ON internal.revenuecat_webhook_event_subjects (merian_user_id);

ALTER TABLE internal.revenuecat_webhook_event_subjects
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.revenuecat_webhook_event_subjects
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE internal.revenuecat_customer_state (
    merian_user_id UUID PRIMARY KEY
        REFERENCES public.users(id) ON DELETE CASCADE,
    last_event_id TEXT NOT NULL
        REFERENCES internal.revenuecat_webhook_events(event_id),
    last_event_timestamp_ms BIGINT NOT NULL,
    last_authoritative_snapshot_at_ms BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT revenuecat_customer_state_event_timestamp_check
        CHECK (last_event_timestamp_ms BETWEEN 0 AND 253402300799999),
    CONSTRAINT revenuecat_customer_state_snapshot_timestamp_check
        CHECK (
            last_authoritative_snapshot_at_ms
                BETWEEN 0 AND 253402300799999
        )
);

COMMENT ON TABLE internal.revenuecat_customer_state IS
    'Per-user RevenueCat ordering watermark. Event time is authoritative; CustomerInfo request time and event id deterministically break ties.';

CREATE INDEX revenuecat_customer_state_last_event_idx
    ON internal.revenuecat_customer_state (last_event_id);

ALTER TABLE internal.revenuecat_customer_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.revenuecat_customer_state
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_revenuecat_webhook_event_result(
    p_event_id TEXT,
    p_event_timestamp_ms BIGINT,
    p_event_type TEXT,
    p_payload_sha256 TEXT
)
RETURNS TABLE (
    outcome TEXT,
    subject_count INTEGER,
    applied_count INTEGER,
    stale_count INTEGER
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '2s'
AS $$
DECLARE
    existing_event internal.revenuecat_webhook_events%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();

    IF p_event_id IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_id) NOT BETWEEN 1 AND 255
       OR p_event_id ~ '[[:cntrl:]]'
       OR p_event_timestamp_ms IS NULL
       OR p_event_timestamp_ms NOT BETWEEN 0 AND 253402300799999
       OR p_event_type IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_type) NOT BETWEEN 1 AND 100
       OR p_event_type ~ '[[:cntrl:]]'
       OR p_payload_sha256 IS NULL
       OR p_payload_sha256 !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'revenuecat_invalid_event_lookup'
            USING ERRCODE = '22023';
    END IF;

    SELECT events.*
    INTO existing_event
    FROM internal.revenuecat_webhook_events AS events
    WHERE events.event_id = p_event_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF existing_event.event_timestamp_ms <> p_event_timestamp_ms
       OR existing_event.event_type <> p_event_type
       OR existing_event.payload_sha256 <> p_payload_sha256 THEN
        RAISE EXCEPTION 'revenuecat_event_id_conflict'
            USING ERRCODE = '23505';
    END IF;

    RETURN QUERY
    SELECT
        'duplicate'::TEXT,
        existing_event.subject_count::INTEGER,
        existing_event.applied_count::INTEGER,
        existing_event.stale_count::INTEGER;
END;
$$;

COMMENT ON FUNCTION public.get_revenuecat_webhook_event_result(
    TEXT,
    BIGINT,
    TEXT,
    TEXT
) IS
    'Service-only durable RevenueCat duplicate lookup. Existing deliveries bypass another provider API reconciliation without exposing the private ledger.';

REVOKE ALL ON FUNCTION public.get_revenuecat_webhook_event_result(
    TEXT,
    BIGINT,
    TEXT,
    TEXT
)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_revenuecat_webhook_event_result(
    TEXT,
    BIGINT,
    TEXT,
    TEXT
) TO service_role;

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
AS $$
DECLARE
    existing_event internal.revenuecat_webhook_events%ROWTYPE;
    watermark internal.revenuecat_customer_state%ROWTYPE;
    subject RECORD;
    candidate_user_ids UUID[];
    resolved_user_ids UUID[] := ARRAY[]::UUID[];
    seen_subject_kinds TEXT[] := ARRAY[]::TEXT[];
    subject_kinds TEXT[] := ARRAY[]::TEXT[];
    snapshot_times BIGINT[] := ARRAY[]::BIGINT[];
    target_tiers public.subscription_tier_enum[] :=
        ARRAY[]::public.subscription_tier_enum[];
    target_expiries TIMESTAMPTZ[] := ARRAY[]::TIMESTAMPTZ[];
    resolved_user_id UUID;
    resolved_entitlement_version BIGINT;
    target_tier public.subscription_tier_enum;
    target_expiry TIMESTAMPTZ;
    snapshot_time BIGINT;
    subject_kind TEXT;
    matching_user_count INTEGER;
    distinct_candidate_count INTEGER;
    locked_user_count INTEGER;
    input_subject_total INTEGER;
    subject_total INTEGER;
    subject_index INTEGER;
    resulting_applied_count INTEGER := 0;
    resulting_stale_count INTEGER := 0;
    resulting_outcome TEXT;
    event_inserted BOOLEAN;
    incoming_is_newer BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_event_id IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_id) NOT BETWEEN 1 AND 255
       OR p_event_id ~ '[[:cntrl:]]'
       OR p_event_timestamp_ms IS NULL
       OR p_event_timestamp_ms NOT BETWEEN 0 AND 253402300799999
       OR p_event_type IS NULL
       OR pg_catalog.CHAR_LENGTH(p_event_type) NOT BETWEEN 1 AND 100
       OR p_event_type ~ '[[:cntrl:]]'
       OR p_payload_sha256 IS NULL
       OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
       OR p_signature_timestamp_s IS NULL
       OR p_signature_timestamp_s NOT BETWEEN 0 AND 253402300799
       OR pg_catalog.JSONB_TYPEOF(p_subjects) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'revenuecat_invalid_customer_state'
            USING ERRCODE = '22023';
    END IF;

    input_subject_total := pg_catalog.JSONB_ARRAY_LENGTH(p_subjects);
    IF input_subject_total > 2
       OR (p_event_type <> 'TRANSFER' AND input_subject_total > 1) THEN
        RAISE EXCEPTION 'revenuecat_invalid_customer_state'
            USING ERRCODE = '22023';
    END IF;

    -- Fast-path committed retries before resolving users that may since have
    -- been deleted. The unique insert below remains the concurrency authority.
    SELECT events.*
    INTO existing_event
    FROM internal.revenuecat_webhook_events AS events
    WHERE events.event_id = p_event_id;

    IF FOUND THEN
        IF existing_event.event_timestamp_ms <> p_event_timestamp_ms
           OR existing_event.event_type <> p_event_type
           OR existing_event.payload_sha256 <> p_payload_sha256 THEN
            RAISE EXCEPTION 'revenuecat_event_id_conflict'
                USING ERRCODE = '23505';
        END IF;

        RETURN QUERY
        SELECT
            'duplicate'::TEXT,
            existing_event.subject_count::INTEGER,
            existing_event.applied_count::INTEGER,
            existing_event.stale_count::INTEGER;
        RETURN;
    END IF;

    -- Resolve every CustomerInfo snapshot before taking locks. A TRANSFER can
    -- carry aliases for two RevenueCat customers; each side must map to exactly
    -- one live Merian profile. Arbitrary "first match" behavior could grant the
    -- wrong account when two live UUID aliases exist, so ambiguity fails closed.
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
           ) NOT BETWEEN 1 AND 32
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'authoritative_snapshot_at_ms'
           ) IS DISTINCT FROM 'number'
           OR pg_catalog.JSONB_TYPEOF(
               subject.value -> 'target_tier'
           ) IS DISTINCT FROM 'string'
           OR (
               subject.value ? 'target_expires_at'
               AND pg_catalog.JSONB_TYPEOF(
                   subject.value -> 'target_expires_at'
               ) NOT IN ('null', 'string')
           ) THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;

        subject_kind := subject.value ->> 'subject_kind';
        IF subject_kind IS NULL
           OR subject_kind NOT IN (
            'customer',
            'transfer_source',
            'transfer_destination'
        )
           OR (
               p_event_type = 'TRANSFER'
               AND subject_kind = 'customer'
           )
           OR (
               p_event_type <> 'TRANSFER'
               AND subject_kind <> 'customer'
           )
           OR subject_kind = ANY(seen_subject_kinds) THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;
        seen_subject_kinds := pg_catalog.ARRAY_APPEND(
            seen_subject_kinds,
            subject_kind
        );

        candidate_user_ids := ARRAY(
            SELECT candidate.value::UUID
            FROM pg_catalog.JSONB_ARRAY_ELEMENTS_TEXT(
                subject.value -> 'candidate_user_ids'
            ) WITH ORDINALITY AS candidate(value, position)
            ORDER BY candidate.position
        );

        SELECT pg_catalog.COUNT(DISTINCT candidate_id)
        INTO distinct_candidate_count
        FROM pg_catalog.UNNEST(candidate_user_ids) AS ids(candidate_id);

        IF distinct_candidate_count <> pg_catalog.CARDINALITY(
            candidate_user_ids
        )
           OR '00000000-0000-0000-0000-000000000000'::UUID =
                ANY(candidate_user_ids) THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;

        snapshot_time :=
            (subject.value ->> 'authoritative_snapshot_at_ms')::BIGINT;
        IF snapshot_time NOT BETWEEN 0 AND 253402300799999 THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;

        IF subject.value ->> 'target_tier' IS NULL
           OR subject.value ->> 'target_tier' NOT IN ('free', 'pro') THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;
        target_tier :=
            (subject.value ->> 'target_tier')::public.subscription_tier_enum;
        target_expiry := CASE
            WHEN pg_catalog.JSONB_TYPEOF(
                subject.value -> 'target_expires_at'
            ) = 'string'
                THEN (subject.value ->> 'target_expires_at')::TIMESTAMPTZ
            ELSE NULL
        END;

        IF (
            target_tier = 'free'::public.subscription_tier_enum
            AND target_expiry IS NOT NULL
        ) OR (
            target_tier = 'pro'::public.subscription_tier_enum
            AND target_expiry IS NOT NULL
            AND target_expiry <= pg_catalog.TO_TIMESTAMP(
                snapshot_time::DOUBLE PRECISION / 1000.0
            )
        ) THEN
            RAISE EXCEPTION 'revenuecat_invalid_customer_state'
                USING ERRCODE = '22023';
        END IF;

        SELECT
            pg_catalog.COUNT(*)::INTEGER,
            (pg_catalog.ARRAY_AGG(
                matches.user_id
                ORDER BY matches.position
            ))[1]
        INTO matching_user_count, resolved_user_id
        FROM (
            SELECT users.id AS user_id, candidates.position
            FROM pg_catalog.UNNEST(candidate_user_ids)
                WITH ORDINALITY AS candidates(user_id, position)
            JOIN public.users AS users
              ON users.id = candidates.user_id
        ) AS matches;

        -- A deleted transfer source no longer has a Merian entitlement to
        -- revoke and must not prevent the live destination from receiving its
        -- authoritative state. Missing normal/destination profiles remain
        -- retryable because they can represent profile-creation races.
        IF matching_user_count = 0
           AND subject_kind = 'transfer_source' THEN
            CONTINUE;
        END IF;
        IF matching_user_count = 0 THEN
            RAISE EXCEPTION 'revenuecat_user_not_found'
                USING ERRCODE = 'P0001';
        END IF;
        IF matching_user_count > 1
           OR resolved_user_id = ANY(resolved_user_ids) THEN
            RAISE EXCEPTION 'revenuecat_user_mapping_ambiguous'
                USING ERRCODE = 'P0001';
        END IF;

        resolved_user_ids := pg_catalog.ARRAY_APPEND(
            resolved_user_ids,
            resolved_user_id
        );
        subject_kinds := pg_catalog.ARRAY_APPEND(
            subject_kinds,
            subject_kind
        );
        snapshot_times := pg_catalog.ARRAY_APPEND(
            snapshot_times,
            snapshot_time
        );
        target_tiers := pg_catalog.ARRAY_APPEND(target_tiers, target_tier);
        target_expiries := pg_catalog.ARRAY_APPEND(
            target_expiries,
            target_expiry
        );
    END LOOP;

    subject_total := pg_catalog.CARDINALITY(resolved_user_ids);

    -- All routines that can mutate a user's entitlement take user locks in UUID
    -- order. The provider calls have already completed, so these locks are held
    -- only for the short ledger/update transaction.
    IF subject_total > 0 THEN
        PERFORM users.id
        FROM public.users AS users
        WHERE users.id = ANY(resolved_user_ids)
        ORDER BY users.id
        FOR UPDATE;
        GET DIAGNOSTICS locked_user_count = ROW_COUNT;

        IF locked_user_count <> subject_total THEN
            RAISE EXCEPTION 'revenuecat_user_not_found'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    resulting_outcome := CASE
        WHEN subject_total = 0 THEN 'ignored'
        ELSE 'stale'
    END;

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
        p_event_id,
        p_event_timestamp_ms,
        p_event_type,
        p_payload_sha256,
        p_signature_timestamp_s,
        resulting_outcome,
        subject_total,
        0,
        subject_total
    )
    ON CONFLICT (event_id) DO NOTHING
    RETURNING TRUE
    INTO event_inserted;

    IF event_inserted IS NOT TRUE THEN
        SELECT events.*
        INTO STRICT existing_event
        FROM internal.revenuecat_webhook_events AS events
        WHERE events.event_id = p_event_id;

        IF existing_event.event_timestamp_ms <> p_event_timestamp_ms
           OR existing_event.event_type <> p_event_type
           OR existing_event.payload_sha256 <> p_payload_sha256 THEN
            RAISE EXCEPTION 'revenuecat_event_id_conflict'
                USING ERRCODE = '23505';
        END IF;

        RETURN QUERY
        SELECT
            'duplicate'::TEXT,
            existing_event.subject_count::INTEGER,
            existing_event.applied_count::INTEGER,
            existing_event.stale_count::INTEGER;
        RETURN;
    END IF;

    IF subject_total = 0 THEN
        RETURN QUERY SELECT 'ignored'::TEXT, 0, 0, 0;
        RETURN;
    END IF;

    FOR subject_index IN 1..subject_total LOOP
        resolved_user_id := resolved_user_ids[subject_index];
        snapshot_time := snapshot_times[subject_index];
        target_tier := target_tiers[subject_index];
        target_expiry := target_expiries[subject_index];
        subject_kind := subject_kinds[subject_index];

        SELECT states.*
        INTO watermark
        FROM internal.revenuecat_customer_state AS states
        WHERE states.merian_user_id = resolved_user_id
        FOR UPDATE;

        incoming_is_newer :=
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
            );

        IF incoming_is_newer THEN
            UPDATE public.users AS users
            SET subscription_tier = target_tier,
                subscription_expires_at = target_expiry
            WHERE users.id = resolved_user_id
              AND (
                  users.subscription_tier IS DISTINCT FROM target_tier
                  OR users.subscription_expires_at
                        IS DISTINCT FROM target_expiry
              )
            RETURNING users.entitlement_version
            INTO resolved_entitlement_version;

            IF NOT FOUND THEN
                SELECT users.entitlement_version
                INTO STRICT resolved_entitlement_version
                FROM public.users AS users
                WHERE users.id = resolved_user_id;
            END IF;

            INSERT INTO internal.revenuecat_customer_state (
                merian_user_id,
                last_event_id,
                last_event_timestamp_ms,
                last_authoritative_snapshot_at_ms,
                updated_at
            )
            VALUES (
                resolved_user_id,
                p_event_id,
                p_event_timestamp_ms,
                snapshot_time,
                pg_catalog.CLOCK_TIMESTAMP()
            )
            ON CONFLICT (merian_user_id) DO UPDATE
            SET last_event_id = EXCLUDED.last_event_id,
                last_event_timestamp_ms = EXCLUDED.last_event_timestamp_ms,
                last_authoritative_snapshot_at_ms =
                    EXCLUDED.last_authoritative_snapshot_at_ms,
                updated_at = EXCLUDED.updated_at;

            resulting_applied_count := resulting_applied_count + 1;
        ELSE
            SELECT users.entitlement_version
            INTO STRICT resolved_entitlement_version
            FROM public.users AS users
            WHERE users.id = resolved_user_id;

            resulting_stale_count := resulting_stale_count + 1;
        END IF;

        INSERT INTO internal.revenuecat_webhook_event_subjects (
            event_id,
            merian_user_id,
            subject_kind,
            authoritative_snapshot_at_ms,
            target_tier,
            target_expires_at,
            outcome,
            entitlement_version
        )
        VALUES (
            p_event_id,
            resolved_user_id,
            subject_kind,
            snapshot_time,
            target_tier,
            target_expiry,
            CASE WHEN incoming_is_newer THEN 'applied' ELSE 'stale' END,
            resolved_entitlement_version
        );
    END LOOP;

    resulting_outcome := CASE
        WHEN resulting_applied_count = subject_total THEN 'applied'
        WHEN resulting_stale_count = subject_total THEN 'stale'
        ELSE 'mixed'
    END;

    UPDATE internal.revenuecat_webhook_events AS events
    SET outcome = resulting_outcome,
        applied_count = resulting_applied_count,
        stale_count = resulting_stale_count
    WHERE events.event_id = p_event_id;

    RETURN QUERY
    SELECT
        resulting_outcome,
        subject_total,
        resulting_applied_count,
        resulting_stale_count;
END;
$$;

COMMENT ON FUNCTION public.apply_revenuecat_customer_state(
    TEXT,
    BIGINT,
    TEXT,
    TEXT,
    BIGINT,
    JSONB
) IS
    'Service-only RevenueCat event ledger and atomic per-user monotonic entitlement transition. The caller must first verify HMAC and reconcile authoritative CustomerInfo for every subject.';

REVOKE ALL ON FUNCTION public.apply_revenuecat_customer_state(
    TEXT,
    BIGINT,
    TEXT,
    TEXT,
    BIGINT,
    JSONB
)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_revenuecat_customer_state(
    TEXT,
    BIGINT,
    TEXT,
    TEXT,
    BIGINT,
    JSONB
) TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)',
    'HMAC-verified RevenueCat event ledger and atomic monotonic entitlement transition, including transfers.'
),
(
    'service_role',
    'public.get_revenuecat_webhook_event_result(text,bigint,text,text)',
    'Durable RevenueCat duplicate lookup before another provider API request.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;
