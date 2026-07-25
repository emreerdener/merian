\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $$
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.account_deletion_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.reject_account_deletion_profile_recreation()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'API roles unexpectedly have direct account-deletion internals access';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.claim_account_deletion_jobs(integer,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.complete_account_deletion_cleanup(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'A public client role can execute an account-deletion worker RPC';
    END IF;

    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_account_deletion(uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.claim_account_deletion_jobs(integer,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.complete_account_deletion_cleanup(uuid,uuid)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.finish_account_deletion_attempt(uuid,uuid,boolean,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'service_role is missing an account-deletion worker RPC';
    END IF;
END;
$$;

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000'::UUID,
    '00000000-0000-0000-0000-00000000d201'::UUID,
    'authenticated',
    'authenticated',
    'account-deletion-test@naturebook.invalid',
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO public.users (
    id,
    email,
    public_username,
    public_author_name,
    public_identity_source
)
VALUES (
    '00000000-0000-0000-0000-00000000d201'::UUID,
    'account-deletion-test@naturebook.invalid',
    'delete_test_d201',
    'Deletion Test',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email;

INSERT INTO public.scans (
    id,
    user_id,
    ai_confidence_score
)
VALUES (
    '00000000-0000-0000-0000-00000000d211'::UUID,
    '00000000-0000-0000-0000-00000000d201'::UUID,
    0.91
);

CREATE TEMP TABLE account_deletion_test_job (
    job_id UUID NOT NULL,
    job_status TEXT NOT NULL
);
GRANT SELECT, INSERT ON account_deletion_test_job TO service_role;

CREATE TEMP TABLE account_deletion_test_claim (
    job_id UUID NOT NULL,
    user_id UUID NOT NULL,
    job_status TEXT NOT NULL,
    claim_token UUID NOT NULL,
    claim_expires_at TIMESTAMPTZ NOT NULL
);
GRANT SELECT, INSERT, DELETE ON account_deletion_test_claim TO service_role;

SET LOCAL ROLE service_role;

INSERT INTO account_deletion_test_job
SELECT *
FROM public.request_account_deletion(
    '00000000-0000-0000-0000-00000000d201'::UUID
);

INSERT INTO account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d201'::UUID
);

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.users AS app_user
        WHERE app_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) THEN
        RAISE EXCEPTION
            'Durable intake or claim mutated Auth or user data';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

DO $$
BEGIN
    BEGIN
        PERFORM public.finish_account_deletion_attempt(
            (SELECT job_id FROM account_deletion_test_claim),
            (SELECT claim_token FROM account_deletion_test_claim),
            TRUE,
            NULL
        );
        RAISE EXCEPTION
            'Auth completion succeeded before relational cleanup';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;
END;
$$;

SELECT public.complete_account_deletion_cleanup(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim)
);

-- Every delivery, including auth_pending recovery, repeats the idempotent
-- cleanup immediately before the external Auth step.
SELECT public.complete_account_deletion_cleanup(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim)
);

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) THEN
        RAISE EXCEPTION
            'Relational cleanup deleted Auth before verification completed';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.users AS app_user
        WHERE app_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.id =
            '00000000-0000-0000-0000-00000000d211'::UUID
          AND scan.user_id =
            '00000000-0000-0000-0000-000000000000'::UUID
          AND scan.is_tombstoned
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.pending_storage_deletions AS deletion
        WHERE deletion.target_user_id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id
            FROM account_deletion_test_job
        )
          AND deletion_job.status = 'auth_pending'
          AND deletion_job.cleanup_completed_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'Relational cleanup did not commit and verify the expected state';
    END IF;
END;
$$;

DO $$
DECLARE
    recreation_rejected BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO public.users (
            id,
            email,
            public_username,
            public_author_name,
            public_identity_source
        )
        VALUES (
            '00000000-0000-0000-0000-00000000d201'::UUID,
            'account-deletion-resurrection@naturebook.invalid',
            'delete_again_d201',
            'Deletion Resurrection Test',
            'alias'
        );
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            recreation_rejected := TRUE;
    END;

    IF NOT recreation_rejected THEN
        RAISE EXCEPTION
            'Active deletion allowed the public profile to be recreated';
    END IF;
END;
$$;

SET LOCAL ROLE service_role;

SELECT public.finish_account_deletion_attempt(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim),
    FALSE,
    'auth_http_503'
);

RESET ROLE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id
            FROM account_deletion_test_job
        )
          AND deletion_job.status = 'auth_pending'
          AND deletion_job.claim_token IS NULL
          AND deletion_job.next_attempt_at > pg_catalog.NOW()
          AND deletion_job.last_error_code = 'auth_http_503'
    ) OR NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) THEN
        RAISE EXCEPTION
            'Retry scheduling lost state or removed Auth prematurely';
    END IF;

    UPDATE internal.account_deletion_jobs AS deletion_job
    SET next_attempt_at = pg_catalog.NOW()
    WHERE deletion_job.id = (
        SELECT job_id
        FROM account_deletion_test_job
    );
END;
$$;

DELETE FROM account_deletion_test_claim;

SET LOCAL ROLE service_role;

INSERT INTO account_deletion_test_claim
SELECT *
FROM public.claim_account_deletion_jobs(
    1,
    '00000000-0000-0000-0000-00000000d201'::UUID
);

RESET ROLE;

DELETE FROM auth.users
WHERE id = '00000000-0000-0000-0000-00000000d201'::UUID;

SET LOCAL ROLE service_role;

SELECT public.finish_account_deletion_attempt(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim),
    TRUE,
    NULL
);

-- Lost-success retries are idempotent even after the terminal row erased its
-- direct user identifier and cleared the lease.
SELECT public.finish_account_deletion_attempt(
    (SELECT job_id FROM account_deletion_test_claim),
    (SELECT claim_token FROM account_deletion_test_claim),
    TRUE,
    NULL
);

RESET ROLE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-00000000d201'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT job_id
            FROM account_deletion_test_job
        )
          AND deletion_job.status = 'completed'
          AND deletion_job.user_id IS NULL
          AND deletion_job.auth_deleted_at IS NOT NULL
          AND deletion_job.completed_at IS NOT NULL
          AND deletion_job.claim_token IS NULL
          AND deletion_job.last_error_code IS NULL
    ) THEN
        RAISE EXCEPTION
            'Terminal account-deletion state is incomplete or retains identity';
    END IF;
END;
$$;

SELECT extensions.pass(
    'account deletion persists intent, cleans before Auth, retries, and minimizes terminal identity'
);
SELECT * FROM extensions.finish();
ROLLBACK;
