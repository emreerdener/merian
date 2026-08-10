-- Empty-Ghost cleanup is an operator-approved account-erasure workflow, not an
-- Auth Admin shortcut. Live database evidence must still prove that the target
-- is an old anonymous shell after RevenueCat has independently been verified.
-- The relational phase is completed in the same transaction as that final
-- proof, then the existing durable storage/provider/Auth state machine resumes.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE TABLE internal.empty_ghost_account_deletion_receipts (
    job_id UUID PRIMARY KEY
        REFERENCES internal.account_deletion_jobs(id) ON DELETE CASCADE,
    candidate_plan_sha256 TEXT NOT NULL,
    revenuecat_project_id TEXT NOT NULL,
    revenuecat_verified_at TIMESTAMPTZ NOT NULL,
    revenuecat_checked_customer_count INTEGER NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.NOW(),
    CONSTRAINT empty_ghost_receipt_plan_sha256_check CHECK (
        candidate_plan_sha256 ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT empty_ghost_receipt_revenuecat_project_check CHECK (
        revenuecat_project_id ~ '^proj[a-zA-Z0-9_-]{4,251}$'
    ),
    CONSTRAINT empty_ghost_receipt_customer_count_check CHECK (
        revenuecat_checked_customer_count BETWEEN 1 AND 50
    )
);

COMMENT ON TABLE internal.empty_ghost_account_deletion_receipts IS
    'Identity-free operator evidence attached to a durable deletion job. The exact reviewed candidate plan and recent live RevenueCat verification authorize only the guarded empty-Ghost intake.';

ALTER TABLE internal.empty_ghost_account_deletion_receipts
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.empty_ghost_account_deletion_receipts
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION internal.empty_ghost_cleanup_blockers(
    p_user_id UUID,
    p_threshold_days INTEGER
)
RETURNS TEXT[]
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $function$
DECLARE
    auth_user auth.users%ROWTYPE;
    app_user public.users%ROWTYPE;
    reference_policy RECORD;
    has_reference BOOLEAN;
    blockers TEXT[] := ARRAY[]::TEXT[];
    cutoff TIMESTAMPTZ;
BEGIN
    IF p_user_id IS NULL
       OR p_user_id =
            '00000000-0000-0000-0000-000000000000'::UUID
       OR p_threshold_days IS NULL
       OR p_threshold_days NOT BETWEEN 30 AND 365 THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_invalid_candidate'
            USING ERRCODE = '22023';
    END IF;

    cutoff := pg_catalog.STATEMENT_TIMESTAMP()
        - pg_catalog.MAKE_INTERVAL(days => p_threshold_days);

    PERFORM internal.assert_ghost_profile_merge_reference_policy_coverage();

    SELECT candidate.*
    INTO auth_user
    FROM auth.users AS candidate
    WHERE candidate.id = p_user_id;

    IF NOT FOUND THEN
        RETURN pg_catalog.ARRAY_APPEND(blockers, 'auth_user_missing');
    END IF;

    IF auth_user.is_anonymous IS NOT TRUE THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'auth_user_not_anonymous'
        );
    END IF;
    IF NULLIF(pg_catalog.BTRIM(auth_user.email), '') IS NOT NULL THEN
        blockers := pg_catalog.ARRAY_APPEND(blockers, 'auth_email_present');
    END IF;
    IF NULLIF(pg_catalog.BTRIM(auth_user.phone), '') IS NOT NULL THEN
        blockers := pg_catalog.ARRAY_APPEND(blockers, 'auth_phone_present');
    END IF;
    IF auth_user.created_at IS NULL OR auth_user.created_at > cutoff THEN
        blockers := pg_catalog.ARRAY_APPEND(blockers, 'auth_user_too_recent');
    END IF;
    IF auth_user.last_sign_in_at IS NULL
       OR auth_user.last_sign_in_at > cutoff THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'auth_sign_in_too_recent'
        );
    END IF;
    IF EXISTS (
        SELECT 1
        FROM auth.identities AS identity
        WHERE identity.user_id = p_user_id
          AND identity.provider <> 'anonymous'
    ) THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'non_anonymous_identity_present'
        );
    END IF;
    IF EXISTS (
        SELECT 1
        FROM auth.sessions AS auth_session
        WHERE auth_session.user_id = p_user_id
          AND auth_session.updated_at > cutoff
    ) THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'recent_auth_session_present'
        );
    END IF;

    SELECT profile.*
    INTO app_user
    FROM public.users AS profile
    WHERE profile.id = p_user_id;

    IF FOUND THEN
        IF NULLIF(pg_catalog.BTRIM(app_user.email), '') IS NOT NULL THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'public_email_present'
            );
        END IF;
        IF app_user.subscription_tier <>
            'free'::public.subscription_tier_enum THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'paid_projection_present'
            );
        END IF;
        IF app_user.subscription_expires_at IS NOT NULL THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'subscription_expiry_present'
            );
        END IF;
        IF app_user.public_identity_source IS NOT NULL
           AND app_user.public_identity_source <> 'alias' THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'custom_identity_source_present'
            );
        END IF;
        IF NULLIF(pg_catalog.BTRIM(app_user.public_author_name), '')
            IS NOT NULL
           AND app_user.public_author_name IS DISTINCT FROM
                app_user.public_username THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'custom_author_name_present'
            );
        END IF;
        IF NULLIF(pg_catalog.BTRIM(app_user.public_username), '')
            IS NOT NULL
           AND app_user.public_username IS DISTINCT FROM
                public.build_default_public_username(p_user_id) THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'custom_public_username_present'
            );
        END IF;
        IF NULLIF(pg_catalog.BTRIM(app_user.custom_avatar_url), '')
            IS NOT NULL THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'custom_avatar_present'
            );
        END IF;
        IF app_user.current_streak_count <> 0
           OR app_user.rest_day_tokens <> 0
           OR app_user.total_species_discovered <> 0
           OR app_user.default_geoprivacy <>
                'open'::public.geoprivacy_enum
           OR app_user.marketing_opt_in IS TRUE
           OR app_user.abuse_strikes <> 0
           OR app_user.is_shadowbanned IS TRUE THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                'profile_activity_present'
            );
        END IF;
    END IF;

    -- This one trip and period are inserted automatically for every profile.
    -- Any second trip, changed lifecycle field, completion, or non-baseline
    -- period is real account state and blocks deletion.
    IF (
        SELECT pg_catalog.COUNT(*)
        FROM public.user_field_trips AS trip
        WHERE trip.user_id = p_user_id
    ) > 1 OR EXISTS (
        SELECT 1
        FROM public.user_field_trips AS trip
        JOIN public.field_trip_templates AS template
          ON template.id = trip.template_id
        WHERE trip.user_id = p_user_id
          AND (
              template.slug <> 'backyard_safari'
              OR trip.current_level_number <> 1
              OR trip.completed_at IS NOT NULL
              OR trip.is_profile_visible IS NOT TRUE
              OR trip.hidden_at IS NOT NULL
              OR trip.started_at IS DISTINCT FROM trip.created_at
              OR trip.updated_at IS DISTINCT FROM trip.created_at
              OR (
                  SELECT pg_catalog.COUNT(*)
                  FROM public.user_field_trip_active_periods AS period
                  WHERE period.user_field_trip_id = trip.id
              ) <> 1
              OR EXISTS (
                  SELECT 1
                  FROM public.user_field_trip_active_periods AS period
                  WHERE period.user_field_trip_id = trip.id
                    AND (
                        period.started_at IS DISTINCT FROM trip.started_at
                        OR period.stopped_at IS NOT NULL
                        OR period.created_at IS DISTINCT FROM trip.created_at
                    )
              )
          )
    ) THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'field_trip_activity_present'
        );
    END IF;

    -- Every reviewed current or future FK blocks by default. The public profile
    -- itself, the exact automatic trip above, and the provider repair queue /
    -- ordering watermark are the only system-owned exceptions. The public
    -- free projection plus the recent live RevenueCat proof are authoritative
    -- for the watermark exception; webhook subject history still blocks.
    FOR reference_policy IN
        SELECT
            policy.source_schema,
            policy.source_table,
            policy.source_column
        FROM internal.ghost_profile_merge_reference_policies AS policy
        WHERE NOT (
            policy.source_schema = 'public'
            AND policy.source_table = 'users'
            AND policy.source_column = 'id'
        )
          AND NOT (
            policy.source_schema = 'public'
            AND policy.source_table = 'user_field_trips'
            AND policy.source_column = 'user_id'
        )
          AND NOT (
            policy.source_schema = 'internal'
            AND policy.source_table = 'revenuecat_reconciliation_queue'
            AND policy.source_column = 'merian_user_id'
        )
          AND NOT (
            policy.source_schema = 'internal'
            AND policy.source_table = 'revenuecat_customer_state'
            AND policy.source_column = 'merian_user_id'
        )
        ORDER BY
            policy.source_schema,
            policy.source_table,
            policy.source_column
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I = $1)',
            reference_policy.source_schema,
            reference_policy.source_table,
            reference_policy.source_column
        )
        INTO has_reference
        USING p_user_id;

        IF has_reference THEN
            blockers := pg_catalog.ARRAY_APPEND(
                blockers,
                pg_catalog.FORMAT(
                    'reference:%I.%I.%I',
                    reference_policy.source_schema,
                    reference_policy.source_table,
                    reference_policy.source_column
                )
            );
        END IF;
    END LOOP;

    -- These intentional logical references do not use user foreign keys and
    -- therefore cannot be discovered through the reviewed merge manifest.
    IF EXISTS (
        SELECT 1
        FROM public.ai_usage_events AS usage
        WHERE usage.user_id = p_user_id
    ) THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'reference:public.ai_usage_events.user_id'
        );
    END IF;
    IF EXISTS (
        SELECT 1
        FROM public.pending_storage_deletions AS storage
        WHERE storage.target_user_id = p_user_id
    ) THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'account_storage_deletion_already_present'
        );
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
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'account_deletion_already_active'
        );
    END IF;
    IF EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_handoffs AS handoff
        WHERE handoff.ghost_user_id = p_user_id
          AND (
              handoff.status = 'prepared'
              OR (
                  handoff.status = 'merged'
                  AND handoff.auth_deleted_at IS NULL
              )
          )
    ) THEN
        blockers := pg_catalog.ARRAY_APPEND(
            blockers,
            'ghost_profile_merge_active'
        );
    END IF;

    RETURN blockers;
END;
$function$;

COMMENT ON FUNCTION internal.empty_ghost_cleanup_blockers(UUID, INTEGER) IS
    'Fail-closed live evidence resolver for old anonymous cleanup candidates. Every reviewed user reference blocks unless it is one exact system-created baseline.';

REVOKE ALL ON FUNCTION internal.empty_ghost_cleanup_blockers(UUID, INTEGER)
    FROM PUBLIC, anon, authenticated, service_role;

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

    RETURN QUERY
    SELECT
        pg_catalog.CARDINALITY(resolved_blockers) = 0,
        resolved_blockers;
END;
$function$;

COMMENT ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(UUID, INTEGER)
IS 'Service-only read of the same live fail-closed evidence used by empty-Ghost deletion intake.';

CREATE OR REPLACE FUNCTION internal.reject_ghost_merge_during_account_deletion()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.status IN ('prepared', 'merged')
       AND EXISTS (
           SELECT 1
           FROM internal.account_deletion_jobs AS deletion_job
           WHERE deletion_job.user_id = NEW.ghost_user_id
             AND deletion_job.status IN (
                 'pending',
                 'storage_pending',
                 'auth_pending'
             )
       ) THEN
        RAISE EXCEPTION 'ghost_merge_source_deletion_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION internal.reject_ghost_merge_during_account_deletion() IS
    'Prevents a Ghost login/merge handoff from starting after guarded or user-requested durable account deletion has begun.';

REVOKE ALL ON FUNCTION internal.reject_ghost_merge_during_account_deletion()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS reject_ghost_merge_during_account_deletion
    ON internal.ghost_profile_merge_handoffs;
CREATE TRIGGER reject_ghost_merge_during_account_deletion
BEFORE INSERT OR UPDATE OF ghost_user_id, status
ON internal.ghost_profile_merge_handoffs
FOR EACH ROW
EXECUTE FUNCTION internal.reject_ghost_merge_during_account_deletion();

CREATE OR REPLACE FUNCTION public.request_empty_ghost_account_deletion(
    p_user_id UUID,
    p_reservation_token UUID,
    p_threshold_days INTEGER,
    p_candidate_plan_sha256 TEXT,
    p_revenuecat_project_id TEXT,
    p_revenuecat_verified_at TIMESTAMPTZ,
    p_revenuecat_checked_customer_count INTEGER
)
RETURNS TABLE (
    job_id UUID,
    job_status TEXT,
    manual_provider_revocation_required BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '30s'
AS $function$
DECLARE
    requested_job_id UUID;
    requested_manual_provider_revocation_required BOOLEAN;
    claimed_job_id UUID;
    claimed_token UUID;
    live_blockers TEXT[];
    cleanup_status TEXT;
BEGIN
    PERFORM internal.require_service_role();

    IF p_reservation_token IS NULL
       OR p_candidate_plan_sha256 IS NULL
       OR p_candidate_plan_sha256 !~ '^[0-9a-f]{64}$'
       OR p_revenuecat_project_id IS NULL
       OR p_revenuecat_project_id !~ '^proj[a-zA-Z0-9_-]{4,251}$'
       OR p_revenuecat_verified_at IS NULL
       OR p_revenuecat_verified_at <
            pg_catalog.STATEMENT_TIMESTAMP() - INTERVAL '10 minutes'
       OR p_revenuecat_verified_at >
            pg_catalog.STATEMENT_TIMESTAMP() + INTERVAL '1 minute'
       OR p_revenuecat_checked_customer_count IS NULL
       OR p_revenuecat_checked_customer_count NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_invalid_evidence'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTENDED(
            'ghost-profile-merge:' || p_user_id::TEXT,
            0
        )
    );

    PERFORM active_reservation.ghost_user_id
    FROM internal.ghost_user_cleanup_reservations AS active_reservation
    WHERE active_reservation.ghost_user_id = p_user_id
      AND active_reservation.reservation_token = p_reservation_token
      AND active_reservation.completed_at IS NULL
      AND active_reservation.expires_at > pg_catalog.NOW()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ghost_cleanup_reservation_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    -- The profile lock serializes new FK-backed application activity against
    -- the final proof. Inserts arriving later wait and then fail after the
    -- public profile is removed in this transaction. The Auth lock coordinates
    -- durable deletion intake; already-committed sessions were checked above,
    -- while profile recreation remains blocked for the lifetime of the job.
    PERFORM candidate.id
    FROM auth.users AS candidate
    WHERE candidate.id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_auth_user_missing'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM profile.id
    FROM public.users AS profile
    WHERE profile.id = p_user_id
    FOR UPDATE;

    live_blockers := internal.empty_ghost_cleanup_blockers(
        p_user_id,
        p_threshold_days
    );
    IF pg_catalog.CARDINALITY(live_blockers) <> 0 THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_live_evidence_present'
            USING ERRCODE = '55000',
                  DETAIL = pg_catalog.ARRAY_TO_STRING(live_blockers, ',');
    END IF;

    SELECT
        deletion.job_id,
        deletion.manual_provider_revocation_required
    INTO STRICT
        requested_job_id,
        requested_manual_provider_revocation_required
    FROM public.request_account_deletion(p_user_id) AS deletion;

    IF requested_manual_provider_revocation_required IS TRUE THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_provider_identity_present'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO internal.empty_ghost_account_deletion_receipts (
        job_id,
        candidate_plan_sha256,
        revenuecat_project_id,
        revenuecat_verified_at,
        revenuecat_checked_customer_count
    )
    VALUES (
        requested_job_id,
        p_candidate_plan_sha256,
        p_revenuecat_project_id,
        p_revenuecat_verified_at,
        p_revenuecat_checked_customer_count
    );

    SELECT claim.job_id, claim.claim_token
    INTO STRICT claimed_job_id, claimed_token
    FROM public.claim_account_deletion_jobs(1, p_user_id) AS claim;

    IF claimed_job_id <> requested_job_id THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_claim_mismatch'
            USING ERRCODE = '55000';
    END IF;

    SELECT public.complete_account_deletion_cleanup(
        claimed_job_id,
        claimed_token
    )
    INTO STRICT cleanup_status;

    IF cleanup_status <> 'storage_pending' THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_unexpected_durable_state'
            USING ERRCODE = '55000';
    END IF;

    UPDATE internal.ghost_user_cleanup_reservations AS completed_reservation
    SET completed_at = pg_catalog.NOW(),
        last_error_code = NULL,
        updated_at = pg_catalog.NOW()
    WHERE completed_reservation.ghost_user_id = p_user_id
      AND completed_reservation.reservation_token = p_reservation_token
      AND completed_reservation.completed_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ghost_cleanup_reservation_not_found'
            USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
    SELECT
        requested_job_id,
        cleanup_status,
        requested_manual_provider_revocation_required;
END;
$function$;

COMMENT ON FUNCTION public.request_empty_ghost_account_deletion(
    UUID,
    UUID,
    INTEGER,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    INTEGER
) IS 'Service-only guarded intake for a reviewed old empty Ghost. It revalidates every database reference and atomically enters the durable relational/storage/provider/Auth deletion state machine.';

REVOKE ALL ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(
    UUID,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.request_empty_ghost_account_deletion(
    UUID,
    UUID,
    INTEGER,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    INTEGER
) FROM PUBLIC, anon, authenticated, service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.inspect_empty_ghost_cleanup_candidate(uuid,integer)',
        'Operator audit reads the exact live blockers used by guarded empty-Ghost deletion.'
    ),
    (
        'service_role',
        'public.request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamp with time zone,integer)',
        'Reviewed empty-Ghost cleanup atomically revalidates evidence and enters durable account deletion.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

GRANT EXECUTE ON FUNCTION public.inspect_empty_ghost_cleanup_candidate(
    UUID,
    INTEGER
) TO service_role;
GRANT EXECUTE ON FUNCTION public.request_empty_ghost_account_deletion(
    UUID,
    UUID,
    INTEGER,
    TEXT,
    TEXT,
    TIMESTAMPTZ,
    INTEGER
) TO service_role;

DO $acl_check$
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.empty_ghost_account_deletion_receipts',
        'SELECT'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.inspect_empty_ghost_cleanup_candidate(uuid,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.inspect_empty_ghost_cleanup_candidate(uuid,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamp with time zone,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamp with time zone,integer)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.inspect_empty_ghost_cleanup_candidate(uuid,integer)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamp with time zone,integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'empty_ghost_cleanup_rpc_acl_invalid';
    END IF;
END;
$acl_check$;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
