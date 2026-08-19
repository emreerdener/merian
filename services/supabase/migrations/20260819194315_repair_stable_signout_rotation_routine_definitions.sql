SET lock_timeout = '10s';
SET statement_timeout = '2min';

-- Reinstall the final protocol-v3 routine definitions through a forward
-- migration. This repairs any persistent catalog that recorded the initial
-- migration before its preparation-variable and expired-receipt corrections.
CREATE OR REPLACE FUNCTION public.prepare_purchase_principal_signout_rotation(
    p_auth_user_id UUID,
    p_capability_hash TEXT,
    p_rotation_id UUID,
    p_secret_hash TEXT,
    p_expected_binding_generation BIGINT,
    p_client_protocol INTEGER
)
RETURNS TABLE (
    rotation_id UUID,
    purchase_principal_id UUID,
    revenuecat_app_user_id TEXT,
    binding_generation BIGINT,
    rotation_status TEXT,
    expires_at TIMESTAMPTZ,
    already_prepared BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
DECLARE
    rollout internal.purchase_identity_rollout_config%ROWTYPE;
    principal internal.purchase_principals%ROWTYPE;
    binding internal.purchase_principal_bindings%ROWTYPE;
    existing internal.purchase_principal_signout_rotations%ROWTYPE;
    source_is_anonymous BOOLEAN;
    rotation_prepared_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    rotation_expires_at TIMESTAMPTZ;
BEGIN
    PERFORM internal.require_service_role();

    IF p_auth_user_id IS NULL
       OR p_capability_hash IS NULL
       OR p_capability_hash !~ '^[0-9a-f]{64}$'
       OR p_rotation_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$'
       OR p_expected_binding_generation IS NULL
       OR p_expected_binding_generation <= 0
       OR p_client_protocol IS NULL
       OR p_client_protocol NOT BETWEEN 3 AND 1000 THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT config.*
    INTO STRICT rollout
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current';
    IF p_client_protocol < rollout.minimum_client_protocol THEN
        RAISE EXCEPTION 'purchase_principal_client_upgrade_required'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal-capability:' || p_capability_hash,
            0::BIGINT
        )
    );

    SELECT principals.*
    INTO principal
    FROM internal.purchase_principals AS principals
    WHERE principals.capability_hash = p_capability_hash;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_unavailable'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal:' || principal.id::TEXT,
            0::BIGINT
        )
    );

    SELECT principals.*
    INTO STRICT principal
    FROM internal.purchase_principals AS principals
    WHERE principals.id = principal.id
      AND principals.capability_hash = p_capability_hash
      AND principals.status = 'active'
    FOR UPDATE;

    SELECT principal_binding.*
    INTO STRICT binding
    FROM internal.purchase_principal_bindings AS principal_binding
    WHERE principal_binding.purchase_principal_id = principal.id
    FOR UPDATE;
    IF binding.auth_user_id <> p_auth_user_id
       OR binding.binding_generation <> p_expected_binding_generation THEN
        RAISE EXCEPTION 'purchase_principal_signout_binding_changed'
            USING ERRCODE = '40001';
    END IF;

    SELECT auth_user.is_anonymous
    INTO STRICT source_is_anonymous
    FROM auth.users AS auth_user
    JOIN public.users AS profile ON profile.id = auth_user.id
    WHERE auth_user.id = p_auth_user_id
    FOR UPDATE OF auth_user, profile;
    IF source_is_anonymous IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'purchase_principal_signout_source_not_available'
            USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.user_id = p_auth_user_id
          AND deletion_job.status IN (
              'pending',
              'storage_pending',
              'auth_pending'
          )
    )
       OR EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.user_id = p_auth_user_id
              AND preparation.expires_at > rotation_prepared_at
       ) THEN
        RAISE EXCEPTION
            'purchase_principal_signout_account_deletion_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    UPDATE internal.purchase_principal_signout_rotations AS rotation
    SET status = 'expired',
        updated_at = rotation_prepared_at
    WHERE rotation.purchase_principal_id = principal.id
      AND rotation.status = 'prepared'
      AND rotation.expires_at <= rotation_prepared_at;

    SELECT rotation.*
    INTO existing
    FROM internal.purchase_principal_signout_rotations AS rotation
    WHERE rotation.id = p_rotation_id
    FOR UPDATE;
    IF FOUND THEN
        IF existing.purchase_principal_id <> principal.id
           OR existing.source_user_id <> p_auth_user_id
           OR existing.secret_hash <> p_secret_hash
           OR existing.binding_generation_before <>
                p_expected_binding_generation
           OR existing.binding_intent_generation_fence <>
                principal.latest_binding_intent_generation
           OR existing.protocol_version <> 3
           OR existing.status <> 'prepared' THEN
            RAISE EXCEPTION
                'purchase_principal_signout_rotation_terminal_conflict'
                USING ERRCODE = '23505';
        END IF;

        RETURN QUERY SELECT
            existing.id,
            principal.id,
            principal.revenuecat_app_user_id,
            binding.binding_generation,
            existing.status,
            existing.expires_at,
            TRUE;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.purchase_principal_signout_rotations AS rotation
        WHERE rotation.purchase_principal_id = principal.id
          AND rotation.status = 'prepared'
    ) THEN
        RAISE EXCEPTION
            'purchase_principal_signout_rotation_already_prepared'
            USING ERRCODE = '23505';
    END IF;

    INSERT INTO internal.purchase_principal_signout_rotations (
        id,
        purchase_principal_id,
        source_user_id,
        secret_hash,
        protocol_version,
        binding_generation_before,
        binding_intent_generation_fence,
        expires_at,
        created_at,
        updated_at
    )
    VALUES (
        p_rotation_id,
        principal.id,
        p_auth_user_id,
        p_secret_hash,
        3,
        binding.binding_generation,
        principal.latest_binding_intent_generation,
        rotation_prepared_at + INTERVAL '30 days',
        rotation_prepared_at,
        rotation_prepared_at
    )
    RETURNING
        internal.purchase_principal_signout_rotations.expires_at
    INTO rotation_expires_at;

    RETURN QUERY SELECT
        p_rotation_id,
        principal.id,
        principal.revenuecat_app_user_id,
        binding.binding_generation,
        'prepared'::TEXT,
        rotation_expires_at,
        FALSE;
END;
$function$;

COMMENT ON FUNCTION public.prepare_purchase_principal_signout_rotation(
    UUID, TEXT, UUID, TEXT, BIGINT, INTEGER
) IS
    'Service-only idempotent protocol-v3 preparation for the exact linked, non-anonymous source of one active capability-bound purchase principal.';

CREATE OR REPLACE FUNCTION public.claim_purchase_principal_signout_rotation(
    p_auth_user_id UUID,
    p_capability_hash TEXT,
    p_rotation_id UUID,
    p_secret_hash TEXT,
    p_client_protocol INTEGER
)
RETURNS TABLE (
    rotation_id UUID,
    purchase_principal_id UUID,
    revenuecat_app_user_id TEXT,
    binding_generation BIGINT,
    account_grants_allowed BOOLEAN,
    rotation_status TEXT,
    expires_at TIMESTAMPTZ,
    already_claimed BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
DECLARE
    rollout internal.purchase_identity_rollout_config%ROWTYPE;
    principal internal.purchase_principals%ROWTYPE;
    rotation internal.purchase_principal_signout_rotations%ROWTYPE;
    binding internal.purchase_principal_bindings%ROWTYPE;
    destination_created_at TIMESTAMPTZ;
    observed_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    locked_user_count INTEGER;
    rewritten_history_count INTEGER;
    resolved_principal_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_auth_user_id IS NULL
       OR p_capability_hash IS NULL
       OR p_capability_hash !~ '^[0-9a-f]{64}$'
       OR p_rotation_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$'
       OR p_client_protocol IS NULL
       OR p_client_protocol NOT BETWEEN 3 AND 1000 THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT config.*
    INTO STRICT rollout
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current';
    IF p_client_protocol < rollout.minimum_client_protocol THEN
        RAISE EXCEPTION 'purchase_principal_client_upgrade_required'
            USING ERRCODE = '22023';
    END IF;

    SELECT rotation_row.purchase_principal_id
    INTO resolved_principal_id
    FROM internal.purchase_principal_signout_rotations AS rotation_row
    JOIN internal.purchase_principals AS principal_row
      ON principal_row.id = rotation_row.purchase_principal_id
    WHERE rotation_row.id = p_rotation_id
      AND principal_row.capability_hash = p_capability_hash;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal-legacy-compatibility',
            0::BIGINT
        )
    );
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal:' || resolved_principal_id::TEXT,
            0::BIGINT
        )
    );

    SELECT principals.*
    INTO STRICT principal
    FROM internal.purchase_principals AS principals
    WHERE principals.id = resolved_principal_id
      AND principals.capability_hash = p_capability_hash
      AND principals.status = 'active'
    FOR UPDATE;

    SELECT rotation_row.*
    INTO STRICT rotation
    FROM internal.purchase_principal_signout_rotations AS rotation_row
    WHERE rotation_row.id = p_rotation_id
      AND rotation_row.purchase_principal_id = principal.id
    FOR UPDATE;

    IF rotation.secret_hash <> p_secret_hash
       OR rotation.protocol_version <> 3 THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT principal_binding.*
    INTO STRICT binding
    FROM internal.purchase_principal_bindings AS principal_binding
    WHERE principal_binding.purchase_principal_id = principal.id
    FOR UPDATE;

    IF rotation.status = 'completed' THEN
        IF rotation.destination_user_id <> p_auth_user_id
           OR binding.auth_user_id <> p_auth_user_id
           OR binding.binding_generation <>
                rotation.binding_generation_after THEN
            RAISE EXCEPTION
                'purchase_principal_signout_rotation_terminal_conflict'
                USING ERRCODE = '23505';
        END IF;

        RETURN QUERY SELECT
            rotation.id,
            principal.id,
            principal.revenuecat_app_user_id,
            binding.binding_generation,
            FALSE,
            rotation.status,
            rotation.expires_at,
            TRUE;
        RETURN;
    END IF;

    -- Expiry may be terminalized by the aggregate health pass before the
    -- destination retries. Preserve the same proof-bound terminal receipt
    -- regardless of which routine won that race.
    IF rotation.status = 'expired' THEN
        RETURN QUERY SELECT
            rotation.id,
            principal.id,
            principal.revenuecat_app_user_id,
            NULL::BIGINT,
            FALSE,
            rotation.status,
            rotation.expires_at,
            FALSE;
        RETURN;
    END IF;

    IF rotation.status = 'prepared'
       AND rotation.expires_at <= observed_at THEN
        UPDATE internal.purchase_principal_signout_rotations AS rotation_row
        SET status = 'expired',
            updated_at = observed_at
        WHERE rotation_row.id = rotation.id
        RETURNING rotation_row.* INTO rotation;

        RETURN QUERY SELECT
            rotation.id,
            principal.id,
            principal.revenuecat_app_user_id,
            NULL::BIGINT,
            FALSE,
            rotation.status,
            rotation.expires_at,
            FALSE;
        RETURN;
    END IF;

    IF rotation.status <> 'prepared' THEN
        RAISE EXCEPTION
            'purchase_principal_signout_rotation_terminal_conflict'
            USING ERRCODE = '23505';
    END IF;
    IF rotation.source_user_id = p_auth_user_id THEN
        RAISE EXCEPTION
            'purchase_principal_signout_anonymous_destination_required'
            USING ERRCODE = '42501';
    END IF;
    IF binding.auth_user_id <> rotation.source_user_id
       OR binding.binding_generation <>
            rotation.binding_generation_before THEN
        RAISE EXCEPTION 'purchase_principal_signout_binding_changed'
            USING ERRCODE = '40001';
    END IF;

    PERFORM profile.id
    FROM public.users AS profile
    JOIN auth.users AS auth_user ON auth_user.id = profile.id
    WHERE profile.id IN (rotation.source_user_id, p_auth_user_id)
    ORDER BY profile.id
    FOR UPDATE OF profile, auth_user;
    GET DIAGNOSTICS locked_user_count = ROW_COUNT;
    IF locked_user_count <> 2 THEN
        RAISE EXCEPTION 'purchase_principal_signout_source_not_available'
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id = rotation.source_user_id
          AND auth_user.is_anonymous IS FALSE
    ) THEN
        RAISE EXCEPTION 'purchase_principal_signout_source_not_available'
            USING ERRCODE = 'P0002';
    END IF;

    SELECT auth_user.created_at
    INTO destination_created_at
    FROM auth.users AS auth_user
    WHERE auth_user.id = p_auth_user_id
      AND auth_user.is_anonymous IS TRUE;
    IF destination_created_at IS NULL THEN
        RAISE EXCEPTION
            'purchase_principal_signout_anonymous_destination_required'
            USING ERRCODE = '42501';
    END IF;
    IF destination_created_at < rotation.created_at THEN
        RAISE EXCEPTION
            'purchase_principal_signout_fresh_anonymous_destination_required'
            USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.user_id IN (
            rotation.source_user_id,
            p_auth_user_id
        )
          AND deletion_job.status IN (
              'pending',
              'storage_pending',
              'auth_pending'
          )
    )
       OR EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.user_id IN (
                rotation.source_user_id,
                p_auth_user_id
            )
              AND preparation.expires_at > observed_at
       ) THEN
        RAISE EXCEPTION
            'purchase_principal_signout_account_deletion_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.ghost_profile_merge_handoffs AS handoff
        WHERE handoff.ghost_user_id = p_auth_user_id
          AND handoff.status IN ('prepared', 'merged')
    ) THEN
        RAISE EXCEPTION
            'purchase_principal_signout_ghost_merge_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'internal.purchase_principal_signout_rotation_id',
        rotation.id::TEXT,
        TRUE
    );

    UPDATE internal.purchase_principal_bindings AS principal_binding
    SET auth_user_id = p_auth_user_id,
        updated_at = observed_at
    WHERE principal_binding.purchase_principal_id = principal.id
    RETURNING principal_binding.* INTO binding;

    UPDATE internal.purchase_principal_binding_history AS history
    SET reason = 'stable_signout_rotation'
    WHERE history.purchase_principal_id = principal.id
      AND history.previous_auth_user_id = rotation.source_user_id
      AND history.next_auth_user_id = p_auth_user_id
      AND history.binding_generation = binding.binding_generation;
    GET DIAGNOSTICS rewritten_history_count = ROW_COUNT;
    IF rewritten_history_count <> 1 THEN
        RAISE EXCEPTION
            'purchase_principal_signout_binding_audit_missing'
            USING ERRCODE = '55000';
    END IF;

    UPDATE internal.purchase_principal_signout_rotations AS rotation_row
    SET destination_user_id = p_auth_user_id,
        binding_generation_after = binding.binding_generation,
        status = 'completed',
        completed_at = observed_at,
        updated_at = observed_at
    WHERE rotation_row.id = rotation.id
    RETURNING rotation_row.* INTO rotation;

    RETURN QUERY SELECT
        rotation.id,
        principal.id,
        principal.revenuecat_app_user_id,
        binding.binding_generation,
        FALSE,
        rotation.status,
        rotation.expires_at,
        FALSE;
END;
$function$;

COMMENT ON FUNCTION public.claim_purchase_principal_signout_rotation(
    UUID, TEXT, UUID, TEXT, INTEGER
) IS
    'Service-only protocol-v3 claim that atomically moves one active binding to the exact fresh anonymous JWT identity authorized by a prepared rotation.';

CREATE OR REPLACE FUNCTION public.cancel_purchase_principal_signout_rotation(
    p_auth_user_id UUID,
    p_capability_hash TEXT,
    p_rotation_id UUID,
    p_secret_hash TEXT,
    p_client_protocol INTEGER
)
RETURNS TABLE (
    rotation_id UUID,
    rotation_status TEXT,
    expires_at TIMESTAMPTZ,
    already_cancelled BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '10s'
AS $function$
DECLARE
    rollout internal.purchase_identity_rollout_config%ROWTYPE;
    principal internal.purchase_principals%ROWTYPE;
    rotation internal.purchase_principal_signout_rotations%ROWTYPE;
    binding internal.purchase_principal_bindings%ROWTYPE;
    source_is_anonymous BOOLEAN;
    observed_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
    resolved_principal_id UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF p_auth_user_id IS NULL
       OR p_capability_hash IS NULL
       OR p_capability_hash !~ '^[0-9a-f]{64}$'
       OR p_rotation_id IS NULL
       OR p_secret_hash IS NULL
       OR p_secret_hash !~ '^[0-9a-f]{64}$'
       OR p_client_protocol IS NULL
       OR p_client_protocol NOT BETWEEN 3 AND 1000 THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_invalid'
            USING ERRCODE = '22023';
    END IF;

    SELECT config.*
    INTO STRICT rollout
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current';
    IF p_client_protocol < rollout.minimum_client_protocol THEN
        RAISE EXCEPTION 'purchase_principal_client_upgrade_required'
            USING ERRCODE = '22023';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal-capability:' || p_capability_hash,
            0::BIGINT
        )
    );

    SELECT principals.id
    INTO resolved_principal_id
    FROM internal.purchase_principals AS principals
    WHERE principals.capability_hash = p_capability_hash
      AND principals.status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-principal:' || resolved_principal_id::TEXT,
            0::BIGINT
        )
    );

    SELECT principals.*
    INTO STRICT principal
    FROM internal.purchase_principals AS principals
    WHERE principals.id = resolved_principal_id
      AND principals.capability_hash = p_capability_hash
      AND principals.status = 'active'
    FOR UPDATE;

    SELECT rotation_row.*
    INTO rotation
    FROM internal.purchase_principal_signout_rotations AS rotation_row
    WHERE rotation_row.id = p_rotation_id
      AND rotation_row.purchase_principal_id = principal.id
    FOR UPDATE;
    IF NOT FOUND THEN
        IF EXISTS (
            SELECT 1
            FROM internal.purchase_principal_signout_rotations AS prepared
            WHERE prepared.purchase_principal_id = principal.id
              AND prepared.status = 'prepared'
              AND prepared.expires_at > observed_at
        ) THEN
            RAISE EXCEPTION
                'purchase_principal_signout_rotation_already_prepared'
                USING ERRCODE = '23505';
        END IF;

        SELECT principal_binding.*
        INTO STRICT binding
        FROM internal.purchase_principal_bindings AS principal_binding
        WHERE principal_binding.purchase_principal_id = principal.id
        FOR UPDATE;
        IF binding.auth_user_id <> p_auth_user_id THEN
            RAISE EXCEPTION 'purchase_principal_signout_binding_changed'
                USING ERRCODE = '40001';
        END IF;

        SELECT auth_user.is_anonymous
        INTO STRICT source_is_anonymous
        FROM auth.users AS auth_user
        JOIN public.users AS profile ON profile.id = auth_user.id
        WHERE auth_user.id = p_auth_user_id
        FOR UPDATE OF auth_user, profile;
        IF source_is_anonymous IS DISTINCT FROM FALSE THEN
            RAISE EXCEPTION
                'purchase_principal_signout_source_not_available'
                USING ERRCODE = '42501';
        END IF;

        INSERT INTO internal.purchase_principal_signout_rotations (
            id,
            purchase_principal_id,
            source_user_id,
            secret_hash,
            protocol_version,
            binding_generation_before,
            binding_intent_generation_fence,
            status,
            expires_at,
            cancelled_at,
            created_at,
            updated_at
        )
        VALUES (
            p_rotation_id,
            principal.id,
            p_auth_user_id,
            p_secret_hash,
            3,
            binding.binding_generation,
            principal.latest_binding_intent_generation,
            'cancelled',
            observed_at + INTERVAL '30 days',
            observed_at,
            observed_at,
            observed_at
        )
        RETURNING
            internal.purchase_principal_signout_rotations.*
        INTO rotation;

        RETURN QUERY SELECT
            rotation.id,
            rotation.status,
            rotation.expires_at,
            FALSE;
        RETURN;
    END IF;

    IF rotation.secret_hash <> p_secret_hash
       OR rotation.protocol_version <> 3
       OR rotation.source_user_id <> p_auth_user_id THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_invalid'
            USING ERRCODE = 'P0002';
    END IF;

    IF rotation.status = 'cancelled' THEN
        RETURN QUERY SELECT
            rotation.id,
            rotation.status,
            rotation.expires_at,
            TRUE;
        RETURN;
    END IF;
    IF rotation.status = 'expired' THEN
        RETURN QUERY SELECT
            rotation.id,
            rotation.status,
            rotation.expires_at,
            FALSE;
        RETURN;
    END IF;
    IF rotation.status = 'prepared'
       AND rotation.expires_at <= observed_at THEN
        UPDATE internal.purchase_principal_signout_rotations AS rotation_row
        SET status = 'expired',
            updated_at = observed_at
        WHERE rotation_row.id = rotation.id
        RETURNING rotation_row.* INTO rotation;

        RETURN QUERY SELECT
            rotation.id,
            rotation.status,
            rotation.expires_at,
            FALSE;
        RETURN;
    END IF;
    IF rotation.status <> 'prepared' THEN
        RAISE EXCEPTION
            'purchase_principal_signout_rotation_terminal_conflict'
            USING ERRCODE = '23505';
    END IF;

    SELECT principal_binding.*
    INTO STRICT binding
    FROM internal.purchase_principal_bindings AS principal_binding
    WHERE principal_binding.purchase_principal_id = principal.id
    FOR UPDATE;
    IF binding.auth_user_id <> p_auth_user_id
       OR binding.binding_generation <>
            rotation.binding_generation_before THEN
        RAISE EXCEPTION 'purchase_principal_signout_binding_changed'
            USING ERRCODE = '40001';
    END IF;

    SELECT auth_user.is_anonymous
    INTO STRICT source_is_anonymous
    FROM auth.users AS auth_user
    JOIN public.users AS profile ON profile.id = auth_user.id
    WHERE auth_user.id = p_auth_user_id
    FOR UPDATE OF auth_user, profile;
    IF source_is_anonymous IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'purchase_principal_signout_source_not_available'
            USING ERRCODE = '42501';
    END IF;

    UPDATE internal.purchase_principal_signout_rotations AS rotation_row
    SET status = 'cancelled',
        cancelled_at = observed_at,
        updated_at = observed_at
    WHERE rotation_row.id = rotation.id
    RETURNING rotation_row.* INTO rotation;

    RETURN QUERY SELECT
        rotation.id,
        rotation.status,
        rotation.expires_at,
        FALSE;
END;
$function$;

COMMENT ON FUNCTION public.cancel_purchase_principal_signout_rotation(
    UUID, TEXT, UUID, TEXT, INTEGER
) IS
    'Service-only protocol-v3 cancellation available only to the exact still-linked source before claim.';


REVOKE ALL ON FUNCTION
    public.prepare_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, BIGINT, INTEGER
    ),
    public.claim_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, INTEGER
    ),
    public.cancel_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, INTEGER
    )
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
    public.prepare_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, BIGINT, INTEGER
    )
TO service_role;

GRANT EXECUTE ON FUNCTION
    public.claim_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, INTEGER
    )
TO service_role;

GRANT EXECUTE ON FUNCTION
    public.cancel_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, INTEGER
    )
TO service_role;

RESET statement_timeout;
RESET lock_timeout;
