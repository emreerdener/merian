-- Account-owned beta, promotion, and support access is issued through the
-- private Supabase ledger. Record one immutable, identity-free batch receipt
-- in the same transaction as its grants so an operator can safely replay a
-- lost response without duplicating or silently changing the approved cohort.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

CREATE TABLE internal.account_access_grant_operations (
    id UUID PRIMARY KEY,
    schema_version INTEGER NOT NULL CHECK (schema_version = 1),
    target_environment TEXT NOT NULL CHECK (
        target_environment ~ '^[a-z][a-z0-9_-]{1,31}$'
    ),
    project_ref TEXT NOT NULL CHECK (
        project_ref ~ '^[a-z]{20}$'
    ),
    database_system_identifier TEXT NOT NULL CHECK (
        database_system_identifier ~ '^[0-9]{1,20}$'
    ),
    source_sha TEXT NOT NULL CHECK (source_sha ~ '^[0-9a-f]{40}$'),
    approval_sha256 TEXT NOT NULL CHECK (
        approval_sha256 ~ '^[0-9a-f]{64}$'
    ),
    plan_sha256 TEXT NOT NULL UNIQUE CHECK (
        plan_sha256 ~ '^[0-9a-f]{64}$'
    ),
    candidate_set_sha256 TEXT NOT NULL CHECK (
        candidate_set_sha256 ~ '^[0-9a-f]{64}$'
    ),
    candidate_count INTEGER NOT NULL CHECK (
        candidate_count BETWEEN 1 AND 500
    ),
    grant_kind TEXT NOT NULL CHECK (
        grant_kind IN ('beta', 'promotion', 'support')
    ),
    expires_at TIMESTAMPTZ NOT NULL,
    principal_mode TEXT NOT NULL CHECK (
        principal_mode IN ('legacy', 'stable')
    ),
    account_grant_mode TEXT NOT NULL CHECK (
        account_grant_mode IN ('dual_read', 'authoritative')
    ),
    applied_at TIMESTAMPTZ NOT NULL DEFAULT pg_catalog.CLOCK_TIMESTAMP()
);

ALTER TABLE internal.account_access_grant_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.account_access_grant_operations FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE internal.account_access_grant_operations
    FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE internal.account_access_grant_operations IS
    'Database-owner-only, immutable receipts for approved account-access grant cohorts. Rows contain aggregate digests and counts, never cohort identities or source artifacts.';

COMMENT ON COLUMN internal.account_access_grant_operations.plan_sha256 IS
    'SHA-256 of the canonical dry-run plan approved before the atomic grant transaction.';

COMMENT ON COLUMN internal.account_access_grant_operations.candidate_set_sha256 IS
    'SHA-256 of the sorted canonical account UUID set. The underlying identities remain only in the private grant ledger.';

CREATE OR REPLACE FUNCTION internal.reject_account_access_grant_operation_mutation()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    RAISE EXCEPTION 'account_access_grant_operation_immutable'
        USING ERRCODE = '55000';
END;
$function$;

REVOKE ALL ON FUNCTION
    internal.reject_account_access_grant_operation_mutation()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER reject_account_access_grant_operation_mutation
BEFORE UPDATE OR DELETE ON internal.account_access_grant_operations
FOR EACH ROW
EXECUTE FUNCTION internal.reject_account_access_grant_operation_mutation();

RESET statement_timeout;
RESET lock_timeout;
