SET lock_timeout = '10s';
SET statement_timeout = '2min';

-- Protocol-v2 recovery preparations authorize conversion only during their
-- short preparation window. Keep this repair forward-only because the v2
-- schema migration may already have been applied to a hosted project.
CREATE TABLE internal.account_deletion_expired_preparation_proofs (
    proof_hash TEXT PRIMARY KEY
        CHECK (proof_hash ~ '^[0-9a-f]{64}$'),
    proof_kind TEXT NOT NULL
        CHECK (proof_kind IN ('recovery', 'acknowledgement')),
    deletion_committed BOOLEAN NOT NULL,
    expired_at TIMESTAMPTZ NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW()
);

ALTER TABLE internal.account_deletion_expired_preparation_proofs
    ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE internal.account_deletion_expired_preparation_proofs IS
    'Identity-free permanent evidence that a v2 recovery or acknowledgement proof expired; committed state prevents older clients from treating a discarded proof as evidence that deletion never started.';

REVOKE ALL ON TABLE
    internal.account_deletion_expired_preparation_proofs
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
    observed_at TIMESTAMPTZ := pg_catalog.NOW();
    preparation_count BIGINT;
    capability_count BIGINT;
    capability_expiry TIMESTAMPTZ :=
        observed_at + INTERVAL '180 days';
BEGIN
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- request_account_deletion already holds the matching Auth-user lock.
    -- Lock every device preparation before classifying it so a proof cannot
    -- cross the expiry boundary while this trigger is materializing receipts.
    PERFORM preparation.id
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id
    ORDER BY preparation.id
    FOR UPDATE;

    INSERT INTO internal.account_deletion_expired_preparation_proofs (
        proof_hash,
        proof_kind,
        deletion_committed,
        expired_at
    )
    SELECT
        proof.proof_hash,
        proof.proof_kind,
        TRUE,
        preparation.expires_at
    FROM internal.account_deletion_recovery_preparations AS preparation
    CROSS JOIN LATERAL (
        VALUES
            (preparation.recovery_secret_hash, 'recovery'::TEXT),
            (
                preparation.acknowledgement_secret_hash,
                'acknowledgement'::TEXT
            )
    ) AS proof(proof_hash, proof_kind)
    WHERE preparation.user_id = NEW.user_id
      AND preparation.expires_at <= observed_at
    ON CONFLICT (proof_hash) DO UPDATE
    SET expired_at = LEAST(
        internal.account_deletion_expired_preparation_proofs.expired_at,
        EXCLUDED.expired_at
    ), deletion_committed =
        internal.account_deletion_expired_preparation_proofs
            .deletion_committed
        OR EXCLUDED.deletion_committed;

    DELETE FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id
      AND preparation.expires_at <= observed_at;

    SELECT pg_catalog.COUNT(*)
    INTO preparation_count
    FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id
      AND preparation.expires_at > observed_at;
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
      AND preparation.expires_at > observed_at
    ORDER BY preparation.id;

    DELETE FROM internal.account_deletion_recovery_preparations AS preparation
    WHERE preparation.user_id = NEW.user_id;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.bind_account_deletion_recovery_preparations() IS
    'Atomically records expired proofs without identity and converts only live device preparations into durable receipts when deletion commits for that Auth user.';

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
    observed_at TIMESTAMPTZ := pg_catalog.NOW();
    preparation_record internal.account_deletion_recovery_preparations%ROWTYPE;
    capability_record internal.account_deletion_recovery_capabilities%ROWTYPE;
    deletion_job internal.account_deletion_jobs%ROWTYPE;
    capability_job_id UUID;
    preparation_user_id UUID;
    expired_preparation_at TIMESTAMPTZ;
    expired_preparation_committed BOOLEAN;
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
        -- waited, its INSERT trigger will have converted a still-live proof and
        -- the capability path below returns that committed receipt.
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
            -- An expired preparation never authorizes a durable 180-day
            -- capability, even if a different device has since committed the
            -- account deletion. Preserve only its unguessable proof hashes so
            -- older clients cannot later mistake an unknown proof for evidence
            -- that no deletion was committed.
            IF preparation_record.expires_at <= observed_at THEN
                SELECT EXISTS (
                    SELECT 1
                    FROM internal.account_deletion_jobs AS jobs
                    WHERE jobs.user_id = preparation_user_id
                )
                INTO expired_preparation_committed;
                INSERT INTO
                    internal.account_deletion_expired_preparation_proofs (
                        proof_hash,
                        proof_kind,
                        deletion_committed,
                        expired_at
                    )
                VALUES
                    (
                        preparation_record.recovery_secret_hash,
                        'recovery',
                        expired_preparation_committed,
                        preparation_record.expires_at
                    ),
                    (
                        preparation_record.acknowledgement_secret_hash,
                        'acknowledgement',
                        expired_preparation_committed,
                        preparation_record.expires_at
                    )
                ON CONFLICT (proof_hash) DO UPDATE
                SET expired_at = LEAST(
                    internal.account_deletion_expired_preparation_proofs
                        .expired_at,
                    EXCLUDED.expired_at
                ), deletion_committed =
                    internal.account_deletion_expired_preparation_proofs
                        .deletion_committed
                    OR EXCLUDED.deletion_committed;
                DELETE FROM internal.account_deletion_recovery_preparations
                    AS preparation
                WHERE preparation.id = preparation_record.id;
                RETURN QUERY SELECT
                    CASE
                        WHEN expired_preparation_committed
                            THEN 'preparation_expired'
                        ELSE 'not_committed'
                    END::TEXT,
                    FALSE,
                    preparation_record.expires_at,
                    FALSE;
                RETURN;
            END IF;

            SELECT jobs.*
            INTO deletion_job
            FROM internal.account_deletion_jobs AS jobs
            WHERE jobs.user_id = preparation_user_id
            FOR UPDATE;

            IF FOUND THEN
                -- A committed deletion converts every live preparation inside
                -- its INSERT trigger. Reaching this state means catalog drift;
                -- never repair it by minting authority during public recovery.
                RAISE EXCEPTION
                    'account_deletion_recovery_state_conflict'
                    USING ERRCODE = '55000';
            END IF;

            DELETE FROM internal.account_deletion_recovery_preparations
                AS preparation
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
        SELECT expired.expired_at, expired.deletion_committed
        INTO expired_preparation_at, expired_preparation_committed
        FROM internal.account_deletion_expired_preparation_proofs AS expired
        WHERE expired.proof_hash = p_recovery_secret_hash
          AND expired.proof_kind = 'recovery';
        IF FOUND THEN
            RETURN QUERY SELECT
                CASE
                    WHEN expired_preparation_committed
                        THEN 'preparation_expired'
                    ELSE 'not_committed'
                END::TEXT,
                FALSE,
                expired_preparation_at,
                FALSE;
            RETURN;
        END IF;

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
       AND capability_record.expires_at <= observed_at THEN
        RAISE EXCEPTION 'account_deletion_recovery_expired'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.account_deletion_recovery_capabilities AS capability
    SET last_recovered_at = observed_at
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
    'Service-only v2 recovery. A live preparation cancels non-destructive intent, an expired preparation returns a non-authorizing terminal state, and a committed proof returns only its bound deletion receipt.';

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
    retired_count BIGINT;
BEGIN
    PERFORM internal.require_service_role();
    IF p_limit < 1 OR p_limit > 500 THEN
        RAISE EXCEPTION 'account_deletion_recovery_prune_limit_invalid'
            USING ERRCODE = '22023';
    END IF;

    WITH expired AS MATERIALIZED (
        SELECT
            preparation.id,
            preparation.recovery_secret_hash,
            preparation.acknowledgement_secret_hash,
            preparation.expires_at
        FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE preparation.expires_at <= pg_catalog.STATEMENT_TIMESTAMP()
        ORDER BY preparation.expires_at, preparation.id
        LIMIT p_limit
        FOR UPDATE SKIP LOCKED
    ), recorded AS MATERIALIZED (
        INSERT INTO internal.account_deletion_expired_preparation_proofs (
            proof_hash,
            proof_kind,
            deletion_committed,
            expired_at
        )
        SELECT
            proof.proof_hash,
            proof.proof_kind,
            FALSE,
            expired.expires_at
        FROM expired
        CROSS JOIN LATERAL (
            VALUES
                (expired.recovery_secret_hash, 'recovery'::TEXT),
                (
                    expired.acknowledgement_secret_hash,
                    'acknowledgement'::TEXT
                )
        ) AS proof(proof_hash, proof_kind)
        ON CONFLICT (proof_hash) DO UPDATE
        SET expired_at = LEAST(
            internal.account_deletion_expired_preparation_proofs.expired_at,
            EXCLUDED.expired_at
        ), deletion_committed =
            internal.account_deletion_expired_preparation_proofs
                .deletion_committed
            OR EXCLUDED.deletion_committed
        RETURNING proof_hash
    ), recorded_preparations AS MATERIALIZED (
        SELECT expired.id
        FROM expired
        WHERE EXISTS (
                SELECT 1
                FROM recorded
                WHERE recorded.proof_hash = expired.recovery_secret_hash
            )
          AND EXISTS (
                SELECT 1
                FROM recorded
                WHERE recorded.proof_hash =
                    expired.acknowledgement_secret_hash
            )
    ), retired AS (
        DELETE FROM internal.account_deletion_recovery_preparations
            AS preparation
        USING recorded_preparations
        WHERE preparation.id = recorded_preparations.id
        RETURNING preparation.id
    )
    SELECT pg_catalog.COUNT(*)
    INTO retired_count
    FROM retired;

    RETURN retired_count;
END;
$function$;

COMMENT ON FUNCTION
public.prune_account_deletion_recovery_preparations(INTEGER) IS
    'Service-only bounded cleanup that records identity-free expired-proof tombstones before retiring stale protocol-v2 preparations.';

-- Once a proof has expired, no authenticated retry may reuse the same hash to
-- mint a new preparation or capability. A fresh deletion attempt must create
-- fresh device capabilities.
DO $repair_v2_prepare_reuse$
DECLARE
    routine_signature REGPROCEDURE := pg_catalog.TO_REGPROCEDURE(
        'public.prepare_account_deletion_recovery_v2(uuid,text,text)'
    );
    routine_definition TEXT;
    old_fragment CONSTANT TEXT := $old$
    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT jobs.*$old$;
    new_fragment CONSTANT TEXT := $new$
    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_expired_preparation_proofs AS expired
        WHERE expired.proof_hash IN (
            p_recovery_secret_hash,
            p_acknowledgement_secret_hash
        )
    ) THEN
        RAISE EXCEPTION 'account_deletion_recovery_preparation_expired'
            USING ERRCODE = '22023';
    END IF;

    SELECT jobs.*$new$;
BEGIN
    IF routine_signature IS NULL THEN
        RAISE EXCEPTION
            'account_deletion_v2_prepare_reuse_repair_missing_routine';
    END IF;
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_signature)
    INTO STRICT routine_definition;
    IF pg_catalog.STRPOS(routine_definition, old_fragment) = 0
       OR pg_catalog.STRPOS(
            pg_catalog.SUBSTRING(
                routine_definition,
                pg_catalog.STRPOS(routine_definition, old_fragment)
                    + pg_catalog.LENGTH(old_fragment)
            ),
            old_fragment
       ) > 0 THEN
        RAISE EXCEPTION
            'account_deletion_v2_prepare_reuse_repair_unexpected_definition';
    END IF;

    EXECUTE pg_catalog.REPLACE(
        routine_definition,
        old_fragment,
        new_fragment
    );
END;
$repair_v2_prepare_reuse$;

-- The destructive v2 commit used the committed-capability expiry code for a
-- preparation that had never authorized deletion. Replace only that reviewed
-- fragment so older clients fail closed instead of treating a 410 as accepted.
DO $repair_v2_commit_expiry$
DECLARE
    routine_signature REGPROCEDURE := pg_catalog.TO_REGPROCEDURE(
        'public.request_account_deletion_with_recovery_v2(uuid,text)'
    );
    routine_definition TEXT;
    old_fragment CONSTANT TEXT := $old$
    IF preparation_record.expires_at <= pg_catalog.NOW() THEN
        RAISE EXCEPTION 'account_deletion_recovery_expired'
            USING ERRCODE = '22023';
    END IF;$old$;
    new_fragment CONSTANT TEXT := $new$
    IF preparation_record.expires_at <= pg_catalog.NOW() THEN
        RAISE EXCEPTION 'account_deletion_recovery_preparation_expired'
            USING ERRCODE = '22023';
    END IF;$new$;
BEGIN
    IF routine_signature IS NULL THEN
        RAISE EXCEPTION
            'account_deletion_v2_commit_expiry_repair_missing_routine';
    END IF;
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_signature)
    INTO STRICT routine_definition;
    IF pg_catalog.STRPOS(routine_definition, old_fragment) = 0
       OR pg_catalog.STRPOS(
            pg_catalog.SUBSTRING(
                routine_definition,
                pg_catalog.STRPOS(routine_definition, old_fragment)
                    + pg_catalog.LENGTH(old_fragment)
            ),
            old_fragment
       ) > 0 THEN
        RAISE EXCEPTION
            'account_deletion_v2_commit_expiry_repair_unexpected_definition';
    END IF;

    EXECUTE pg_catalog.REPLACE(
        routine_definition,
        old_fragment,
        new_fragment
    );
END;
$repair_v2_commit_expiry$;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
