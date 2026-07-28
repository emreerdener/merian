\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    release_state JSONB;
    request_result JSONB;
BEGIN
    IF internal.dwca_exports_are_enabled() THEN
        RAISE EXCEPTION 'DwC-A exports are not default-off';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.dwca_export_release_control',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.dwca_export_release_control',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.dwca_export_release_control',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role can read private DwC-A release state';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.get_dwca_export_release_state()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_dwca_export_release_state()',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_dwca_export_release_state()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_dwca_export_job(uuid,text,boolean)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_dwca_export_job(uuid,text,boolean)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_dwca_export_job(uuid,text,boolean)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'DwC-A release routines have unexpected ACLs';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.dwca_exports_are_enabled()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.dwca_exports_are_enabled()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.dwca_exports_are_enabled()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.enforce_dwca_export_intake_gate()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.enforce_dwca_export_intake_gate()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.enforce_dwca_export_intake_gate()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'a DwC-A release helper is API-role executable';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'internal.dwca_exports_are_enabled()'::REGPROCEDURE
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')

        UNION ALL

        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'internal.enforce_dwca_export_intake_gate()'::REGPROCEDURE,
            'public.export_jobs'::REGCLASS
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')

        UNION ALL

        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'public.get_dwca_export_release_state()'::REGPROCEDURE
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')

        UNION ALL

        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'public.request_dwca_export_job(uuid,text,boolean)'::REGPROCEDURE
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')
    ) THEN
        RAISE EXCEPTION 'a DwC-A launch-gate routine fails static validation';
    END IF;

    release_state := public.get_dwca_export_release_state();
    IF release_state IS DISTINCT FROM '{"enabled": false}'::JSONB THEN
        RAISE EXCEPTION 'service-side release state did not fail closed';
    END IF;

    request_result := public.request_dwca_export_job(
        '00000000-0000-4000-8000-00000000e301'::UUID,
        'personal',
        FALSE
    );
    IF request_result IS DISTINCT FROM '{"status": "disabled"}'::JSONB THEN
        RAISE EXCEPTION 'the transactional request RPC bypassed the gate';
    END IF;

    BEGIN
        INSERT INTO public.export_jobs (
            id,
            user_id,
            export_scope,
            include_precise_coordinates
        )
        VALUES (
            '00000000-0000-4000-8000-00000000e302'::UUID,
            '00000000-0000-4000-8000-00000000e301'::UUID,
            'personal',
            FALSE
        );
        RAISE EXCEPTION 'a direct insert bypassed the launch gate';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            IF SQLERRM <> 'dwca_exports_disabled' THEN
                RAISE;
            END IF;
    END;

    IF EXISTS (
        SELECT 1
        FROM cron.job AS scheduled_job
        WHERE scheduled_job.jobname =
                'resume_dwca_exports_every_minute'
          AND scheduled_job.active
    ) THEN
        RAISE EXCEPTION 'DwC-A processing cron remains active';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM cron.job AS scheduled_job
        WHERE scheduled_job.jobname =
                'reconcile_dwca_archive_cleanup_every_five_minutes'
          AND scheduled_job.active
    ) THEN
        RAISE EXCEPTION 'independent DwC-A archive cleanup was disabled';
    END IF;
END;
$test$;

SELECT extensions.pass(
    'DwC-A launch gate is private, default-off, transactional, and cleanup-safe'
);
SELECT * FROM extensions.finish();
ROLLBACK;
