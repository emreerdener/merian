\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-4000-8000-00000000e101';
    first_job_id UUID := '00000000-0000-4000-8000-00000000e111';
    second_job_id UUID := '00000000-0000-4000-8000-00000000e112';
    legacy_job_id UUID := '00000000-0000-4000-8000-00000000e113';
    post_rollout_job_id UUID := '00000000-0000-4000-8000-00000000e114';
    legacy_failure_job_id UUID :=
        '00000000-0000-4000-8000-00000000e115';
    first_token UUID := '00000000-0000-4000-8000-00000000e121';
    second_token UUID := '00000000-0000-4000-8000-00000000e122';
    post_rollout_token UUID := '00000000-0000-4000-8000-00000000e123';
    claim_row RECORD;
    returned_rows INTEGER;
    routine_signature TEXT;
    boolean_result BOOLEAN;
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_job_claims',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_job_claims',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_job_claims',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role can read private export claim tokens';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_worker_protocol',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_worker_protocol',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_worker_protocol',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role can read private export rollout state';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_job_work',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_job_work',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_job_work',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_job_chunks',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_job_chunks',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_job_chunks',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role can bypass private export batch state';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.export_jobs',
        'INSERT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.export_jobs',
        'INSERT'
    ) THEN
        RAISE EXCEPTION 'an API role can bypass the export request endpoint';
    END IF;

    FOREACH routine_signature IN ARRAY ARRAY[
        'public.claim_export_job(uuid,uuid)',
        'public.renew_export_job_claim(uuid,uuid)',
        'public.stage_export_job_archive(uuid,uuid,text,text)',
        'public.complete_export_job(uuid,uuid)',
        'public.fail_export_job(uuid,uuid,text)',
        'public.get_due_export_job_ids(integer)',
        'public.claim_export_job_step(uuid,uuid)',
        'public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,boolean)',
        'public.get_export_job_chunks(uuid,uuid)',
        'public.stage_prepared_export_archive(uuid,uuid,text,text)',
        'public.complete_prepared_export_job(uuid,uuid)',
        'public.release_export_job_step(uuid,uuid,text,boolean)'
    ]
    LOOP
        IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'service_role',
            routine_signature,
            'EXECUTE'
        ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'authenticated',
            routine_signature,
            'EXECUTE'
        ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
            'anon',
            routine_signature,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'invalid API-role grants for export RPC %',
                routine_signature;
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = function_row.pronamespace
        WHERE namespace_row.nspname = 'public'
          AND function_row.proname IN (
              'claim_export_job',
              'renew_export_job_claim',
              'stage_export_job_archive',
              'complete_export_job',
              'fail_export_job',
              'get_due_export_job_ids',
              'claim_export_job_step',
              'advance_export_job_step',
              'get_export_job_chunks',
              'stage_prepared_export_archive',
              'complete_prepared_export_job',
              'release_export_job_step'
          )
          AND (
              NOT function_row.prosecdef
              OR function_row.prosrc NOT LIKE
                  '%internal.require_service_role()%'
              OR NOT (
                  COALESCE(
                      function_row.proconfig,
                      ARRAY[]::TEXT[]
                  ) @> ARRAY['search_path=""']::TEXT[]
              )
          )
    ) THEN
        RAISE EXCEPTION
            'an export definer RPC lacks authorization or an empty search_path';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'internal.enforce_export_job_update()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'internal.enforce_export_job_update()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.enforce_export_job_update()',
        'EXECUTE'
    ) OR EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS function_row
        WHERE function_row.oid =
              'internal.enforce_export_job_update()'::REGPROCEDURE
          AND (
              NOT function_row.prosecdef
              OR NOT (
                  COALESCE(
                      function_row.proconfig,
                      ARRAY[]::TEXT[]
                  ) @> ARRAY['search_path=""']::TEXT[]
              )
          )
    ) THEN
        RAISE EXCEPTION
            'the private export transition trigger has unsafe privileges';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_indexes AS index_row
        WHERE index_row.schemaname = 'public'
          AND index_row.indexname = 'idx_scans_dwca_personal_keyset'
          AND index_row.indexdef LIKE '%(user_id, id)%'
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_indexes AS index_row
        WHERE index_row.schemaname = 'public'
          AND index_row.indexname = 'idx_scans_dwca_global_keyset'
          AND index_row.indexdef LIKE '%(id)%'
    ) THEN
        RAISE EXCEPTION 'DwC-A keyset indexes are missing';
    END IF;

    IF (
        SELECT column_row.column_default
        FROM information_schema.columns AS column_row
        WHERE column_row.table_schema = 'public'
          AND column_row.table_name = 'export_jobs'
          AND column_row.column_name = 'pseudonym_key_version'
    ) IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'export pseudonym key version default is not pinned';
    END IF;

    IF (
        SELECT column_row.column_default
        FROM information_schema.columns AS column_row
        WHERE column_row.table_schema = 'public'
          AND column_row.table_name = 'export_jobs'
          AND column_row.column_name = 'max_export_rows'
    ) IS DISTINCT FROM '5000' OR (
        SELECT column_row.column_default
        FROM information_schema.columns AS column_row
        WHERE column_row.table_schema = 'public'
          AND column_row.table_name = 'export_jobs'
          AND column_row.column_name = 'max_archive_bytes'
    ) IS DISTINCT FROM '8388608' THEN
        RAISE EXCEPTION 'canonical DwC-A budgets are not pinned';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgrelid = 'public.export_jobs'::REGCLASS
          AND trigger_row.tgname = 'enforce_export_job_update'
          AND NOT trigger_row.tgisinternal
    ) THEN
        RAISE EXCEPTION 'export canonical-state trigger is missing';
    END IF;

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
        'export-test@naturebook.invalid',
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

    -- Avoid an irrelevant pg_net call from this transactional fixture.
    ALTER TABLE public.export_jobs
        DISABLE TRIGGER on_export_job_created;

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        first_job_id,
        test_user_id,
        'global',
        FALSE
    );

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job(first_job_id, first_token);

    IF claim_row.user_id <> test_user_id
       OR claim_row.export_scope <> 'global'
       OR claim_row.include_precise_coordinates
       OR claim_row.pseudonym_key_version <> 1
       OR claim_row.attempt_count <> 1 THEN
        RAISE EXCEPTION 'claim did not return canonical job state';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_rows
    FROM public.claim_export_job(first_job_id, second_token);

    IF returned_rows <> 0 THEN
        RAISE EXCEPTION 'a concurrent worker acquired an active export lease';
    END IF;

    BEGIN
        UPDATE public.export_jobs
        SET status = 'processing'
        WHERE id = first_job_id;
        RAISE EXCEPTION 'an old worker continued after a claim was installed';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            IF SQLERRM <> 'claimed_export_job_already_owned' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE public.export_jobs
        SET status = 'completed',
            completed_at = pg_catalog.NOW()
        WHERE id = first_job_id;
        RAISE EXCEPTION 'a claimed job completed without a staged archive';
    EXCEPTION
        WHEN SQLSTATE '23514' THEN
            IF SQLERRM <> 'completed_export_job_requires_archive' THEN
                RAISE;
            END IF;
    END;

    SELECT public.stage_export_job_archive(
        first_job_id,
        second_token,
        'exports/' || test_user_id::TEXT || '/' || first_job_id::TEXT || '/'
            || second_token::TEXT || '.zip',
        'https://example.invalid/stale.zip'
    )
    INTO boolean_result;
    IF boolean_result THEN
        RAISE EXCEPTION 'a stale token staged an export archive';
    END IF;

    SELECT public.stage_export_job_archive(
        first_job_id,
        first_token,
        'exports/' || test_user_id::TEXT || '/' || first_job_id::TEXT || '/'
            || first_token::TEXT || '.zip',
        'https://example.invalid/export.zip?signature=stable'
    )
    INTO boolean_result;
    IF NOT boolean_result THEN
        RAISE EXCEPTION 'the active worker could not stage its archive';
    END IF;

    BEGIN
        UPDATE public.export_jobs
        SET status = 'failed',
            error_message = 'old worker provider detail'
        WHERE id = first_job_id;
        RAISE EXCEPTION 'an old worker failed a claimed export job';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            IF SQLERRM <> 'claimed_export_job_failure_requires_rpc' THEN
                RAISE;
            END IF;
    END;

    BEGIN
        UPDATE public.export_jobs
        SET status = 'completed',
            file_url = 'https://example.invalid/old-worker.zip',
            completed_at = pg_catalog.NOW()
        WHERE id = first_job_id;
        RAISE EXCEPTION 'an old worker replaced a claimed export result';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            IF SQLERRM <> 'claimed_export_job_result_requires_rpc' THEN
                RAISE;
            END IF;
    END;

    SELECT public.complete_export_job(first_job_id, second_token)
    INTO boolean_result;
    IF boolean_result THEN
        RAISE EXCEPTION 'a stale token completed an export job';
    END IF;

    SELECT public.complete_export_job(first_job_id, first_token)
    INTO boolean_result;
    IF NOT boolean_result THEN
        RAISE EXCEPTION 'the active worker could not complete its export';
    END IF;

    BEGIN
        UPDATE public.export_jobs
        SET file_url = 'https://example.invalid/terminal-overwrite.zip'
        WHERE id = first_job_id;
        RAISE EXCEPTION 'a terminal export result remained mutable';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            IF SQLERRM <> 'terminal_export_job_is_immutable' THEN
                RAISE;
            END IF;
    END;

    SELECT public.complete_export_job(first_job_id, first_token)
    INTO boolean_result;
    IF NOT boolean_result THEN
        RAISE EXCEPTION 'completion is not idempotent for the winning token';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_rows
    FROM public.claim_export_job(first_job_id, second_token);
    IF returned_rows <> 0 THEN
        RAISE EXCEPTION 'a terminal export was claimed again';
    END IF;

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        second_job_id,
        test_user_id,
        'personal',
        TRUE
    );

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job(second_job_id, first_token);

    UPDATE internal.export_job_claims AS claims
    SET lease_expires_at = pg_catalog.NOW() - INTERVAL '1 second'
    WHERE claims.job_id = second_job_id;

    SELECT public.stage_export_job_archive(
        second_job_id,
        first_token,
        'exports/' || test_user_id::TEXT || '/' || second_job_id::TEXT || '/'
            || first_token::TEXT || '.zip',
        'https://example.invalid/expired.zip'
    )
    INTO boolean_result;
    IF boolean_result THEN
        RAISE EXCEPTION 'an expired lease staged an export archive';
    END IF;

    SELECT public.renew_export_job_claim(second_job_id, first_token)
    INTO boolean_result;
    IF boolean_result THEN
        RAISE EXCEPTION 'an expired lease renewed itself';
    END IF;

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job(second_job_id, second_token);
    IF claim_row.attempt_count <> 2 THEN
        RAISE EXCEPTION 'lease recovery did not advance the attempt count';
    END IF;

    SELECT public.renew_export_job_claim(second_job_id, first_token)
    INTO boolean_result;
    IF boolean_result THEN
        RAISE EXCEPTION 'a stale token renewed a replacement lease';
    END IF;

    SELECT public.fail_export_job(
        second_job_id,
        first_token,
        'archive_generation_failed'
    )
    INTO boolean_result;
    IF boolean_result THEN
        RAISE EXCEPTION 'a stale token failed a replacement attempt';
    END IF;

    SELECT public.fail_export_job(
        second_job_id,
        second_token,
        'archive_generation_failed'
    )
    INTO boolean_result;
    IF NOT boolean_result THEN
        RAISE EXCEPTION 'the active token could not fail its attempt';
    END IF;

    BEGIN
        UPDATE public.export_jobs
        SET export_scope = 'global'
        WHERE id = second_job_id;
        RAISE EXCEPTION 'canonical export scope was mutable';
    EXCEPTION
        WHEN SQLSTATE '22023' THEN
            IF SQLERRM <> 'export_job_request_is_immutable' THEN
                RAISE;
            END IF;
    END;

    IF (
        SELECT jobs.error_message
        FROM public.export_jobs AS jobs
        WHERE jobs.id = second_job_id
    ) <> 'Export processing failed. Please retry.' THEN
        RAISE EXCEPTION 'failed jobs expose a non-stable error message';
    END IF;

    -- Migrations deploy before Edge bundles. A prior service worker has no
    -- claim/archive columns, so retain its completion path only for the finite
    -- migration cohort.
    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        legacy_job_id,
        test_user_id,
        'personal',
        TRUE
    );

    UPDATE public.export_jobs
    SET status = 'processing'
    WHERE id = legacy_job_id;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_rows
    FROM public.claim_export_job(legacy_job_id, first_token);
    IF returned_rows <> 0 THEN
        RAISE EXCEPTION
            'a new worker claimed an in-flight rollout-era export';
    END IF;

    UPDATE public.export_jobs
    SET status = 'completed',
        file_url = 'https://example.invalid/legacy-rollout.zip',
        completed_at = pg_catalog.NOW()
    WHERE id = legacy_job_id;

    IF (
        SELECT jobs.status
        FROM public.export_jobs AS jobs
        WHERE jobs.id = legacy_job_id
    ) <> 'completed'::public.export_status THEN
        RAISE EXCEPTION 'migration-before-bundle export compatibility failed';
    END IF;

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        legacy_failure_job_id,
        test_user_id,
        'personal',
        FALSE
    );

    UPDATE public.export_jobs
    SET status = 'processing'
    WHERE id = legacy_failure_job_id;

    UPDATE public.export_jobs
    SET status = 'failed',
        error_message =
            'provider failure: secret implementation detail'
    WHERE id = legacy_failure_job_id;

    IF (
        SELECT jobs.error_message
        FROM public.export_jobs AS jobs
        WHERE jobs.id = legacy_failure_job_id
    ) <> 'Export processing failed. Please retry.' THEN
        RAISE EXCEPTION
            'a rollout-era worker persisted internal failure details';
    END IF;

    -- The compatibility shape is a finite migration cohort, not a permanent
    -- alternate processing path. A job created after its deadline requires
    -- the same private claim as every steady-state worker.
    UPDATE internal.export_worker_protocol
    SET legacy_payload_until =
        pg_catalog.NOW() - INTERVAL '1 second'
    WHERE singleton;

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        post_rollout_job_id,
        test_user_id,
        'personal',
        FALSE
    );

    BEGIN
        UPDATE public.export_jobs
        SET status = 'processing'
        WHERE id = post_rollout_job_id;
        RAISE EXCEPTION 'a post-rollout job processed without a claim';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN
            IF SQLERRM <> 'export_job_claim_required' THEN
                RAISE;
            END IF;
    END;

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job(
        post_rollout_job_id,
        post_rollout_token
    );

    IF claim_row.job_id <> post_rollout_job_id THEN
        RAISE EXCEPTION 'the fenced worker could not claim post-rollout work';
    END IF;

    ALTER TABLE public.export_jobs
        ENABLE TRIGGER on_export_job_created;
END;
$test$;

SELECT extensions.pass(
    'DwC-A jobs are canonical, finitely compatible, fenced, private, and keyset-indexed'
);
SELECT * FROM extensions.finish();
ROLLBACK;
