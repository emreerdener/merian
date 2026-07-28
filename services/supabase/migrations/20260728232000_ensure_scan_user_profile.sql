-- A replayed or authenticated scan may encounter an auth.users identity whose
-- public profile is absent. Directly inserting only (id, subscription_tier)
-- has been invalid since Explore made the public identity columns mandatory.
-- Keep profile repair inside one service-only database boundary so it uses the
-- same identity derivation as Auth signup and cannot race account retirement.

SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION public.ensure_scan_user_profile(
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $$
DECLARE
    auth_email TEXT;
    auth_metadata JSONB;
    resolved_name TEXT;
    resolved_source TEXT;
    resolved_username TEXT;
    resolved_avatar_url TEXT;
    username_attempt INTEGER := 0;
    violated_constraint TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_user_id =
           '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'scan_user_profile_invalid_user'
            USING ERRCODE = '22023';
    END IF;

    -- Match the lock used by account merge and empty-ghost cleanup. An old
    -- ghost session must never recreate the public profile after its ownership
    -- has moved to a permanent account.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'ghost-profile-merge:' || p_user_id::TEXT,
            0
        )
    );

    SELECT
        auth_user.email,
        COALESCE(
            public.public_author_metadata_for_auth_user(auth_user.id),
            auth_user.raw_user_meta_data,
            '{}'::JSONB
        )
    INTO auth_email, auth_metadata
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_user_id
    FOR KEY SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'scan_user_auth_identity_missing'
            USING ERRCODE = '23503';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.user_id = p_user_id
          AND deletion_job.status IN (
              'pending',
              'storage_pending',
              'auth_pending'
          )
    ) THEN
        RAISE EXCEPTION 'scan_user_account_deletion_in_progress'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_handoffs AS handoff
        WHERE handoff.ghost_user_id = p_user_id
          AND handoff.status = 'merged'
    ) THEN
        RAISE EXCEPTION 'scan_user_identity_retired'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_user_cleanup_reservations AS reservation
        WHERE reservation.ghost_user_id = p_user_id
          AND reservation.completed_at IS NULL
          AND reservation.expires_at > pg_catalog.NOW()
    ) THEN
        RAISE EXCEPTION 'scan_user_cleanup_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.users AS profile
        WHERE profile.id = p_user_id
    ) THEN
        RETURN FALSE;
    END IF;

    SELECT identity.author_name, identity.identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(
        auth_metadata,
        p_user_id
    ) AS identity;

    resolved_avatar_url := public.resolve_public_avatar_url(
        NULL,
        auth_metadata
    );

    LOOP
        resolved_username := public.build_unique_public_username(
            resolved_name,
            p_user_id
        );

        BEGIN
            INSERT INTO public.users (
                id,
                email,
                subscription_tier,
                public_author_name,
                public_identity_source,
                public_avatar_url,
                public_username
            )
            VALUES (
                p_user_id,
                auth_email,
                'free',
                CASE
                    WHEN resolved_source = 'alias'
                        THEN resolved_username
                    ELSE resolved_name
                END,
                resolved_source,
                resolved_avatar_url,
                resolved_username
            );

            RETURN TRUE;
        EXCEPTION
            WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS
                    violated_constraint = CONSTRAINT_NAME;

                -- A concurrent request for this same auth identity won.
                IF EXISTS (
                    SELECT 1
                    FROM public.users AS profile
                    WHERE profile.id = p_user_id
                ) THEN
                    RETURN FALSE;
                END IF;

                username_attempt := username_attempt + 1;
                IF violated_constraint IS DISTINCT FROM
                       'users_public_username_unique_idx'
                   OR username_attempt > 4 THEN
                    RAISE;
                END IF;
        END;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.ensure_scan_user_profile(UUID) IS
    'Service-only, merge-aware repair for a real Auth identity whose mandatory public profile is absent before durable scan insertion.';

REVOKE ALL ON FUNCTION public.ensure_scan_user_profile(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ensure_scan_user_profile(UUID)
    TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.ensure_scan_user_profile(uuid)',
    'Scan ingestion profile prerequisite; derives mandatory public identity from the exact Auth owner and refuses retired identities.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

RESET statement_timeout;
RESET lock_timeout;

NOTIFY pgrst, 'reload schema';
