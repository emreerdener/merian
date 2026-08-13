SET lock_timeout = '10s';
SET statement_timeout = '2min';

-- Account-deletion intake, recovery, and preparation creation all serialize on
-- the Auth user before they touch a prepared proof. Keep the bounded expiry
-- pruner in that same order so a deletion that already owns the user lock can
-- commit its classification before cleanup observes the preparation.
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
    observed_at TIMESTAMPTZ := pg_catalog.STATEMENT_TIMESTAMP();
    candidate_user_id UUID;
    remaining_limit INTEGER;
    retired_for_user BIGINT;
    retired_count BIGINT := 0;
BEGIN
    PERFORM internal.require_service_role();
    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
        RAISE EXCEPTION 'account_deletion_recovery_prune_limit_invalid'
            USING ERRCODE = '22023';
    END IF;
    remaining_limit := p_limit;

    -- The ordered Auth-user locks are the shared parent lock for deletion,
    -- recovery, preparation creation, and pruning. Bound the outer candidate
    -- set as well as the inner preparation set, and skip users already owned
    -- by deletion/recovery work so a small cleanup batch cannot wait behind or
    -- lock an unrelated account. Each user's preparations are locked only
    -- after the matching Auth row has been acquired.
    FOR candidate_user_id IN
        SELECT auth_user.id
        FROM auth.users AS auth_user
        WHERE EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations
                AS preparation
            WHERE preparation.user_id = auth_user.id
              AND preparation.expires_at <= observed_at
        )
        ORDER BY auth_user.id
        LIMIT p_limit
        FOR UPDATE OF auth_user SKIP LOCKED
    LOOP
        EXIT WHEN remaining_limit <= 0;

        WITH expired AS MATERIALIZED (
            SELECT
                preparation.id,
                preparation.recovery_secret_hash,
                preparation.acknowledgement_secret_hash,
                preparation.expires_at
            FROM internal.account_deletion_recovery_preparations
                AS preparation
            WHERE preparation.user_id = candidate_user_id
              AND preparation.expires_at <= observed_at
            ORDER BY preparation.expires_at, preparation.id
            LIMIT remaining_limit
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
                internal.account_deletion_expired_preparation_proofs
                    .expired_at,
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
                    WHERE recorded.proof_hash =
                        expired.recovery_secret_hash
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
        INTO retired_for_user
        FROM retired;

        retired_count := retired_count + retired_for_user;
        remaining_limit := remaining_limit - retired_for_user::INTEGER;
    END LOOP;

    RETURN retired_count;
END;
$function$;

COMMENT ON FUNCTION
public.prune_account_deletion_recovery_preparations(INTEGER) IS
    'Service-only bounded cleanup that locks each Auth user before recording identity-free expired-proof tombstones and retiring that user''s stale protocol-v2 preparations.';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
