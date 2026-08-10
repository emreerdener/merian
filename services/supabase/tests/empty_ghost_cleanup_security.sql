\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $$
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.inspect_empty_ghost_cleanup_candidate(uuid,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.inspect_empty_ghost_cleanup_candidate(uuid,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamp with time zone,integer)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamp with time zone,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.empty_ghost_account_deletion_receipts',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'empty-Ghost cleanup privilege boundary is invalid';
    END IF;
END;
$$;

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
SELECT
    '00000000-0000-0000-0000-000000000000'::UUID,
    seed.user_id,
    'authenticated',
    'authenticated',
    NULL,
    pg_catalog.NOW() - INTERVAL '90 days',
    pg_catalog.JSONB_BUILD_OBJECT(
        'provider',
        'anonymous',
        'providers',
        pg_catalog.JSONB_BUILD_ARRAY('anonymous')
    ),
    '{}'::JSONB,
    pg_catalog.NOW() - INTERVAL '90 days',
    pg_catalog.NOW() - INTERVAL '90 days',
    TRUE
FROM (VALUES
    ('00000000-0000-4000-8000-00000000e101'::UUID),
    ('00000000-0000-4000-8000-00000000e102'::UUID)
) AS seed(user_id);

INSERT INTO public.users (id)
VALUES
    ('00000000-0000-4000-8000-00000000e101'::UUID),
    ('00000000-0000-4000-8000-00000000e102'::UUID)
ON CONFLICT (id) DO NOTHING;

-- A custom identity is sufficient to preserve the second otherwise-empty
-- anonymous account.
UPDATE public.users AS profile
SET public_identity_source = 'display_name',
    public_author_name = 'Protected Beta Tester'
WHERE profile.id = '00000000-0000-4000-8000-00000000e102'::UUID;

CREATE TEMP TABLE empty_ghost_cleanup_fixture (
    reservation_token UUID,
    job_id UUID,
    job_status TEXT,
    manual_provider_revocation_required BOOLEAN
);
GRANT SELECT, INSERT, UPDATE ON empty_ghost_cleanup_fixture TO service_role;

SET LOCAL ROLE service_role;

DO $$
DECLARE
    eligible_candidate BOOLEAN;
    eligible_blockers TEXT[];
    protected_candidate BOOLEAN;
    protected_blockers TEXT[];
BEGIN
    SELECT inspection.eligible, inspection.blockers
    INTO STRICT eligible_candidate, eligible_blockers
    FROM public.inspect_empty_ghost_cleanup_candidate(
        '00000000-0000-4000-8000-00000000e101'::UUID,
        30
    ) AS inspection;

    SELECT inspection.eligible, inspection.blockers
    INTO STRICT protected_candidate, protected_blockers
    FROM public.inspect_empty_ghost_cleanup_candidate(
        '00000000-0000-4000-8000-00000000e102'::UUID,
        30
    ) AS inspection;

    IF eligible_candidate IS NOT TRUE
       OR pg_catalog.CARDINALITY(eligible_blockers) <> 0
       OR protected_candidate IS NOT FALSE
       OR NOT ('custom_identity_source_present' = ANY(protected_blockers)) THEN
        RAISE EXCEPTION
            'empty-Ghost live inspection did not preserve exact evidence';
    END IF;
END;
$$;

INSERT INTO empty_ghost_cleanup_fixture (reservation_token)
SELECT public.reserve_ghost_user_bulk_cleanup(
    '00000000-0000-4000-8000-00000000e101'::UUID,
    15
);

WITH deletion AS (
    SELECT request.*
    FROM public.request_empty_ghost_account_deletion(
        '00000000-0000-4000-8000-00000000e101'::UUID,
        (SELECT reservation_token FROM empty_ghost_cleanup_fixture),
        30,
        pg_catalog.REPEAT('a', 64),
        'projtest1234',
        pg_catalog.NOW(),
        1
    ) AS request
)
UPDATE empty_ghost_cleanup_fixture AS fixture
SET job_id = deletion.job_id,
    job_status = deletion.job_status,
    manual_provider_revocation_required =
        deletion.manual_provider_revocation_required
FROM deletion;

RESET ROLE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.users AS profile
        WHERE profile.id =
            '00000000-0000-4000-8000-00000000e101'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.users AS profile
        WHERE profile.id =
            '00000000-0000-4000-8000-00000000e102'::UUID
          AND profile.public_author_name = 'Protected Beta Tester'
    ) OR NOT EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-4000-8000-00000000e101'::UUID
    ) OR NOT EXISTS (
        SELECT 1
        FROM public.pending_storage_deletions AS storage_deletion
        WHERE storage_deletion.target_user_id =
            '00000000-0000-4000-8000-00000000e101'::UUID
          AND storage_deletion.status = 'pending'
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.account_deletion_jobs AS deletion_job
        WHERE deletion_job.id = (
            SELECT fixture.job_id FROM empty_ghost_cleanup_fixture AS fixture
        )
          AND deletion_job.status = 'storage_pending'
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.empty_ghost_account_deletion_receipts AS receipt
        WHERE receipt.job_id = (
            SELECT fixture.job_id FROM empty_ghost_cleanup_fixture AS fixture
        )
          AND receipt.candidate_plan_sha256 = pg_catalog.REPEAT('a', 64)
          AND receipt.revenuecat_project_id = 'projtest1234'
          AND receipt.revenuecat_checked_customer_count = 1
    ) OR EXISTS (
        SELECT 1
        FROM internal.ghost_user_cleanup_reservations AS reservation
        WHERE reservation.ghost_user_id =
            '00000000-0000-4000-8000-00000000e101'::UUID
          AND reservation.completed_at IS NULL
    ) OR EXISTS (
        SELECT 1
        FROM empty_ghost_cleanup_fixture AS fixture
        WHERE fixture.job_status <> 'storage_pending'
           OR fixture.manual_provider_revocation_required
    ) THEN
        RAISE EXCEPTION
            'guarded cleanup did not enter storage-first/Auth-last deletion exactly';
    END IF;
END;
$$;

SELECT extensions.pass(
    'empty-Ghost cleanup preserves evidence-bearing accounts and starts only durable deletion'
);
SELECT * FROM extensions.finish();
ROLLBACK;
