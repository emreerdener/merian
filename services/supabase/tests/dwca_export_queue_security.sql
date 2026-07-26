\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-4000-8000-00000000e701';
    test_job_id UUID := '00000000-0000-4000-8000-00000000e702';
    test_claim_token UUID :=
        '00000000-0000-4000-8000-00000000e703';
    baseline RECORD;
    due_health RECORD;
    claimed_health RECORD;
    expired_health RECORD;
    claim_row RECORD;
BEGIN
    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_dwca_export_queue_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_dwca_export_queue_health()',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_dwca_export_queue_health()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'DwC-A queue health RPC has an unsafe ACL';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS grants
        WHERE grants.role_name = 'service_role'
          AND grants.routine_signature =
                'public.get_dwca_export_queue_health()'
    ) THEN
        RAISE EXCEPTION
            'DwC-A queue health RPC is absent from the privilege allowlist';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_indexes AS indexes
        WHERE indexes.schemaname = 'public'
          AND indexes.indexname =
                'idx_export_jobs_nonterminal_created'
          AND indexes.indexdef LIKE '%(created_at, id)%'
          AND indexes.indexdef LIKE
                '%WHERE (status = ANY (%pending%processing%))%'
    ) THEN
        RAISE EXCEPTION
            'DwC-A outstanding-job queue index is missing or unbounded';
    END IF;

    SELECT *
    INTO STRICT baseline
    FROM public.get_dwca_export_queue_health();

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
        test_user_id,
        'authenticated',
        'authenticated',
        'dwca-queue-test@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        pg_catalog.JSONB_BUILD_OBJECT(
            'provider',
            'google',
            'providers',
            pg_catalog.JSONB_BUILD_ARRAY('google')
        ),
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    );

    -- The queue test invokes the worker RPCs directly; avoid an irrelevant
    -- pg_net request while inserting the canonical export job.
    ALTER TABLE public.export_jobs
        DISABLE TRIGGER on_export_job_created;

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        test_job_id,
        test_user_id,
        'personal',
        FALSE
    );

    UPDATE internal.export_job_work AS work
    SET next_step_at = pg_catalog.NOW() - INTERVAL '10 minutes'
    WHERE work.job_id = test_job_id;

    SELECT *
    INTO STRICT due_health
    FROM public.get_dwca_export_queue_health();

    IF due_health.backlog_count <> baseline.backlog_count + 1
       OR due_health.due_count <> baseline.due_count + 1
       OR due_health.oldest_due_at IS NULL
       OR due_health.oldest_due_age_seconds < 590 THEN
        RAISE EXCEPTION
            'DwC-A queue health did not expose an overdue continuation';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.get_due_export_job_ids(5) AS due
        WHERE due.job_id = test_job_id
    ) THEN
        RAISE EXCEPTION
            'oldest-due discovery omitted an unclaimed continuation';
    END IF;

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job_step(test_job_id, test_claim_token);

    SELECT *
    INTO STRICT claimed_health
    FROM public.get_dwca_export_queue_health();

    IF claimed_health.backlog_count <> baseline.backlog_count + 1
       OR claimed_health.due_count <> baseline.due_count
       OR claimed_health.active_claim_count <>
            baseline.active_claim_count + 1 THEN
        RAISE EXCEPTION
            'DwC-A queue health did not exclude a live fenced claim';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_due_export_job_ids(5) AS due
        WHERE due.job_id = test_job_id
    ) THEN
        RAISE EXCEPTION
            'oldest-due discovery returned a live claimed continuation';
    END IF;

    UPDATE internal.export_job_claims AS claims
    SET lease_expires_at = pg_catalog.NOW() - INTERVAL '1 second'
    WHERE claims.job_id = test_job_id;

    SELECT *
    INTO STRICT expired_health
    FROM public.get_dwca_export_queue_health();

    IF expired_health.backlog_count <> baseline.backlog_count + 1
       OR expired_health.due_count <> baseline.due_count + 1
       OR expired_health.expired_claim_count <>
            baseline.expired_claim_count + 1
       OR expired_health.oldest_due_at IS NULL THEN
        RAISE EXCEPTION
            'DwC-A queue health did not expose an expired claim';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.get_due_export_job_ids(5) AS due
        WHERE due.job_id = test_job_id
    ) THEN
        RAISE EXCEPTION
            'oldest-due discovery did not recover an expired claim';
    END IF;

    ALTER TABLE public.export_jobs
        ENABLE TRIGGER on_export_job_created;
END;
$test$;

SELECT extensions.pass(
    'DwC-A continuation queue is indexed, private, and observable'
);
SELECT * FROM extensions.finish();
ROLLBACK;
