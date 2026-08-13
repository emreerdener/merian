-- Preserve a device's ability to finish local erasure after an authenticated
-- account-deletion request commits but its HTTP response is lost. The opaque
-- device capability is generated client-side; only its SHA-256 digest reaches
-- PostgreSQL. It can inspect or acknowledge an existing deletion job, never
-- initiate deletion or select an Auth user.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE TABLE internal.account_deletion_recovery_capabilities (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    job_id UUID NOT NULL
        REFERENCES internal.account_deletion_jobs(id) ON DELETE RESTRICT,
    secret_hash TEXT NOT NULL UNIQUE,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    last_recovered_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    CONSTRAINT account_deletion_recovery_secret_hash_check
        CHECK (secret_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT account_deletion_recovery_expiry_check
        CHECK (expires_at > issued_at),
    CONSTRAINT account_deletion_recovery_recovered_at_check
        CHECK (
            last_recovered_at IS NULL
            OR last_recovered_at >= issued_at
        ),
    CONSTRAINT account_deletion_recovery_acknowledged_at_check
        CHECK (
            acknowledged_at IS NULL
            OR acknowledged_at >= issued_at
        )
);

COMMENT ON TABLE internal.account_deletion_recovery_capabilities IS
    'Private, hash-only device capabilities and permanent acknowledgement receipts that recover an already-authorized account-deletion job after Auth has disappeared.';

ALTER TABLE internal.account_deletion_recovery_capabilities
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.account_deletion_recovery_capabilities
    FROM PUBLIC, anon, authenticated, service_role;

-- Non-partial leading index required for the job foreign key and lookup.
CREATE INDEX account_deletion_recovery_capabilities_job_idx
    ON internal.account_deletion_recovery_capabilities (job_id, issued_at, id);

CREATE INDEX account_deletion_recovery_capabilities_expiry_idx
    ON internal.account_deletion_recovery_capabilities (
        expires_at,
        id
    )
    WHERE acknowledged_at IS NULL;

CREATE INDEX account_deletion_recovery_capabilities_ack_idx
    ON internal.account_deletion_recovery_capabilities (
        acknowledged_at,
        id
    )
    WHERE acknowledged_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.request_account_deletion_with_recovery(
    p_user_id UUID,
    p_secret_hash TEXT
)
RETURNS TABLE (
    job_id UUID,
    job_status TEXT,
    manual_provider_revocation_required BOOLEAN,
    recovery_expires_at TIMESTAMPTZ
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    requested_job_id UUID;
    requested_status TEXT;
    requested_manual_revocation BOOLEAN;
    existing_capability internal.account_deletion_recovery_capabilities%ROWTYPE;
    capability_count BIGINT;
    capability_expiry TIMESTAMPTZ :=
        pg_catalog.NOW() + INTERVAL '180 days';
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    -- The digest lock serializes the vanishingly unlikely cross-job collision
    -- and is shared with recovery before either path takes a job row lock.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'account-deletion-recovery:' || p_secret_hash,
            0::BIGINT
        )
    );

    SELECT
        request.job_id,
        request.job_status,
        request.manual_provider_revocation_required
    INTO STRICT
        requested_job_id,
        requested_status,
        requested_manual_revocation
    FROM public.request_account_deletion(p_user_id) AS request;

    PERFORM 1
    FROM internal.account_deletion_jobs AS deletion_job
    WHERE deletion_job.id = requested_job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_recovery_job_missing'
            USING ERRCODE = '55000';
    END IF;

    SELECT capability.*
    INTO existing_capability
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.secret_hash = p_secret_hash
    FOR UPDATE;

    IF FOUND THEN
        IF existing_capability.job_id <> requested_job_id THEN
            RAISE EXCEPTION 'account_deletion_recovery_invalid'
                USING ERRCODE = '22023';
        END IF;

        -- A late authenticated retry must never reopen a permanent
        -- acknowledgement receipt after the device has already completed local
        -- cleanup. Unacknowledged intake replays may renew their inspection
        -- window while the exact source session is still available.
        IF existing_capability.acknowledged_at IS NULL THEN
            UPDATE internal.account_deletion_recovery_capabilities AS capability
            SET
                issued_at = pg_catalog.NOW(),
                expires_at = capability_expiry,
                last_recovered_at = NULL
            WHERE capability.id = existing_capability.id;
        ELSE
            capability_expiry := existing_capability.expires_at;
        END IF;
    ELSE
        SELECT pg_catalog.COUNT(*)
        INTO capability_count
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.job_id = requested_job_id;

        -- Acknowledgement cannot be used to bypass the per-job storage bound.
        -- Each retained hash is an indefinite idempotency receipt for a device
        -- that may have lost the acknowledgement response.
        IF capability_count >= 8 THEN
            RAISE EXCEPTION 'account_deletion_recovery_capability_limit'
                USING ERRCODE = '54000';
        END IF;

        INSERT INTO internal.account_deletion_recovery_capabilities (
            job_id,
            secret_hash,
            expires_at
        )
        VALUES (
            requested_job_id,
            p_secret_hash,
            capability_expiry
        );
    END IF;

    RETURN QUERY SELECT
        requested_job_id,
        requested_status,
        requested_manual_revocation,
        capability_expiry;
END;
$function$;

COMMENT ON FUNCTION public.request_account_deletion_with_recovery(UUID, TEXT)
IS 'Service-only authenticated deletion intake that atomically binds a hash-only device recovery capability to the durable job.';

CREATE OR REPLACE FUNCTION public.recover_account_deletion(
    p_secret_hash TEXT,
    p_acknowledge BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    deletion_status TEXT,
    manual_provider_revocation_required BOOLEAN,
    recovery_expires_at TIMESTAMPTZ,
    recovery_acknowledged BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    capability_job_id UUID;
    capability_record internal.account_deletion_recovery_capabilities%ROWTYPE;
    deletion_job internal.account_deletion_jobs%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();

    IF p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'account-deletion-recovery:' || p_secret_hash,
            0::BIGINT
        )
    );

    SELECT capability.job_id
    INTO capability_job_id
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.secret_hash = p_secret_hash;

    IF capability_job_id IS NULL THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT jobs.*
    INTO STRICT deletion_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = capability_job_id
    FOR UPDATE;

    SELECT capability.*
    INTO STRICT capability_record
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.secret_hash = p_secret_hash
      AND capability.job_id = capability_job_id
    FOR UPDATE;

    -- Once acknowledged, this row is a permanent, identity-free idempotency
    -- receipt. A device may have completed local erasure but lost the HTTP
    -- acknowledgement response and remained offline for an arbitrary period.
    IF capability_record.acknowledged_at IS NULL
       AND capability_record.expires_at <= pg_catalog.NOW()
       AND NOT p_acknowledge THEN
        RAISE EXCEPTION 'account_deletion_recovery_expired'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.account_deletion_recovery_capabilities AS capability
    SET
        last_recovered_at = pg_catalog.NOW(),
        acknowledged_at = CASE
            WHEN p_acknowledge THEN
                COALESCE(capability.acknowledged_at, pg_catalog.NOW())
            ELSE capability.acknowledged_at
        END
    WHERE capability.id = capability_record.id
    RETURNING capability.* INTO capability_record;

    RETURN QUERY SELECT
        CASE
            WHEN deletion_job.status = 'completed' THEN 'completed'
            ELSE 'pending'
        END,
        deletion_job.manual_provider_revocation_required,
        capability_record.expires_at,
        capability_record.acknowledged_at IS NOT NULL;
END;
$function$;

COMMENT ON FUNCTION public.recover_account_deletion(TEXT, BOOLEAN) IS
    'Service-only capability recovery for an existing deletion receipt. The hash selects its bound job; callers cannot initiate deletion or choose an identity.';

CREATE OR REPLACE FUNCTION public.get_account_deletion_recovery_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    active_unacknowledged_count BIGINT,
    acknowledged_retained_count BIGINT,
    expired_unacknowledged_count BIGINT,
    oldest_active_issued_at TIMESTAMPTZ,
    oldest_active_age_seconds BIGINT,
    oldest_expired_at TIMESTAMPTZ,
    oldest_expired_age_seconds BIGINT,
    maximum_active_capabilities_per_job BIGINT
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
    ), capability_health AS MATERIALIZED (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE capability.acknowledged_at IS NULL
                  AND capability.expires_at > clock.observed_at
            ) AS active_unacknowledged_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE capability.acknowledged_at IS NOT NULL
            ) AS acknowledged_retained_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE capability.acknowledged_at IS NULL
                  AND capability.expires_at <= clock.observed_at
            ) AS expired_unacknowledged_count,
            pg_catalog.MIN(capability.issued_at) FILTER (
                WHERE capability.acknowledged_at IS NULL
                  AND capability.expires_at > clock.observed_at
            ) AS oldest_active_issued_at,
            pg_catalog.MIN(capability.expires_at) FILTER (
                WHERE capability.acknowledged_at IS NULL
                  AND capability.expires_at <= clock.observed_at
            ) AS oldest_expired_at
        FROM internal.account_deletion_recovery_capabilities AS capability
        CROSS JOIN health_clock AS clock
    ), per_job AS MATERIALIZED (
        SELECT pg_catalog.COUNT(*) AS active_count
        FROM internal.account_deletion_recovery_capabilities AS capability
        CROSS JOIN health_clock AS clock
        WHERE capability.acknowledged_at IS NULL
          AND capability.expires_at > clock.observed_at
        GROUP BY capability.job_id
    )
    SELECT
        clock.observed_at,
        health.active_unacknowledged_count,
        health.acknowledged_retained_count,
        health.expired_unacknowledged_count,
        health.oldest_active_issued_at,
        CASE
            WHEN health.oldest_active_issued_at IS NULL THEN NULL
            ELSE pg_catalog.FLOOR(
                EXTRACT(
                    EPOCH FROM (
                        clock.observed_at - health.oldest_active_issued_at
                    )
                )
            )::BIGINT
        END,
        health.oldest_expired_at,
        CASE
            WHEN health.oldest_expired_at IS NULL THEN NULL
            ELSE pg_catalog.FLOOR(
                EXTRACT(
                    EPOCH FROM (
                        clock.observed_at - health.oldest_expired_at
                    )
                )
            )::BIGINT
        END,
        COALESCE(
            (SELECT pg_catalog.MAX(per_job.active_count) FROM per_job),
            0
        )
    FROM health_clock AS clock
    CROSS JOIN capability_health AS health;
END;
$function$;

COMMENT ON FUNCTION public.get_account_deletion_recovery_health() IS
    'Returns aggregate service-only deletion-recovery capability age, expiry, acknowledgement, and per-job cardinality health without identities.';

REVOKE ALL ON FUNCTION
    public.request_account_deletion_with_recovery(UUID, TEXT),
    public.recover_account_deletion(TEXT, BOOLEAN),
    public.get_account_deletion_recovery_health()
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
    public.request_account_deletion_with_recovery(UUID, TEXT),
    public.recover_account_deletion(TEXT, BOOLEAN),
    public.get_account_deletion_recovery_health()
TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.request_account_deletion_with_recovery(uuid,text)',
        'Atomically binds a hash-only device recovery capability to authenticated durable account-deletion intake.'
    ),
    (
        'service_role',
        'public.recover_account_deletion(text,boolean)',
        'Recovers or acknowledges an already-authorized deletion job through its private device capability without accepting an identity.'
    ),
    (
        'service_role',
        'public.get_account_deletion_recovery_health()',
        'Reads aggregate deletion recovery capability age, expiry, acknowledgement, and cardinality health.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;
