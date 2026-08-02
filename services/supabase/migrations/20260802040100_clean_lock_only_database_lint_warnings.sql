-- Remove lint-only composite row holders while preserving the reviewed lock
-- order and all published routine contracts. Rebuild installed definitions so
-- comments, ownership, security settings, and ACLs remain unchanged.

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'apply_revenuecat_reconciliation is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    queue_row internal.revenuecat_reconciliation_queue%ROWTYPE;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'    SELECT queue.*\n    INTO queue_row\n    FROM internal.revenuecat_reconciliation_queue AS queue\n',
        E'    PERFORM 1\n    FROM internal.revenuecat_reconciliation_queue AS queue\n'
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'queue_row') > 0 THEN
        RAISE EXCEPTION
            'apply_revenuecat_reconciliation lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.release_export_job_step(uuid,uuid,text,boolean)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'release_export_job_step is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    job_row public.export_jobs%ROWTYPE;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'    work_row internal.export_job_work%ROWTYPE;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'    SELECT jobs.*\n    INTO job_row\n    FROM public.export_jobs AS jobs\n',
        E'    PERFORM 1\n    FROM public.export_jobs AS jobs\n'
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'    SELECT work.*\n    INTO work_row\n    FROM internal.export_job_work AS work\n',
        E'    PERFORM 1\n    FROM internal.export_job_work AS work\n'
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'job_row') > 0
       OR pg_catalog.STRPOS(patched_sql, 'work_row') > 0 THEN
        RAISE EXCEPTION
            'release_export_job_step lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.complete_prepared_export_job(uuid,uuid)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'complete_prepared_export_job is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    job_row public.export_jobs%ROWTYPE;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'    SELECT jobs.*\n    INTO job_row\n    FROM public.export_jobs AS jobs\n',
        E'    PERFORM 1\n    FROM public.export_jobs AS jobs\n'
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'job_row') > 0 THEN
        RAISE EXCEPTION
            'complete_prepared_export_job lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.ensure_scan_user_profile(uuid)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'ensure_scan_user_profile is missing during lint repair';
    END IF;

    -- Preserve the existing five-attempt retry contract and fifth-conflict
    -- rethrow, but express the bound in the loop itself. The explicit terminal
    -- exception then makes every analyzer-visible path fail closed.
    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    username_attempt INTEGER := 0;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'    LOOP\n',
        E'    FOR profile_attempt IN 1..5 LOOP\n'
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'                username_attempt := username_attempt + 1;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        'username_attempt > 4',
        'profile_attempt = 5'
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        E'    END LOOP;\nEND;\n',
        E'    END LOOP;\n\n    RAISE EXCEPTION ''scan_user_profile_creation_failed''\n        USING ERRCODE = ''P0001'';\nEND;\n'
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'username_attempt') > 0
       OR pg_catalog.STRPOS(
            patched_sql,
            'FOR profile_attempt IN 1..5 LOOP'
       ) = 0
       OR pg_catalog.STRPOS(
            patched_sql,
            'scan_user_profile_creation_failed'
       ) = 0 THEN
        RAISE EXCEPTION
            'ensure_scan_user_profile lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;
