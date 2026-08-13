-- Add an owner-only, versioned control plane for stable purchase-principal
-- activation and rollback. Deploying this migration does not change either
-- rollout mode. A separately authorized operator must present the exact
-- reviewed SHA, approved dry-run digest, evidence digest, and approval digest.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE TABLE internal.purchase_identity_rollout_operations (
    id UUID PRIMARY KEY,
    operation_version INTEGER NOT NULL CHECK (operation_version = 1),
    target_environment TEXT NOT NULL CHECK (
        target_environment ~ '^[a-z][a-z0-9_-]{1,31}$'
    ),
    target_project_ref TEXT NOT NULL CHECK (
        target_project_ref ~ '^[a-z]{20}$'
    ),
    database_system_identifier TEXT NOT NULL CHECK (
        database_system_identifier ~ '^[0-9]{1,20}$'
    ),
    action TEXT NOT NULL CHECK (
        action IN (
            'enable_stable',
            'rollback_stable',
            'enable_authoritative',
            'rollback_authoritative'
        )
    ),
    source_sha TEXT NOT NULL CHECK (source_sha ~ '^[0-9a-f]{40}$'),
    evidence_sha256 TEXT NOT NULL CHECK (
        evidence_sha256 ~ '^[0-9a-f]{64}$'
    ),
    approval_sha256 TEXT NOT NULL CHECK (
        approval_sha256 ~ '^[0-9a-f]{64}$'
    ),
    approved_plan_sha256 TEXT NOT NULL UNIQUE CHECK (
        approved_plan_sha256 ~ '^[0-9a-f]{64}$'
    ),
    principal_mode_before TEXT NOT NULL CHECK (
        principal_mode_before IN ('legacy', 'stable')
    ),
    account_grant_mode_before TEXT NOT NULL CHECK (
        account_grant_mode_before IN ('dual_read', 'authoritative')
    ),
    minimum_client_protocol_before INTEGER NOT NULL CHECK (
        minimum_client_protocol_before BETWEEN 1 AND 1000
    ),
    principal_mode_after TEXT NOT NULL CHECK (
        principal_mode_after IN ('legacy', 'stable')
    ),
    account_grant_mode_after TEXT NOT NULL CHECK (
        account_grant_mode_after IN ('dual_read', 'authoritative')
    ),
    minimum_client_protocol_after INTEGER NOT NULL CHECK (
        minimum_client_protocol_after BETWEEN 1 AND 1000
    ),
    rollback_of UUID UNIQUE REFERENCES internal.purchase_identity_rollout_operations(id),
    applied_by TEXT NOT NULL CHECK (
        applied_by ~ '^[a-z_][a-z0-9_-]{0,62}$'
    ),
    applied_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP(),
    CONSTRAINT purchase_identity_rollout_target_binding CHECK (
        target_environment = 'production'
        AND target_project_ref = 'qlarqavoqhkuwzmevrmf'
    ),
    CONSTRAINT purchase_identity_rollout_rollback_shape CHECK (
        (action IN ('enable_stable', 'enable_authoritative')
            AND rollback_of IS NULL)
        OR
        (action IN ('rollback_stable', 'rollback_authoritative')
            AND rollback_of IS NOT NULL)
    ),
    CONSTRAINT purchase_identity_rollout_one_axis CHECK (
        (
            principal_mode_before IS DISTINCT FROM principal_mode_after
            AND account_grant_mode_before = account_grant_mode_after
        )
        OR
        (
            principal_mode_before = principal_mode_after
            AND account_grant_mode_before IS DISTINCT FROM account_grant_mode_after
        )
    )
);

ALTER TABLE internal.purchase_identity_rollout_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE internal.purchase_identity_rollout_operations
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.purchase_identity_rollout_operations IS
    'Owner-only, identity-free exact-SHA ledger for separately authorized purchase-principal rollout and rollback operations.';

CREATE OR REPLACE FUNCTION internal.apply_purchase_identity_rollout_operation(
    p_operation_id UUID,
    p_operation_version INTEGER,
    p_target_environment TEXT,
    p_target_project_ref TEXT,
    p_database_system_identifier TEXT,
    p_action TEXT,
    p_source_sha TEXT,
    p_evidence_sha256 TEXT,
    p_approval_sha256 TEXT,
    p_approved_plan_sha256 TEXT,
    p_expected_principal_mode TEXT,
    p_expected_account_grant_mode TEXT,
    p_expected_minimum_client_protocol INTEGER,
    p_target_minimum_client_protocol INTEGER,
    p_rollback_of UUID DEFAULT NULL
)
RETURNS TABLE (
    operation_id UUID,
    applied_action TEXT,
    principal_mode TEXT,
    account_grant_mode TEXT,
    minimum_client_protocol INTEGER,
    already_applied BOOLEAN
)
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
SET statement_timeout = '30s'
AS $function$
DECLARE
    rollout internal.purchase_identity_rollout_config%ROWTYPE;
    existing internal.purchase_identity_rollout_operations%ROWTYPE;
    rollback_source internal.purchase_identity_rollout_operations%ROWTYPE;
    next_principal_mode TEXT;
    next_account_grant_mode TEXT;
    next_minimum_client_protocol INTEGER;
    expected_rollback_action TEXT;
    current_database_system_identifier TEXT;
BEGIN
    IF SESSION_USER <> 'postgres' OR CURRENT_USER <> 'postgres' THEN
        RAISE EXCEPTION 'purchase_identity_rollout_owner_required'
            USING ERRCODE = '42501';
    END IF;

    IF p_operation_id IS NULL
       OR p_operation_version IS NULL
       OR p_operation_version <> 1
       OR p_target_environment IS NULL
       OR p_target_environment !~ '^[a-z][a-z0-9_-]{1,31}$'
       OR p_target_environment <> 'production'
       OR p_target_project_ref IS NULL
       OR p_target_project_ref <> 'qlarqavoqhkuwzmevrmf'
       OR p_database_system_identifier IS NULL
       OR p_database_system_identifier !~ '^[0-9]{1,20}$'
       OR p_action IS NULL
       OR p_action NOT IN (
            'enable_stable',
            'rollback_stable',
            'enable_authoritative',
            'rollback_authoritative'
       )
       OR p_source_sha IS NULL
       OR p_source_sha !~ '^[0-9a-f]{40}$'
       OR p_evidence_sha256 IS NULL
       OR p_evidence_sha256 !~ '^[0-9a-f]{64}$'
       OR p_approval_sha256 IS NULL
       OR p_approval_sha256 !~ '^[0-9a-f]{64}$'
       OR p_approved_plan_sha256 IS NULL
       OR p_approved_plan_sha256 !~ '^[0-9a-f]{64}$'
       OR p_expected_principal_mode IS NULL
       OR p_expected_principal_mode NOT IN ('legacy', 'stable')
       OR p_expected_account_grant_mode IS NULL
       OR p_expected_account_grant_mode NOT IN (
            'dual_read',
            'authoritative'
       )
       OR p_expected_minimum_client_protocol IS NULL
       OR p_expected_minimum_client_protocol NOT BETWEEN 1 AND 1000
       OR p_target_minimum_client_protocol IS NULL
       OR p_target_minimum_client_protocol NOT BETWEEN 1 AND 1000 THEN
        RAISE EXCEPTION 'purchase_identity_rollout_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    SELECT control.system_identifier::TEXT
    INTO STRICT current_database_system_identifier
    FROM pg_catalog.PG_CONTROL_SYSTEM() AS control;
    IF current_database_system_identifier <>
            p_database_system_identifier THEN
        RAISE EXCEPTION 'purchase_identity_rollout_database_target_mismatch'
            USING ERRCODE = '55000';
    END IF;

    -- Serialize before replay lookup. Two simultaneous invocations of the same
    -- approved operation must make the second one observe the first receipt,
    -- not misreport a state-change failure after the first changes config.
    PERFORM pg_catalog.PG_ADVISORY_XACT_LOCK(
        pg_catalog.HASHTEXTEXTENDED(
            'purchase-identity-rollout-control',
            0::BIGINT
        )
    );

    SELECT operation.*
    INTO existing
    FROM internal.purchase_identity_rollout_operations AS operation
    WHERE operation.id = p_operation_id;

    IF FOUND THEN
        IF existing.operation_version <> p_operation_version
           OR existing.target_environment <> p_target_environment
           OR existing.target_project_ref <> p_target_project_ref
           OR existing.database_system_identifier <>
                p_database_system_identifier
           OR existing.action <> p_action
           OR existing.source_sha <> p_source_sha
           OR existing.evidence_sha256 <> p_evidence_sha256
           OR existing.approval_sha256 <> p_approval_sha256
           OR existing.approved_plan_sha256 <> p_approved_plan_sha256
           OR existing.principal_mode_before <>
                p_expected_principal_mode
           OR existing.account_grant_mode_before <>
                p_expected_account_grant_mode
           OR existing.minimum_client_protocol_before <>
                p_expected_minimum_client_protocol
           OR existing.minimum_client_protocol_after <>
                p_target_minimum_client_protocol
           OR existing.rollback_of IS DISTINCT FROM p_rollback_of THEN
            RAISE EXCEPTION 'purchase_identity_rollout_replay_mismatch'
                USING ERRCODE = '22023';
        END IF;

        RETURN QUERY SELECT
            existing.id,
            existing.action,
            existing.principal_mode_after,
            existing.account_grant_mode_after,
            existing.minimum_client_protocol_after,
            TRUE;
        RETURN;
    END IF;

    SELECT config.*
    INTO STRICT rollout
    FROM internal.purchase_identity_rollout_config AS config
    WHERE config.config_key = 'current'
    FOR UPDATE;

    IF rollout.principal_mode <> p_expected_principal_mode
       OR rollout.account_grant_mode <> p_expected_account_grant_mode
       OR rollout.minimum_client_protocol <>
            p_expected_minimum_client_protocol THEN
        RAISE EXCEPTION 'purchase_identity_rollout_state_changed'
            USING ERRCODE = '40001';
    END IF;

    next_principal_mode := rollout.principal_mode;
    next_account_grant_mode := rollout.account_grant_mode;
    next_minimum_client_protocol := rollout.minimum_client_protocol;

    CASE p_action
    WHEN 'enable_stable' THEN
        IF rollout.principal_mode <> 'legacy'
           OR rollout.account_grant_mode <> 'dual_read'
           OR p_target_minimum_client_protocol < 2
           OR p_target_minimum_client_protocol <
                rollout.minimum_client_protocol THEN
            RAISE EXCEPTION 'purchase_identity_rollout_transition_invalid'
                USING ERRCODE = '55000';
        END IF;
        next_principal_mode := 'stable';
        next_minimum_client_protocol := p_target_minimum_client_protocol;
    WHEN 'rollback_stable' THEN
        IF rollout.principal_mode <> 'stable'
           OR rollout.account_grant_mode <> 'dual_read'
           OR p_target_minimum_client_protocol <>
                rollout.minimum_client_protocol THEN
            RAISE EXCEPTION 'purchase_identity_rollout_transition_invalid'
                USING ERRCODE = '55000';
        END IF;
        next_principal_mode := 'legacy';
        expected_rollback_action := 'enable_stable';
    WHEN 'enable_authoritative' THEN
        IF rollout.principal_mode <> 'stable'
           OR rollout.account_grant_mode <> 'dual_read'
           OR p_target_minimum_client_protocol <>
                rollout.minimum_client_protocol THEN
            RAISE EXCEPTION 'purchase_identity_rollout_transition_invalid'
                USING ERRCODE = '55000';
        END IF;
        next_account_grant_mode := 'authoritative';
    WHEN 'rollback_authoritative' THEN
        IF rollout.principal_mode <> 'stable'
           OR rollout.account_grant_mode <> 'authoritative'
           OR p_target_minimum_client_protocol <>
                rollout.minimum_client_protocol THEN
            RAISE EXCEPTION 'purchase_identity_rollout_transition_invalid'
                USING ERRCODE = '55000';
        END IF;
        next_account_grant_mode := 'dual_read';
        expected_rollback_action := 'enable_authoritative';
    END CASE;

    IF expected_rollback_action IS NOT NULL THEN
        IF p_rollback_of IS NULL THEN
            RAISE EXCEPTION 'purchase_identity_rollout_rollback_reference_required'
                USING ERRCODE = '22023';
        END IF;
        SELECT operation.*
        INTO rollback_source
        FROM internal.purchase_identity_rollout_operations AS operation
        WHERE operation.id = p_rollback_of
        FOR SHARE;
        IF NOT FOUND
           OR rollback_source.action <> expected_rollback_action
           OR rollback_source.target_environment <> p_target_environment
           OR rollback_source.target_project_ref <> p_target_project_ref
           OR rollback_source.database_system_identifier <>
                p_database_system_identifier
           OR rollback_source.principal_mode_after <>
                rollout.principal_mode
           OR rollback_source.account_grant_mode_after <>
                rollout.account_grant_mode
           OR rollback_source.minimum_client_protocol_after <>
                rollout.minimum_client_protocol THEN
            RAISE EXCEPTION 'purchase_identity_rollout_rollback_reference_invalid'
                USING ERRCODE = '22023';
        END IF;
    ELSIF p_rollback_of IS NOT NULL THEN
        RAISE EXCEPTION 'purchase_identity_rollout_rollback_reference_invalid'
            USING ERRCODE = '22023';
    END IF;

    UPDATE internal.purchase_identity_rollout_config AS config
    SET principal_mode = next_principal_mode,
        account_grant_mode = next_account_grant_mode,
        minimum_client_protocol = next_minimum_client_protocol,
        updated_at = pg_catalog.CLOCK_TIMESTAMP()
    WHERE config.config_key = 'current'
      AND config.principal_mode = rollout.principal_mode
      AND config.account_grant_mode = rollout.account_grant_mode
      AND config.minimum_client_protocol =
            rollout.minimum_client_protocol;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'purchase_identity_rollout_state_changed'
            USING ERRCODE = '40001';
    END IF;

    INSERT INTO internal.purchase_identity_rollout_operations (
        id,
        operation_version,
        target_environment,
        target_project_ref,
        database_system_identifier,
        action,
        source_sha,
        evidence_sha256,
        approval_sha256,
        approved_plan_sha256,
        principal_mode_before,
        account_grant_mode_before,
        minimum_client_protocol_before,
        principal_mode_after,
        account_grant_mode_after,
        minimum_client_protocol_after,
        rollback_of,
        applied_by
    ) VALUES (
        p_operation_id,
        p_operation_version,
        p_target_environment,
        p_target_project_ref,
        p_database_system_identifier,
        p_action,
        p_source_sha,
        p_evidence_sha256,
        p_approval_sha256,
        p_approved_plan_sha256,
        rollout.principal_mode,
        rollout.account_grant_mode,
        rollout.minimum_client_protocol,
        next_principal_mode,
        next_account_grant_mode,
        next_minimum_client_protocol,
        p_rollback_of,
        SESSION_USER
    );

    RETURN QUERY SELECT
        p_operation_id,
        p_action,
        next_principal_mode,
        next_account_grant_mode,
        next_minimum_client_protocol,
        FALSE;
END;
$function$;

REVOKE ALL ON FUNCTION internal.apply_purchase_identity_rollout_operation(
    UUID,
    INTEGER,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    INTEGER,
    INTEGER,
    UUID
) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION internal.apply_purchase_identity_rollout_operation(
    UUID,
    INTEGER,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    INTEGER,
    INTEGER,
    UUID
) IS
    'Database-owner-only atomic purchase identity rollout operation. Changes exactly one rollout axis and records only exact-SHA/digest evidence; deploys never call it.';

RESET statement_timeout;
RESET lock_timeout;
