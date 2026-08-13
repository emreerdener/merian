-- Make account-deletion recovery safe when a device-only Keychain item
-- survives an app reinstall but process-local preferences do not. Protocol v2
-- registers a non-destructive preparation before deletion can commit and uses
-- independent recovery and acknowledgement capabilities. An unknown v2 proof
-- therefore proves deletion never committed; a known prepared proof can be
-- cancelled without touching account data.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

ALTER TABLE internal.account_deletion_recovery_capabilities
    ADD COLUMN protocol_version SMALLINT NOT NULL DEFAULT 1,
    ADD COLUMN acknowledgement_secret_hash TEXT;

ALTER TABLE internal.account_deletion_recovery_capabilities
    ADD CONSTRAINT account_deletion_recovery_protocol_version_check
        CHECK (protocol_version IN (1, 2)),
    ADD CONSTRAINT account_deletion_recovery_ack_secret_hash_check
        CHECK (
            acknowledgement_secret_hash IS NULL
            OR acknowledgement_secret_hash ~ '^[0-9a-f]{64}$'
        ),
    ADD CONSTRAINT account_deletion_recovery_protocol_shape_check
        CHECK (
            (protocol_version = 1 AND acknowledgement_secret_hash IS NULL)
            OR (
                protocol_version = 2
                AND acknowledgement_secret_hash IS NOT NULL
                AND acknowledgement_secret_hash <> secret_hash
            )
        );

CREATE UNIQUE INDEX account_deletion_recovery_ack_secret_hash_idx
    ON internal.account_deletion_recovery_capabilities (
        acknowledgement_secret_hash
    )
    WHERE acknowledgement_secret_hash IS NOT NULL;

CREATE TABLE internal.account_deletion_recovery_preparations (
    id UUID PRIMARY KEY DEFAULT pg_catalog.GEN_RANDOM_UUID(),
    user_id UUID NOT NULL
        REFERENCES auth.users(id) ON DELETE CASCADE,
    recovery_secret_hash TEXT NOT NULL UNIQUE,
    acknowledgement_secret_hash TEXT NOT NULL UNIQUE,
    prepared_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT account_deletion_recovery_preparation_recovery_hash_check
        CHECK (recovery_secret_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT account_deletion_recovery_preparation_ack_hash_check
        CHECK (acknowledgement_secret_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT account_deletion_recovery_preparation_distinct_hashes_check
        CHECK (recovery_secret_hash <> acknowledgement_secret_hash),
    CONSTRAINT account_deletion_recovery_preparation_expiry_check
        CHECK (expires_at > prepared_at)
);

COMMENT ON TABLE internal.account_deletion_recovery_preparations IS
    'Short-lived, non-destructive protocol-v2 deletion preparations. A recovery proof can cancel this row; only authenticated commit may create a deletion job.';

ALTER TABLE internal.account_deletion_recovery_preparations
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.account_deletion_recovery_preparations
    FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX account_deletion_recovery_preparations_expiry_idx
    ON internal.account_deletion_recovery_preparations (expires_at, id);

CREATE INDEX account_deletion_recovery_preparations_user_idx
    ON internal.account_deletion_recovery_preparations (user_id, id);

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
    'account_deletion_recovery_preparations',
    'user_id',
    'auth',
    'users',
    'id',
    'preserve',
    900,
    NULL,
    'A prepared deletion proof belongs to its exact Auth identity and blocks profile merging until it is cancelled, committed, or expires.'
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

SELECT internal.assert_ghost_profile_merge_reference_policy_coverage();

CREATE OR REPLACE FUNCTION internal.lock_account_deletion_capability_hashes(
    p_hashes TEXT[]
)
RETURNS VOID
LANGUAGE PLPGSQL
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    capability_hash TEXT;
BEGIN
    IF p_hashes IS NULL
       OR pg_catalog.CARDINALITY(p_hashes) = 0
       OR EXISTS (
            SELECT 1
            FROM pg_catalog.UNNEST(p_hashes) AS supplied(value)
            WHERE supplied.value IS NULL
               OR supplied.value !~ '^[0-9a-f]{64}$'
       ) THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    FOR capability_hash IN
        SELECT DISTINCT supplied.value
        FROM pg_catalog.UNNEST(p_hashes) AS supplied(value)
        ORDER BY supplied.value
    LOOP
        PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
            pg_catalog.HASHTEXTEXTENDED(
                'account-deletion-recovery:' || capability_hash,
                0::BIGINT
            )
        );
    END LOOP;
END;
$function$;

COMMENT ON FUNCTION internal.lock_account_deletion_capability_hashes(TEXT[])
IS 'Locks recovery and acknowledgement hashes in lexical order so prepare, commit, recover, and acknowledge cannot deadlock or cross-bind proofs.';

REVOKE ALL ON FUNCTION
    internal.lock_account_deletion_capability_hashes(TEXT[])
FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION
internal.bind_account_deletion_recovery_preparations()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    preparation_count BIGINT;
    capability_count BIGINT;
    capability_expiry TIMESTAMPTZ :=
        pg_catalog.NOW() + INTERVAL '180 days';
BEGIN
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- request_account_deletion already holds the matching Auth-user lock.
    -- Lock all device preparations deterministically before converting them;
    -- a concurrent prepare for this user cannot pass that Auth lock.
    PERFORM preparation.id
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id
    ORDER BY preparation.id
    FOR UPDATE;

    SELECT pg_catalog.COUNT(*)
    INTO preparation_count
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id;
    IF preparation_count = 0 THEN
        RETURN NEW;
    END IF;

    SELECT pg_catalog.COUNT(*)
    INTO capability_count
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.job_id = NEW.id;
    IF capability_count + preparation_count > 8 THEN
        RAISE EXCEPTION 'account_deletion_recovery_capability_limit'
            USING ERRCODE = '54000';
    END IF;

    INSERT INTO internal.account_deletion_recovery_capabilities (
        job_id,
        secret_hash,
        protocol_version,
        acknowledgement_secret_hash,
        expires_at
    )
    SELECT
        NEW.id,
        preparation.recovery_secret_hash,
        2,
        preparation.acknowledgement_secret_hash,
        capability_expiry
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id
    ORDER BY preparation.id;

    DELETE FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.bind_account_deletion_recovery_preparations() IS
    'Atomically converts every prepared device proof into a durable receipt whenever deletion commits for that exact Auth user.';

REVOKE ALL ON FUNCTION
    internal.bind_account_deletion_recovery_preparations()
FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_bind_account_deletion_recovery_preparations
AFTER INSERT ON internal.account_deletion_jobs
FOR EACH ROW
WHEN (NEW.user_id IS NOT NULL)
EXECUTE FUNCTION internal.bind_account_deletion_recovery_preparations();

CREATE OR REPLACE FUNCTION public.prepare_account_deletion_recovery_v2(
    p_user_id UUID,
    p_recovery_secret_hash TEXT,
    p_acknowledgement_secret_hash TEXT
)
RETURNS TABLE (
    recovery_prepared BOOLEAN,
    recovery_expires_at TIMESTAMPTZ
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    existing_preparation internal.account_deletion_recovery_preparations%ROWTYPE;
    existing_capability internal.account_deletion_recovery_capabilities%ROWTYPE;
    active_job internal.account_deletion_jobs%ROWTYPE;
    preparation_count BIGINT;
    capability_count BIGINT;
    preparation_expiry TIMESTAMPTZ :=
        pg_catalog.NOW() + INTERVAL '24 hours';
    capability_expiry TIMESTAMPTZ :=
        pg_catalog.NOW() + INTERVAL '180 days';
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_user_id = '00000000-0000-0000-0000-000000000000'::UUID
       OR p_recovery_secret_hash IS NULL
       OR p_acknowledgement_secret_hash IS NULL
       OR p_recovery_secret_hash = p_acknowledgement_secret_hash THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    PERFORM internal.lock_account_deletion_capability_hashes(
        ARRAY[
            p_recovery_secret_hash,
            p_acknowledgement_secret_hash
        ]
    );

    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT jobs.*
    INTO active_job
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.user_id = p_user_id
    FOR UPDATE;

    IF FOUND THEN
        SELECT capability.*
        INTO existing_capability
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.job_id = active_job.id
          AND capability.protocol_version = 2
          AND capability.secret_hash = p_recovery_secret_hash
          AND capability.acknowledgement_secret_hash =
              p_acknowledgement_secret_hash
        FOR UPDATE;

        IF FOUND THEN
            RETURN QUERY SELECT TRUE, existing_capability.expires_at;
            RETURN;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_capabilities AS capability
            WHERE p_recovery_secret_hash IN (
                    capability.secret_hash,
                    capability.acknowledgement_secret_hash
                  )
               OR p_acknowledgement_secret_hash IN (
                    capability.secret_hash,
                    capability.acknowledgement_secret_hash
                  )
        ) OR EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE p_recovery_secret_hash IN (
                    preparation.recovery_secret_hash,
                    preparation.acknowledgement_secret_hash
                  )
               OR p_acknowledgement_secret_hash IN (
                    preparation.recovery_secret_hash,
                    preparation.acknowledgement_secret_hash
                  )
        ) THEN
            RAISE EXCEPTION 'account_deletion_recovery_invalid'
                USING ERRCODE = '22023';
        END IF;

        SELECT pg_catalog.COUNT(*)
        INTO capability_count
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.job_id = active_job.id;
        IF capability_count >= 8 THEN
            RAISE EXCEPTION 'account_deletion_recovery_capability_limit'
                USING ERRCODE = '54000';
        END IF;

        INSERT INTO internal.account_deletion_recovery_capabilities (
            job_id,
            secret_hash,
            protocol_version,
            acknowledgement_secret_hash,
            expires_at
        )
        VALUES (
            active_job.id,
            p_recovery_secret_hash,
            2,
            p_acknowledgement_secret_hash,
            capability_expiry
        );

        RETURN QUERY SELECT TRUE, capability_expiry;
        RETURN;
    END IF;

    SELECT preparation.*
    INTO existing_preparation
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.recovery_secret_hash = p_recovery_secret_hash
    FOR UPDATE;

    IF FOUND
       AND existing_preparation.user_id = p_user_id
       AND existing_preparation.recovery_secret_hash =
           p_recovery_secret_hash
       AND existing_preparation.acknowledgement_secret_hash =
           p_acknowledgement_secret_hash
       AND existing_preparation.expires_at > pg_catalog.NOW() THEN
        RETURN QUERY SELECT TRUE, existing_preparation.expires_at;
        RETURN;
    END IF;

    IF FOUND THEN
        IF existing_preparation.user_id <> p_user_id
           OR existing_preparation.acknowledgement_secret_hash <>
              p_acknowledgement_secret_hash THEN
            RAISE EXCEPTION 'account_deletion_recovery_invalid'
                USING ERRCODE = '22023';
        END IF;
        DELETE FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE preparation.id = existing_preparation.id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE p_recovery_secret_hash IN (
                capability.secret_hash,
                capability.acknowledgement_secret_hash
              )
           OR p_acknowledgement_secret_hash IN (
                capability.secret_hash,
                capability.acknowledgement_secret_hash
              )
    ) OR EXISTS (
        SELECT 1
        FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE p_recovery_secret_hash IN (
                preparation.recovery_secret_hash,
                preparation.acknowledgement_secret_hash
              )
           OR p_acknowledgement_secret_hash IN (
                preparation.recovery_secret_hash,
                preparation.acknowledgement_secret_hash
              )
    ) THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT pg_catalog.COUNT(*)
    INTO preparation_count
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = p_user_id;
    IF preparation_count >= 8 THEN
        RAISE EXCEPTION 'account_deletion_recovery_capability_limit'
            USING ERRCODE = '54000';
    END IF;

    INSERT INTO internal.account_deletion_recovery_preparations (
        user_id,
        recovery_secret_hash,
        acknowledgement_secret_hash,
        expires_at
    )
    VALUES (
        p_user_id,
        p_recovery_secret_hash,
        p_acknowledgement_secret_hash,
        preparation_expiry
    );

    RETURN QUERY SELECT TRUE, preparation_expiry;
END;
$function$;

COMMENT ON FUNCTION public.prepare_account_deletion_recovery_v2(
    UUID, TEXT, TEXT
) IS 'Service-only non-destructive preparation that binds two independent hash-only device proofs to the authenticated user before deletion may commit.';

CREATE OR REPLACE FUNCTION public.request_account_deletion_with_recovery_v2(
    p_user_id UUID,
    p_recovery_secret_hash TEXT
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
    preparation_record internal.account_deletion_recovery_preparations%ROWTYPE;
    existing_capability internal.account_deletion_recovery_capabilities%ROWTYPE;
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    requested_job_id UUID;
    requested_status TEXT;
    requested_manual_revocation BOOLEAN;
    capability_count BIGINT;
    capability_expiry TIMESTAMPTZ :=
        pg_catalog.NOW() + INTERVAL '180 days';
    acknowledgement_hash TEXT;
    preparation_user_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_recovery_secret_hash IS NULL
       OR p_recovery_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT
        preparation.user_id,
        preparation.acknowledgement_secret_hash
    INTO preparation_user_id, acknowledgement_hash
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.recovery_secret_hash = p_recovery_secret_hash;

    IF acknowledgement_hash IS NULL THEN
        SELECT capability.acknowledgement_secret_hash
        INTO acknowledgement_hash
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.protocol_version = 2
          AND capability.secret_hash = p_recovery_secret_hash;
    END IF;

    IF acknowledgement_hash IS NULL THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM internal.lock_account_deletion_capability_hashes(
        ARRAY[p_recovery_secret_hash, acknowledgement_hash]
    );

    SELECT capability.*
    INTO existing_capability
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.protocol_version = 2
      AND capability.secret_hash = p_recovery_secret_hash
      AND capability.acknowledgement_secret_hash = acknowledgement_hash;

    IF FOUND THEN
        SELECT jobs.*
        INTO STRICT deletion_job
        FROM internal.account_deletion_jobs AS jobs
        WHERE jobs.id = existing_capability.job_id
        FOR UPDATE;

        IF deletion_job.user_id IS DISTINCT FROM p_user_id THEN
            RAISE EXCEPTION 'account_deletion_recovery_invalid'
                USING ERRCODE = 'P0002';
        END IF;

        SELECT capability.*
        INTO STRICT existing_capability
        FROM internal.account_deletion_recovery_capabilities AS capability
        WHERE capability.id = existing_capability.id
        FOR UPDATE;

        RETURN QUERY SELECT
            deletion_job.id,
            deletion_job.status,
            deletion_job.manual_provider_revocation_required,
            existing_capability.expires_at;
        RETURN;
    END IF;

    IF preparation_user_id IS NULL OR preparation_user_id <> p_user_id THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT preparation.*
    INTO preparation_record
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.recovery_secret_hash = p_recovery_secret_hash
      AND preparation.acknowledgement_secret_hash = acknowledgement_hash
    FOR UPDATE;

    IF NOT FOUND OR preparation_record.user_id <> p_user_id THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = 'P0002';
    END IF;
    IF preparation_record.expires_at <= pg_catalog.NOW() THEN
        RAISE EXCEPTION 'account_deletion_recovery_expired'
            USING ERRCODE = '22023';
    END IF;

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
    FROM internal.account_deletion_jobs AS jobs
    WHERE jobs.id = requested_job_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_recovery_job_missing'
            USING ERRCODE = '55000';
    END IF;

    -- The account-deletion INSERT trigger normally materializes every active
    -- preparation before request_account_deletion returns. Treat that durable
    -- capability as the commit receipt rather than inserting it twice.
    SELECT capability.*
    INTO existing_capability
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.job_id = requested_job_id
      AND capability.protocol_version = 2
      AND capability.secret_hash = p_recovery_secret_hash
      AND capability.acknowledgement_secret_hash = acknowledgement_hash
    FOR UPDATE;

    IF FOUND THEN
        RETURN QUERY SELECT
            requested_job_id,
            requested_status,
            requested_manual_revocation,
            existing_capability.expires_at;
        RETURN;
    END IF;

    SELECT pg_catalog.COUNT(*)
    INTO capability_count
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.job_id = requested_job_id;
    IF capability_count >= 8 THEN
        RAISE EXCEPTION 'account_deletion_recovery_capability_limit'
            USING ERRCODE = '54000';
    END IF;

    INSERT INTO internal.account_deletion_recovery_capabilities (
        job_id,
        secret_hash,
        protocol_version,
        acknowledgement_secret_hash,
        expires_at
    )
    VALUES (
        requested_job_id,
        p_recovery_secret_hash,
        2,
        acknowledgement_hash,
        capability_expiry
    );

    DELETE FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.id = preparation_record.id;

    RETURN QUERY SELECT
        requested_job_id,
        requested_status,
        requested_manual_revocation,
        capability_expiry;
END;
$function$;

COMMENT ON FUNCTION public.request_account_deletion_with_recovery_v2(
    UUID, TEXT
) IS 'Service-only destructive v2 commit. It requires a prior authenticated preparation and atomically replaces that preparation with a durable deletion job and two-proof receipt.';

CREATE OR REPLACE FUNCTION public.recover_account_deletion_v2(
    p_recovery_secret_hash TEXT
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
    preparation_record internal.account_deletion_recovery_preparations%ROWTYPE;
    capability_record internal.account_deletion_recovery_capabilities%ROWTYPE;
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    capability_job_id UUID;
    preparation_user_id UUID;
    capability_count BIGINT;
    capability_expiry TIMESTAMPTZ :=
        pg_catalog.NOW() + INTERVAL '180 days';
BEGIN
    PERFORM internal.require_service_role();
    IF p_recovery_secret_hash IS NULL
       OR p_recovery_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    PERFORM internal.lock_account_deletion_capability_hashes(
        ARRAY[p_recovery_secret_hash]
    );

    SELECT preparation.user_id
    INTO preparation_user_id
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.recovery_secret_hash = p_recovery_secret_hash;

    IF preparation_user_id IS NOT NULL THEN
        -- Every mutation for one account serializes on the Auth row before it
        -- locks a preparation. If another device committed while this request
        -- waited, its INSERT trigger will have converted the proof and the
        -- capability path below returns the committed receipt.
        PERFORM auth_user.id
        FROM auth.users AS auth_user
        WHERE auth_user.id = preparation_user_id
        FOR UPDATE;

        SELECT preparation.*
        INTO preparation_record
        FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE preparation.recovery_secret_hash = p_recovery_secret_hash
          AND preparation.user_id = preparation_user_id
        FOR UPDATE;

        IF FOUND THEN
            SELECT jobs.*
            INTO deletion_job
            FROM internal.account_deletion_jobs AS jobs
            WHERE jobs.user_id = preparation_user_id
            FOR UPDATE;

            IF FOUND THEN
                SELECT pg_catalog.COUNT(*)
                INTO capability_count
                FROM internal.account_deletion_recovery_capabilities AS capability
                WHERE capability.job_id = deletion_job.id;
                IF capability_count >= 8 THEN
                    RAISE EXCEPTION
                        'account_deletion_recovery_capability_limit'
                        USING ERRCODE = '54000';
                END IF;

                INSERT INTO internal.account_deletion_recovery_capabilities (
                    job_id,
                    secret_hash,
                    protocol_version,
                    acknowledgement_secret_hash,
                    expires_at
                )
                VALUES (
                    deletion_job.id,
                    preparation_record.recovery_secret_hash,
                    2,
                    preparation_record.acknowledgement_secret_hash,
                    capability_expiry
                )
                RETURNING * INTO capability_record;

                DELETE FROM internal.account_deletion_recovery_preparations AS preparation
                WHERE preparation.id = preparation_record.id;

                RETURN QUERY SELECT
                    CASE
                        WHEN deletion_job.status = 'completed' THEN 'completed'
                        ELSE 'pending'
                    END,
                    deletion_job.manual_provider_revocation_required,
                    capability_record.expires_at,
                    FALSE;
                RETURN;
            END IF;

            DELETE FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.id = preparation_record.id;
            RETURN QUERY SELECT
                'not_committed'::TEXT,
                FALSE,
                preparation_record.expires_at,
                FALSE;
            RETURN;
        END IF;
    END IF;

    SELECT capability.job_id
    INTO capability_job_id
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.protocol_version = 2
      AND capability.secret_hash = p_recovery_secret_hash;
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
    WHERE capability.protocol_version = 2
      AND capability.secret_hash = p_recovery_secret_hash
      AND capability.job_id = capability_job_id
    FOR UPDATE;

    IF capability_record.acknowledged_at IS NULL
       AND capability_record.expires_at <= pg_catalog.NOW() THEN
        RAISE EXCEPTION 'account_deletion_recovery_expired'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.account_deletion_recovery_capabilities AS capability
    SET last_recovered_at = pg_catalog.NOW()
    WHERE capability.id = capability_record.id;

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

COMMENT ON FUNCTION public.recover_account_deletion_v2(TEXT) IS
    'Service-only v2 recovery. A prepared proof cancels non-destructive intent and returns not_committed; a committed proof returns only its bound deletion receipt.';

CREATE OR REPLACE FUNCTION public.acknowledge_account_deletion_recovery_v2(
    p_acknowledgement_secret_hash TEXT
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
    IF p_acknowledgement_secret_hash IS NULL
       OR p_acknowledgement_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'account_deletion_recovery_invalid'
            USING ERRCODE = '22023';
    END IF;

    PERFORM internal.lock_account_deletion_capability_hashes(
        ARRAY[p_acknowledgement_secret_hash]
    );

    SELECT capability.job_id
    INTO capability_job_id
    FROM internal.account_deletion_recovery_capabilities AS capability
    WHERE capability.protocol_version = 2
      AND capability.acknowledgement_secret_hash =
          p_acknowledgement_secret_hash;
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
    WHERE capability.protocol_version = 2
      AND capability.acknowledgement_secret_hash =
          p_acknowledgement_secret_hash
      AND capability.job_id = capability_job_id
    FOR UPDATE;

    UPDATE internal.account_deletion_recovery_capabilities AS capability
    SET
        last_recovered_at = pg_catalog.NOW(),
        acknowledged_at = COALESCE(
            capability.acknowledged_at,
            pg_catalog.NOW()
        )
    WHERE capability.id = capability_record.id
    RETURNING capability.* INTO capability_record;

    RETURN QUERY SELECT
        CASE
            WHEN deletion_job.status = 'completed' THEN 'completed'
            ELSE 'pending'
        END,
        deletion_job.manual_provider_revocation_required,
        capability_record.expires_at,
        TRUE;
END;
$function$;

COMMENT ON FUNCTION public.acknowledge_account_deletion_recovery_v2(TEXT) IS
    'Service-only v2 acknowledgement using a proof that cannot recover, cancel, initiate, or select an account deletion.';

CREATE OR REPLACE FUNCTION public.prune_account_deletion_recovery_preparations(
    p_limit INTEGER DEFAULT 100
)
RETURNS BIGINT
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    deleted_count BIGINT;
BEGIN
    PERFORM internal.require_service_role();
    IF p_limit < 1 OR p_limit > 500 THEN
        RAISE EXCEPTION 'account_deletion_recovery_prune_limit_invalid'
            USING ERRCODE = '22023';
    END IF;

    WITH expired AS MATERIALIZED (
        SELECT preparation.id
        FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE preparation.expires_at <= pg_catalog.NOW()
        ORDER BY preparation.expires_at, preparation.id
        LIMIT p_limit
        FOR UPDATE SKIP LOCKED
    ), deleted AS (
        DELETE FROM internal.account_deletion_recovery_preparations AS preparation
        USING expired
        WHERE preparation.id = expired.id
        RETURNING preparation.id
    )
    SELECT pg_catalog.COUNT(*) INTO deleted_count FROM deleted;

    RETURN deleted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_account_deletion_recovery_preparation_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    active_preparation_count BIGINT,
    expired_preparation_count BIGINT,
    oldest_active_age_seconds BIGINT,
    oldest_expired_age_seconds BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
BEGIN
    PERFORM internal.require_service_role();
    RETURN QUERY
    WITH clock AS MATERIALIZED (
        SELECT pg_catalog.STATEMENT_TIMESTAMP() AS observed_at
    ), aggregate_health AS MATERIALIZED (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE preparation.expires_at > clock.observed_at
            ) AS active_count,
            pg_catalog.COUNT(*) FILTER (
                WHERE preparation.expires_at <= clock.observed_at
            ) AS expired_count,
            pg_catalog.MIN(preparation.prepared_at) FILTER (
                WHERE preparation.expires_at > clock.observed_at
            ) AS oldest_active,
            pg_catalog.MIN(preparation.expires_at) FILTER (
                WHERE preparation.expires_at <= clock.observed_at
            ) AS oldest_expired
        FROM internal.account_deletion_recovery_preparations AS preparation
        CROSS JOIN clock
    )
    SELECT
        clock.observed_at,
        health.active_count,
        health.expired_count,
        CASE WHEN health.oldest_active IS NULL THEN NULL ELSE
            pg_catalog.FLOOR(EXTRACT(EPOCH FROM (
                clock.observed_at - health.oldest_active
            )))::BIGINT
        END,
        CASE WHEN health.oldest_expired IS NULL THEN NULL ELSE
            pg_catalog.FLOOR(EXTRACT(EPOCH FROM (
                clock.observed_at - health.oldest_expired
            )))::BIGINT
        END
    FROM clock
    CROSS JOIN aggregate_health AS health;
END;
$function$;

REVOKE ALL ON FUNCTION
    public.prepare_account_deletion_recovery_v2(UUID, TEXT, TEXT),
    public.request_account_deletion_with_recovery_v2(UUID, TEXT),
    public.recover_account_deletion_v2(TEXT),
    public.acknowledge_account_deletion_recovery_v2(TEXT),
    public.prune_account_deletion_recovery_preparations(INTEGER),
    public.get_account_deletion_recovery_preparation_health()
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
    public.prepare_account_deletion_recovery_v2(UUID, TEXT, TEXT),
    public.request_account_deletion_with_recovery_v2(UUID, TEXT),
    public.recover_account_deletion_v2(TEXT),
    public.acknowledge_account_deletion_recovery_v2(TEXT),
    public.prune_account_deletion_recovery_preparations(INTEGER),
    public.get_account_deletion_recovery_preparation_health()
TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.prepare_account_deletion_recovery_v2(uuid,text,text)',
        'Registers a non-destructive two-proof deletion preparation for the authenticated user.'
    ),
    (
        'service_role',
        'public.request_account_deletion_with_recovery_v2(uuid,text)',
        'Commits a previously prepared protocol-v2 deletion and durable two-proof receipt.'
    ),
    (
        'service_role',
        'public.recover_account_deletion_v2(text)',
        'Cancels a prepared deletion or reads the receipt bound to a committed recovery proof.'
    ),
    (
        'service_role',
        'public.acknowledge_account_deletion_recovery_v2(text)',
        'Acknowledges post-cleanup deletion recovery through an independent proof.'
    ),
    (
        'service_role',
        'public.prune_account_deletion_recovery_preparations(integer)',
        'Prunes bounded expired non-destructive deletion preparations.'
    ),
    (
        'service_role',
        'public.get_account_deletion_recovery_preparation_health()',
        'Reads aggregate preparation age and expiry health without identities.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;
RESET statement_timeout;
