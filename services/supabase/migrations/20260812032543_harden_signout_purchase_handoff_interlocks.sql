-- A bound sign-out handoff names one exact anonymous destination. Destructive
-- account workflows, automatic anonymous cleanup, and profile merging must not
-- delete or replace that destination while RevenueCat verification is
-- retryable. The Auth-user locks below serialize the two competing state
-- transitions without holding a database transaction across provider I/O.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE OR REPLACE FUNCTION internal.reject_account_deletion_during_signout_handoff()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.user_id IS NOT NULL
       AND NEW.status IN ('pending', 'storage_pending', 'auth_pending')
       AND EXISTS (
           SELECT 1
           FROM internal.signout_purchase_handoffs AS handoff
           WHERE handoff.status = 'bound'
             AND NEW.user_id IN (
                 handoff.source_user_id,
                 handoff.destination_user_id
             )
       ) THEN
        RAISE EXCEPTION 'signout_handoff_destination_deletion_blocked'
            USING ERRCODE = '55000';
    END IF;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION internal.reject_account_deletion_during_signout_handoff()
IS 'Prevents durable account deletion from removing either side of an active sign-out purchase handoff.';

REVOKE ALL ON FUNCTION internal.reject_account_deletion_during_signout_handoff()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS reject_account_deletion_during_signout_handoff
    ON internal.account_deletion_jobs;
CREATE TRIGGER reject_account_deletion_during_signout_handoff
BEFORE INSERT OR UPDATE OF user_id, status
ON internal.account_deletion_jobs
FOR EACH ROW
EXECUTE FUNCTION internal.reject_account_deletion_during_signout_handoff();

CREATE OR REPLACE FUNCTION internal.reject_ghost_merge_during_signout_handoff()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.status IN ('prepared', 'merged')
       AND EXISTS (
           SELECT 1
           FROM internal.signout_purchase_handoffs AS handoff
           WHERE handoff.destination_user_id = NEW.ghost_user_id
             AND handoff.status = 'bound'
       ) THEN
        RAISE EXCEPTION 'signout_purchase_handoff_pending'
            USING ERRCODE = '55P03';
    END IF;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION internal.reject_ghost_merge_during_signout_handoff() IS
    'Prevents account-upgrade preparation or consumption from deleting an anonymous identity whose sign-out purchase handoff is still bound.';

REVOKE ALL ON FUNCTION internal.reject_ghost_merge_during_signout_handoff()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS reject_ghost_merge_during_signout_handoff
    ON internal.ghost_profile_merge_handoffs;
CREATE TRIGGER reject_ghost_merge_during_signout_handoff
BEFORE INSERT OR UPDATE OF ghost_user_id, status
ON internal.ghost_profile_merge_handoffs
FOR EACH ROW
EXECUTE FUNCTION internal.reject_ghost_merge_during_signout_handoff();

CREATE OR REPLACE FUNCTION public.request_account_deletion(
    p_user_id UUID
)
RETURNS TABLE (
    job_id UUID,
    job_status TEXT,
    manual_provider_revocation_required BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    has_apple_identity BOOLEAN;
    has_apple_credential BOOLEAN;
    provider_status TEXT;
    provider_resolved_at TIMESTAMPTZ;
    manual_revocation_required BOOLEAN;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_user_id =
           '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'account_deletion_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    -- bind_signout_purchase_handoff locks the same Auth rows before it writes
    -- the destination. Whichever transition wins forces the loser to observe
    -- the committed blocker after waiting; neither path uses inverse locks.
    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'account_deletion_user_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.signout_purchase_handoffs AS handoff
        WHERE handoff.status = 'bound'
          AND p_user_id IN (
              handoff.source_user_id,
              handoff.destination_user_id
          )
    ) THEN
        RAISE EXCEPTION 'signout_handoff_destination_deletion_blocked'
            USING ERRCODE = '55000';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM auth.identities AS identity
        WHERE identity.user_id = p_user_id
          AND identity.provider = 'apple'
    ) INTO has_apple_identity;

    SELECT EXISTS (
        SELECT 1
        FROM internal.apple_sign_in_revocation_credentials AS credential
        WHERE credential.user_id = p_user_id
    ) INTO has_apple_credential;

    IF has_apple_credential THEN
        provider_status := 'pending';
        provider_resolved_at := NULL;
        manual_revocation_required := FALSE;
    ELSIF has_apple_identity THEN
        provider_status := 'manual_required';
        provider_resolved_at := pg_catalog.NOW();
        manual_revocation_required := TRUE;
    ELSE
        provider_status := 'not_required';
        provider_resolved_at := pg_catalog.NOW();
        manual_revocation_required := FALSE;
    END IF;

    RETURN QUERY
    INSERT INTO internal.account_deletion_jobs AS deletion_job (
        user_id,
        status,
        provider_revocation_status,
        provider_revocation_resolved_at,
        manual_provider_revocation_required,
        next_attempt_at
    )
    VALUES (
        p_user_id,
        'pending',
        provider_status,
        provider_resolved_at,
        manual_revocation_required,
        pg_catalog.NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET updated_at = pg_catalog.NOW()
    RETURNING
        deletion_job.id,
        deletion_job.status,
        deletion_job.manual_provider_revocation_required;
END;
$function$;

COMMENT ON FUNCTION public.request_account_deletion(UUID) IS
    'Service-only idempotent deletion intake. It records Apple revocation disposition and refuses to delete either identity in a bound sign-out purchase handoff.';

CREATE OR REPLACE FUNCTION public.bind_signout_purchase_handoff(
    p_handoff_id UUID,
    p_secret_hash TEXT
)
RETURNS TABLE (
    handoff_id UUID,
    source_user_id UUID,
    destination_user_id UUID,
    source_snapshot_at_ms BIGINT,
    expected_store_tier TEXT,
    expected_store_expires_at TIMESTAMPTZ,
    handoff_status TEXT,
    destination_verified_snapshot_at_ms BIGINT,
    destination_verified_store_tier TEXT,
    destination_verified_store_expires_at TIMESTAMPTZ,
    bound_at TIMESTAMPTZ,
    already_bound BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    caller_id UUID := auth.uid();
    source_id UUID;
    destination_created_at TIMESTAMPTZ;
    handoff_record internal.signout_purchase_handoffs%ROWTYPE;
BEGIN
    IF caller_id IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_authentication_required'
            USING ERRCODE = '42501';
    END IF;

    IF p_handoff_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT handoff.source_user_id
    INTO source_id
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id;

    IF source_id IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'signout-purchase-handoff:' || source_id::TEXT,
            0
        )
    );

    SELECT handoff.*
    INTO STRICT handoff_record
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = p_handoff_id
    FOR UPDATE;

    IF handoff_record.secret_hash <> p_secret_hash THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    IF handoff_record.status IN ('bound', 'completed') THEN
        IF handoff_record.destination_user_id <> caller_id THEN
            RAISE EXCEPTION 'signout_handoff_invalid'
                USING ERRCODE = 'P0002';
        END IF;

        RETURN QUERY SELECT
            handoff_record.id,
            handoff_record.source_user_id,
            handoff_record.destination_user_id,
            handoff_record.source_snapshot_at_ms,
            handoff_record.expected_store_tier,
            handoff_record.expected_store_expires_at,
            handoff_record.status,
            handoff_record.destination_verified_snapshot_at_ms,
            handoff_record.destination_verified_store_tier,
            handoff_record.destination_verified_store_expires_at,
            handoff_record.bound_at,
            TRUE;
        RETURN;
    END IF;

    IF handoff_record.status = 'expired'
       OR (
           handoff_record.status = 'prepared'
           AND handoff_record.expires_at <= pg_catalog.NOW()
       ) THEN
        RAISE EXCEPTION 'signout_handoff_expired'
            USING ERRCODE = 'P0001';
    END IF;

    IF handoff_record.status <> 'prepared'
       OR caller_id = handoff_record.source_user_id THEN
        RAISE EXCEPTION 'signout_handoff_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id IN (handoff_record.source_user_id, caller_id)
    ORDER BY auth_user.id
    FOR UPDATE;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = handoff_record.source_user_id
          AND auth_user.is_anonymous IS FALSE
    ) THEN
        RAISE EXCEPTION 'signout_handoff_source_not_available'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT auth_user.created_at
    INTO destination_created_at
    FROM auth.users AS auth_user
    WHERE auth_user.id = caller_id
      AND auth_user.is_anonymous IS TRUE;

    IF destination_created_at IS NULL THEN
        RAISE EXCEPTION 'signout_handoff_anonymous_destination_required'
            USING ERRCODE = '42501';
    END IF;

    IF destination_created_at < handoff_record.created_at THEN
        RAISE EXCEPTION 'signout_handoff_fresh_anonymous_destination_required'
            USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.user_id IN (
            handoff_record.source_user_id,
            caller_id
        )
          AND deletion_job.status IN (
              'pending',
              'storage_pending',
              'auth_pending'
          )
    ) THEN
        RAISE EXCEPTION 'signout_handoff_destination_deletion_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    UPDATE internal.signout_purchase_handoffs AS handoff
    SET destination_user_id = caller_id,
        status = 'bound',
        bound_at = pg_catalog.NOW(),
        updated_at = pg_catalog.NOW()
    WHERE handoff.id = handoff_record.id
    RETURNING handoff.*
    INTO handoff_record;

    RETURN QUERY SELECT
        handoff_record.id,
        handoff_record.source_user_id,
        handoff_record.destination_user_id,
        handoff_record.source_snapshot_at_ms,
        handoff_record.expected_store_tier,
        handoff_record.expected_store_expires_at,
        handoff_record.status,
        handoff_record.destination_verified_snapshot_at_ms,
        handoff_record.destination_verified_store_tier,
        handoff_record.destination_verified_store_expires_at,
        handoff_record.bound_at,
        FALSE;
END;
$function$;

COMMENT ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT) IS
    'Authenticated anonymous destination binds one prepared proof. The destination must be newer than the proof and cannot be entering account deletion.';

CREATE OR REPLACE FUNCTION public.inspect_empty_ghost_cleanup_candidate(
    p_user_id UUID,
    p_threshold_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    eligible BOOLEAN,
    blockers TEXT[]
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '20s'
AS $function$
DECLARE
    resolved_blockers TEXT[];
BEGIN
    PERFORM internal.require_service_role();
    resolved_blockers := internal.empty_ghost_cleanup_blockers(
        p_user_id,
        p_threshold_days
    );

    IF EXISTS (
        SELECT 1
        FROM internal.signout_purchase_handoffs AS handoff
        WHERE handoff.destination_user_id = p_user_id
          AND handoff.status = 'bound'
    ) THEN
        resolved_blockers := pg_catalog.ARRAY_APPEND(
            resolved_blockers,
            'signout_purchase_handoff_active'
        );
    END IF;

    RETURN QUERY
    SELECT
        pg_catalog.CARDINALITY(resolved_blockers) = 0,
        resolved_blockers;
END;
$function$;

COMMENT ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(UUID, INTEGER)
IS 'Service-only live cleanup evidence. A bound sign-out purchase destination is never an eligible anonymous shell.';

-- Reassert the pre-existing least-privilege surface after function replacement.
REVOKE ALL ON FUNCTION public.request_account_deletion(UUID)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT)
    FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(UUID, INTEGER)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.request_account_deletion(UUID)
    TO service_role;
GRANT EXECUTE ON FUNCTION public.bind_signout_purchase_handoff(UUID, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(UUID, INTEGER)
    TO service_role;

RESET statement_timeout;
RESET lock_timeout;
