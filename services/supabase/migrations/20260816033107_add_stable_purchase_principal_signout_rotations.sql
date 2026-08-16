-- Replace the client-only stable sign-out rebind marker with a server-owned,
-- capability-bound, one-use rotation. A linked source prepares the rotation,
-- one fresh anonymous Auth identity may claim it, and ordinary purchase-
-- principal resolution remains blocked until the rotation is terminal.
--
-- The legacy provider-transfer handoff remains unchanged. These routines are
-- an additive protocol-v3 boundary for already-active stable principals.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

DO $migration$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM internal.purchase_identity_rollout_config AS config
        WHERE config.principal_mode = 'stable'
          AND config.minimum_client_protocol < 3
    ) THEN
        RAISE EXCEPTION
            'purchase_principal_signout_protocol_upgrade_required'
            USING ERRCODE = '55000';
    END IF;
END;
$migration$;

CREATE TABLE internal.purchase_principal_signout_rotations (
    id UUID PRIMARY KEY,
    purchase_principal_id UUID NOT NULL
        REFERENCES internal.purchase_principals(id) ON DELETE RESTRICT,
    source_user_id UUID,
    destination_user_id UUID,
    secret_hash TEXT NOT NULL UNIQUE,
    protocol_version INTEGER NOT NULL DEFAULT 3
        CHECK (protocol_version = 3),
    binding_generation_before BIGINT NOT NULL
        CHECK (binding_generation_before > 0),
    binding_intent_generation_fence BIGINT NOT NULL
        CHECK (
            binding_intent_generation_fence BETWEEN 0 AND 9007199254740991
        ),
    binding_generation_after BIGINT
        CHECK (binding_generation_after > 0),
    status TEXT NOT NULL DEFAULT 'prepared'
        CHECK (status IN ('prepared', 'completed', 'cancelled', 'expired')),
    expires_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    identities_scrubbed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT purchase_principal_signout_rotation_secret_check CHECK (
        secret_hash ~ '^[0-9a-f]{64}$'
    ),
    CONSTRAINT purchase_principal_signout_rotation_expiry_check CHECK (
        expires_at > created_at
    ),
    CONSTRAINT purchase_principal_signout_rotation_state_check CHECK (
        (
            status = 'prepared'
            AND source_user_id IS NOT NULL
            AND destination_user_id IS NULL
            AND binding_generation_after IS NULL
            AND completed_at IS NULL
            AND cancelled_at IS NULL
        )
        OR (
            status = 'completed'
            AND (
                destination_user_id IS NOT NULL
                OR identities_scrubbed_at IS NOT NULL
            )
            AND binding_generation_after IS NOT NULL
            AND completed_at IS NOT NULL
            AND cancelled_at IS NULL
        )
        OR (
            status = 'cancelled'
            AND destination_user_id IS NULL
            AND binding_generation_after IS NULL
            AND completed_at IS NULL
            AND cancelled_at IS NOT NULL
        )
        OR (
            status = 'expired'
            AND destination_user_id IS NULL
            AND binding_generation_after IS NULL
            AND completed_at IS NULL
            AND cancelled_at IS NULL
        )
    )
);

CREATE UNIQUE INDEX purchase_principal_signout_one_prepared_idx
    ON internal.purchase_principal_signout_rotations (
        purchase_principal_id
    )
    WHERE status = 'prepared';

CREATE INDEX purchase_principal_signout_rotation_intent_fence_idx
    ON internal.purchase_principal_signout_rotations (
        purchase_principal_id,
        binding_intent_generation_fence DESC
    );

CREATE INDEX purchase_principal_signout_rotation_expiry_idx
    ON internal.purchase_principal_signout_rotations (expires_at, id)
    WHERE status = 'prepared';

CREATE INDEX purchase_principal_signout_rotation_source_idx
    ON internal.purchase_principal_signout_rotations (
        source_user_id,
        created_at DESC
    )
    WHERE source_user_id IS NOT NULL;

CREATE INDEX purchase_principal_signout_rotation_destination_idx
    ON internal.purchase_principal_signout_rotations (
        destination_user_id,
        created_at DESC
    )
    WHERE destination_user_id IS NOT NULL;

ALTER TABLE internal.purchase_principal_signout_rotations
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.purchase_principal_signout_rotations
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.purchase_principal_signout_rotations IS
    'Private one-use protocol-v3 reservations authorizing one active stable purchase principal to move from its exact linked source to one fresh anonymous Auth identity. Only proof hashes are stored.';

CREATE OR REPLACE FUNCTION
internal.require_purchase_principal_signout_protocol_for_stable_rollout()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.principal_mode = 'stable'
       AND NEW.minimum_client_protocol < 3 THEN
        RAISE EXCEPTION
            'purchase_principal_signout_protocol_upgrade_required'
            USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.require_purchase_principal_signout_protocol_for_stable_rollout() IS
    'Prevents stable purchase-principal activation for clients that do not implement server-authorized sign-out rotation protocol 3.';

REVOKE ALL ON FUNCTION
internal.require_purchase_principal_signout_protocol_for_stable_rollout()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER require_purchase_principal_signout_protocol_for_stable_rollout
BEFORE INSERT OR UPDATE OF principal_mode, minimum_client_protocol
ON internal.purchase_identity_rollout_config
FOR EACH ROW
EXECUTE FUNCTION
    internal.require_purchase_principal_signout_protocol_for_stable_rollout();

CREATE OR REPLACE FUNCTION
internal.guard_purchase_principal_intent_during_signout_rotation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.latest_binding_intent_generation IS NOT DISTINCT FROM
            OLD.latest_binding_intent_generation THEN
        RETURN NEW;
    END IF;

    UPDATE internal.purchase_principal_signout_rotations AS rotation
    SET status = 'expired',
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE rotation.purchase_principal_id = NEW.id
      AND rotation.status = 'prepared'
      AND rotation.expires_at <= pg_catalog.CLOCK_TIMESTAMP();

    IF EXISTS (
        SELECT 1
        FROM internal.purchase_principal_signout_rotations AS rotation
        WHERE rotation.purchase_principal_id = NEW.id
          AND rotation.status = 'prepared'
    ) THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_required'
            USING ERRCODE = '55P03';
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.guard_purchase_principal_intent_during_signout_rotation() IS
    'Rejects ordinary resolver intents while a live one-use stable sign-out rotation owns the principal transition.';

REVOKE ALL ON FUNCTION
internal.guard_purchase_principal_intent_during_signout_rotation()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER guard_purchase_principal_intent_during_signout_rotation
BEFORE UPDATE OF latest_binding_intent_generation
ON internal.purchase_principals
FOR EACH ROW
EXECUTE FUNCTION
    internal.guard_purchase_principal_intent_during_signout_rotation();

CREATE OR REPLACE FUNCTION
internal.guard_purchase_principal_binding_during_signout_rotation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    prepared_rotation_id UUID;
    latest_binding_intent_generation BIGINT;
BEGIN
    UPDATE internal.purchase_principal_signout_rotations AS rotation
    SET status = 'expired',
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE rotation.purchase_principal_id = NEW.purchase_principal_id
      AND rotation.status = 'prepared'
      AND rotation.expires_at <= pg_catalog.CLOCK_TIMESTAMP();

    SELECT rotation.id
    INTO prepared_rotation_id
    FROM internal.purchase_principal_signout_rotations AS rotation
    WHERE rotation.purchase_principal_id = NEW.purchase_principal_id
      AND rotation.status = 'prepared';

    IF prepared_rotation_id IS NOT NULL THEN
        IF pg_catalog.CURRENT_SETTING(
                'internal.purchase_principal_signout_rotation_id',
                TRUE
           ) IS DISTINCT FROM prepared_rotation_id::TEXT THEN
            RAISE EXCEPTION 'purchase_principal_signout_rotation_required'
                USING ERRCODE = '55P03';
        END IF;
        RETURN NEW;
    END IF;

    SELECT principal.latest_binding_intent_generation
    INTO STRICT latest_binding_intent_generation
    FROM internal.purchase_principals AS principal
    WHERE principal.id = NEW.purchase_principal_id;

    -- A resolver is intentionally two-phase. Preparation snapshots every
    -- begin token already issued for this principal so a delayed completion
    -- cannot wait out claim, cancellation, or expiry and then overwrite the
    -- exact rotation destination. A later begin must first advance the
    -- principal generation above every terminal fence.
    IF EXISTS (
        SELECT 1
        FROM internal.purchase_principal_signout_rotations AS rotation
        WHERE rotation.purchase_principal_id = NEW.purchase_principal_id
          AND rotation.binding_intent_generation_fence >=
                latest_binding_intent_generation
    ) THEN
        RAISE EXCEPTION 'purchase_principal_binding_intent_stale'
            USING ERRCODE = '40001';
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.guard_purchase_principal_binding_during_signout_rotation() IS
    'Allows a prepared principal binding to move only inside its exact server-authorized claim transaction and permanently rejects resolver tokens issued before preparation.';

REVOKE ALL ON FUNCTION
internal.guard_purchase_principal_binding_during_signout_rotation()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER guard_purchase_principal_binding_during_signout_rotation
BEFORE INSERT OR UPDATE ON internal.purchase_principal_bindings
FOR EACH ROW
EXECUTE FUNCTION
    internal.guard_purchase_principal_binding_during_signout_rotation();

CREATE OR REPLACE FUNCTION
internal.scrub_purchase_principal_signout_rotation_auth_references()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    UPDATE internal.purchase_principal_signout_rotations AS rotation
    SET status = 'expired',
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE rotation.status = 'prepared'
      AND rotation.expires_at <= pg_catalog.CLOCK_TIMESTAMP()
      AND OLD.id IN (
          rotation.source_user_id,
          rotation.destination_user_id
      );

    IF EXISTS (
        SELECT 1
        FROM internal.purchase_principal_signout_rotations AS rotation
        WHERE rotation.status = 'prepared'
          AND OLD.id IN (
              rotation.source_user_id,
              rotation.destination_user_id
          )
    ) THEN
        RAISE EXCEPTION 'purchase_principal_signout_rotation_required'
            USING ERRCODE = '55P03';
    END IF;

    UPDATE internal.purchase_principal_signout_rotations AS rotation
    SET source_user_id = CASE
            WHEN rotation.source_user_id = OLD.id THEN NULL
            ELSE rotation.source_user_id
        END,
        destination_user_id = CASE
            WHEN rotation.destination_user_id = OLD.id THEN NULL
            ELSE rotation.destination_user_id
        END,
        identities_scrubbed_at = pg_catalog.CLOCK_TIMESTAMP(),
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE rotation.status <> 'prepared'
      AND (
          rotation.source_user_id = OLD.id
          OR rotation.destination_user_id = OLD.id
      );

    RETURN OLD;
END;
$function$;

COMMENT ON FUNCTION
internal.scrub_purchase_principal_signout_rotation_auth_references() IS
    'Blocks direct deletion during a prepared rotation and removes terminal Auth references when a profile is later erased.';

REVOKE ALL ON FUNCTION
internal.scrub_purchase_principal_signout_rotation_auth_references()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER scrub_purchase_principal_signout_rotation_auth_references
BEFORE DELETE ON public.users
FOR EACH ROW
EXECUTE FUNCTION
    internal.scrub_purchase_principal_signout_rotation_auth_references();

CREATE OR REPLACE FUNCTION
internal.reject_account_deletion_during_signout_handoff()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.user_id IS NOT NULL
       AND NEW.status IN ('pending', 'storage_pending', 'auth_pending') THEN
        PERFORM auth_user.id
        FROM auth.users AS auth_user
        WHERE auth_user.id = NEW.user_id
        FOR UPDATE;

        IF EXISTS (
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

        IF EXISTS (
            SELECT 1
            FROM internal.purchase_principal_signout_rotations AS rotation
            WHERE rotation.status = 'prepared'
              AND rotation.source_user_id = NEW.user_id
              AND rotation.expires_at > pg_catalog.CLOCK_TIMESTAMP()
        ) THEN
            RAISE EXCEPTION
                'purchase_principal_signout_account_deletion_in_progress'
                USING ERRCODE = '55P03';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION internal.reject_account_deletion_during_signout_handoff()
IS 'Prevents durable account deletion from racing either a bound legacy sign-out handoff or a prepared stable purchase-principal rotation.';

REVOKE ALL ON FUNCTION
internal.reject_account_deletion_during_signout_handoff()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION
internal.reject_account_deletion_preparation_during_purchase_signout()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    PERFORM auth_user.id
    FROM auth.users AS auth_user
    WHERE auth_user.id = NEW.user_id
    FOR UPDATE;

    IF EXISTS (
        SELECT 1
        FROM internal.purchase_principal_signout_rotations AS rotation
        WHERE rotation.status = 'prepared'
          AND rotation.source_user_id = NEW.user_id
          AND rotation.expires_at > pg_catalog.CLOCK_TIMESTAMP()
    ) THEN
        RAISE EXCEPTION
            'purchase_principal_signout_account_deletion_in_progress'
            USING ERRCODE = '55P03';
    END IF;
    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION
internal.reject_account_deletion_preparation_during_purchase_signout() IS
    'Serializes non-destructive account-deletion preparation against a live stable purchase-principal sign-out rotation.';

REVOKE ALL ON FUNCTION
internal.reject_account_deletion_preparation_during_purchase_signout()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER reject_account_deletion_preparation_during_purchase_signout
BEFORE INSERT OR UPDATE OF user_id, expires_at
ON internal.account_deletion_recovery_preparations
FOR EACH ROW
EXECUTE FUNCTION
    internal.reject_account_deletion_preparation_during_purchase_signout();

CREATE OR REPLACE FUNCTION
internal.reject_ghost_merge_during_signout_handoff()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.status IN ('prepared', 'merged') THEN
        PERFORM auth_user.id
        FROM auth.users AS auth_user
        WHERE auth_user.id = NEW.ghost_user_id
        FOR UPDATE;

        IF EXISTS (
            SELECT 1
            FROM internal.signout_purchase_handoffs AS handoff
            WHERE handoff.destination_user_id = NEW.ghost_user_id
              AND handoff.status = 'bound'
        ) THEN
            RAISE EXCEPTION 'signout_purchase_handoff_pending'
                USING ERRCODE = '55P03';
        END IF;

        IF EXISTS (
            SELECT 1
            FROM internal.purchase_principal_signout_rotations AS rotation
            WHERE rotation.destination_user_id = NEW.ghost_user_id
              AND rotation.status = 'prepared'
              AND rotation.expires_at > pg_catalog.CLOCK_TIMESTAMP()
        ) THEN
            RAISE EXCEPTION 'purchase_principal_signout_rotation_required'
                USING ERRCODE = '55P03';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION internal.reject_ghost_merge_during_signout_handoff() IS
    'Serializes Ghost merge preparation against legacy and stable sign-out purchase transitions.';

REVOKE ALL ON FUNCTION internal.reject_ghost_merge_during_signout_handoff()
    FROM PUBLIC, anon, authenticated, service_role;

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
    prepared_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
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
              AND preparation.expires_at > prepared_at
       ) THEN
        RAISE EXCEPTION
            'purchase_principal_signout_account_deletion_in_progress'
            USING ERRCODE = '55P03';
    END IF;

    UPDATE internal.purchase_principal_signout_rotations AS rotation
    SET status = 'expired',
        updated_at = prepared_at
    WHERE rotation.purchase_principal_id = principal.id
      AND rotation.status = 'prepared'
      AND rotation.expires_at <= prepared_at;

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
        prepared_at + INTERVAL '30 days',
        prepared_at,
        prepared_at
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

CREATE OR REPLACE FUNCTION
public.get_purchase_principal_signout_rotation_health()
RETURNS TABLE (
    generated_at TIMESTAMPTZ,
    prepared_count BIGINT,
    expired_prepared_count BIGINT,
    oldest_prepared_at TIMESTAMPTZ,
    oldest_prepared_age_seconds BIGINT,
    completed_last_24h BIGINT,
    cancelled_last_24h BIGINT
)
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $function$
DECLARE
    observed_at TIMESTAMPTZ := pg_catalog.CLOCK_TIMESTAMP();
BEGIN
    PERFORM internal.require_service_role();

    RETURN QUERY
    WITH expired_rotations AS (
        UPDATE internal.purchase_principal_signout_rotations AS rotation
        SET status = 'expired',
            updated_at = observed_at
        WHERE rotation.status = 'prepared'
          AND rotation.expires_at <= observed_at
        RETURNING rotation.id
    ),
    health AS (
        SELECT
            pg_catalog.COUNT(*) FILTER (
                WHERE rotation.status = 'prepared'
                  AND rotation.expires_at > observed_at
            ) AS prepared_count,
            pg_catalog.MIN(rotation.created_at) FILTER (
                WHERE rotation.status = 'prepared'
                  AND rotation.expires_at > observed_at
            ) AS oldest_prepared_at,
            pg_catalog.COUNT(*) FILTER (
                WHERE rotation.status = 'completed'
                  AND rotation.completed_at >=
                        observed_at - INTERVAL '24 hours'
            ) AS completed_last_24h,
            pg_catalog.COUNT(*) FILTER (
                WHERE rotation.status = 'cancelled'
                  AND rotation.cancelled_at >=
                        observed_at - INTERVAL '24 hours'
            ) AS cancelled_last_24h
        FROM internal.purchase_principal_signout_rotations AS rotation
    )
    SELECT
        observed_at,
        health.prepared_count,
        (
            SELECT pg_catalog.COUNT(*)
            FROM expired_rotations
        ),
        health.oldest_prepared_at,
        CASE
            WHEN health.oldest_prepared_at IS NULL THEN NULL::BIGINT
            ELSE GREATEST(
                0::BIGINT,
                pg_catalog.FLOOR(
                    EXTRACT(
                        EPOCH FROM observed_at - health.oldest_prepared_at
                    )
                )::BIGINT
            )
        END,
        health.completed_last_24h,
        health.cancelled_last_24h
    FROM health;
END;
$function$;

COMMENT ON FUNCTION
public.get_purchase_principal_signout_rotation_health() IS
    'Service-only aggregate health for protocol-v3 stable sign-out rotations; terminalizes newly expired preparations, reports that transition count once, and returns no identities, capabilities, or proofs.';

REVOKE ALL ON FUNCTION
    public.prepare_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, BIGINT, INTEGER
    ),
    public.claim_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, INTEGER
    ),
    public.cancel_purchase_principal_signout_rotation(
        UUID, TEXT, UUID, TEXT, INTEGER
    ),
    public.get_purchase_principal_signout_rotation_health()
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

GRANT EXECUTE ON FUNCTION
    public.get_purchase_principal_signout_rotation_health()
TO service_role;

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES
    (
        'service_role',
        'public.prepare_purchase_principal_signout_rotation(uuid,text,uuid,text,bigint,integer)',
        'Prepares one capability-bound protocol-v3 stable sign-out rotation for the exact linked source.'
    ),
    (
        'service_role',
        'public.claim_purchase_principal_signout_rotation(uuid,text,uuid,text,integer)',
        'Claims one prepared stable sign-out rotation for the exact fresh anonymous JWT destination.'
    ),
    (
        'service_role',
        'public.cancel_purchase_principal_signout_rotation(uuid,text,uuid,text,integer)',
        'Cancels one prepared stable sign-out rotation from its exact still-linked source.'
    ),
    (
        'service_role',
        'public.get_purchase_principal_signout_rotation_health()',
        'Reads identity-free aggregate health for stable sign-out rotations.'
    )
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

RESET statement_timeout;
RESET lock_timeout;
