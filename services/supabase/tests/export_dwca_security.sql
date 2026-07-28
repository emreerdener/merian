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
    bounded_job_id UUID := '00000000-0000-4000-8000-00000000e116';
    crc_job_id UUID := '00000000-0000-4000-8000-00000000e117';
    first_token UUID := '00000000-0000-4000-8000-00000000e121';
    second_token UUID := '00000000-0000-4000-8000-00000000e122';
    post_rollout_token UUID := '00000000-0000-4000-8000-00000000e123';
    bounded_token UUID := '00000000-0000-4000-8000-00000000e124';
    crc_token UUID := '00000000-0000-4000-8000-00000000e125';
    confirmed_species_id UUID :=
        '00000000-0000-4000-8000-00000000e129';
    test_species_id UUID := '00000000-0000-4000-8000-00000000e130';
    first_scan_id UUID := '00000000-0000-4000-8000-00000000e131';
    second_scan_id UUID := '00000000-0000-4000-8000-00000000e132';
    third_scan_id UUID := '00000000-0000-4000-8000-00000000e133';
    fourth_scan_id UUID := '00000000-0000-4000-8000-00000000e134';
    claim_row RECORD;
    returned_rows INTEGER;
    routine_signature TEXT;
    boolean_result BOOLEAN;
    first_source_bytes INTEGER;
    second_source_bytes INTEGER;
    returned_source_bytes INTEGER;
    batch_complete BOOLEAN;
    batch_oversize BOOLEAN;
    batch_revision_changed BOOLEAN;
    expected_crc32 BIGINT := 4294967295;
    returned_crc32 BIGINT;
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
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_job_source_state',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_job_source_state',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_job_source_state',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_job_source_rows',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_job_source_rows',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_job_source_rows',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role can bypass private export batch state';
    END IF;

    IF NOT (
        SELECT class_row.relrowsecurity
        FROM pg_catalog.pg_class AS class_row
        WHERE class_row.oid =
              'internal.export_job_source_rows'::REGCLASS
    ) OR (
        SELECT pg_catalog.COUNT(*)
        FROM information_schema.columns AS column_row
        WHERE column_row.table_schema = 'internal'
          AND column_row.table_name = 'export_job_source_rows'
          AND column_row.column_name IN (
              'eligibility_sha256',
              'occurrence_payload',
              'occurrence_byte_count',
              'multimedia_payload',
              'multimedia_byte_count',
              'coordinate_protection_required'
          )
          AND column_row.is_nullable = 'NO'
    ) <> 6 THEN
        RAISE EXCEPTION
            'the private immutable export DTO store is not fully constrained';
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

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attribute_row
        WHERE attribute_row.attrelid =
              'internal.export_job_chunks'::REGCLASS
          AND attribute_row.attname = 'crc32'
          AND attribute_row.attnotnull
          AND NOT attribute_row.attisdropped
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid =
              'internal.export_job_chunks'::REGCLASS
          AND constraint_row.conname =
              'export_job_chunks_crc32_check'
          AND constraint_row.contype = 'c'
          AND constraint_row.convalidated
    ) THEN
        RAISE EXCEPTION
            'the private export chunk manifest lacks a bounded CRC invariant';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attribute_row
        WHERE attribute_row.attrelid =
              'internal.export_job_work'::REGCLASS
          AND attribute_row.attname = 'delivery_file_url'
          AND NOT attribute_row.attnotnull
          AND NOT attribute_row.attisdropped
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid =
              'internal.export_job_work'::REGCLASS
          AND constraint_row.conname =
              'export_job_work_delivery_url_check'
          AND constraint_row.contype = 'c'
          AND constraint_row.convalidated
    ) THEN
        RAISE EXCEPTION
            'the private staged export delivery URL is not constrained';
    END IF;

    FOREACH routine_signature IN ARRAY ARRAY[
        'public.claim_export_job(uuid,uuid)',
        'public.renew_export_job_claim(uuid,uuid)',
        'public.stage_export_job_archive(uuid,uuid,text,text)',
        'public.complete_export_job(uuid,uuid)',
        'public.fail_export_job(uuid,uuid,text)',
        'public.get_due_export_job_ids(integer)',
        'public.claim_export_job_step(uuid,uuid)',
        'public.get_dwca_export_scan_batch(uuid,uuid,text,uuid,integer,integer)',
        'public.advance_export_job_step(uuid,uuid,text,uuid,integer,text,integer,bigint,boolean)',
        'public.get_export_job_chunks(uuid,uuid)',
        'public.check_dwca_export_source_fence(uuid,uuid,text)',
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
              'get_dwca_export_scan_batch',
              'advance_export_job_step',
              'get_export_job_chunks',
              'check_dwca_export_source_fence',
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

    FOREACH routine_signature IN ARRAY ARRAY[
        'internal.materialize_dwca_export_source_snapshot(uuid)',
        'internal.dwca_export_source_is_current(uuid)',
        'internal.initialize_dwca_export_source_snapshot()',
        'internal.purge_dwca_export_source_snapshot()',
        'internal.invalidate_dwca_exports_for_scan()',
        'internal.invalidate_dwca_exports_for_species()'
    ]
    LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
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
                'an API role can execute private snapshot routine %',
                routine_signature;
        END IF;
    END LOOP;

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE (
            (
                trigger_row.tgrelid = 'public.scans'::REGCLASS
                AND trigger_row.tgname IN (
                    'invalidate_dwca_exports_for_scan',
                    'invalidate_dwca_exports_for_scan_truncate'
                )
            ) OR (
                trigger_row.tgrelid =
                    'public.species_dictionary'::REGCLASS
                AND trigger_row.tgname IN (
                    'invalidate_dwca_exports_for_species',
                    'invalidate_dwca_exports_for_species_truncate'
                )
            )
        )
          AND NOT trigger_row.tgisinternal
    ) <> 4 THEN
        RAISE EXCEPTION
            'a durable DwC-A privacy invalidation trigger is missing';
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

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid IN (
            'public.scans'::REGCLASS,
            'public.species_dictionary'::REGCLASS
        )
          AND constraint_row.conname IN (
              'scans_dwca_image_urls_bounded_check',
              'scans_dwca_interactions_bounded_check',
              'species_dictionary_dwca_taxonomy_bounded_check'
          )
          AND NOT constraint_row.convalidated
    ) OR (
        SELECT pg_catalog.COUNT(*)
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid IN (
            'public.scans'::REGCLASS,
            'public.species_dictionary'::REGCLASS
        )
          AND constraint_row.conname IN (
              'scans_dwca_image_urls_bounded_check',
              'scans_dwca_interactions_bounded_check',
              'species_dictionary_dwca_taxonomy_bounded_check'
          )
    ) <> 3 THEN
        RAISE EXCEPTION 'DwC-A source constraints are absent or unvalidated';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'public.scans'::REGCLASS
          AND constraint_row.conname = 'scans_sex_value_check'
          AND constraint_row.convalidated
    ) THEN
        RAISE EXCEPTION
            'the existing finite DwC-A sex source invariant is missing';
    END IF;

    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.dwca_export_snapshot_source',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.dwca_export_snapshot_source',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.dwca_export_snapshot_source',
        'SELECT'
    ) THEN
        RAISE EXCEPTION
            'an API role can bypass the immutable export page RPC';
    END IF;

    IF pg_catalog.TO_REGCLASS(
        'internal.dwca_export_occurrence_source'
    ) IS NOT NULL OR pg_catalog.TO_REGCLASS(
        'internal.dwca_export_multimedia_source'
    ) IS NOT NULL THEN
        RAISE EXCEPTION
            'a live phase-specific export source projection still exists';
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

    IF (
        SELECT pg_catalog.COUNT(*)
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgrelid = 'public.export_jobs'::REGCLASS
          AND trigger_row.tgname IN (
              'enforce_export_job_update',
              'initialize_dwca_export_source_snapshot',
              'purge_dwca_export_source_snapshot'
          )
          AND NOT trigger_row.tgisinternal
    ) <> 3 OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgrelid = 'public.export_jobs'::REGCLASS
          AND trigger_row.tgname = 'enforce_export_job_update'
          AND NOT trigger_row.tgisinternal
    ) THEN
        RAISE EXCEPTION
            'an export canonical-state or source-snapshot trigger is missing';
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

    INSERT INTO public.species_dictionary (
        id,
        scientific_name,
        common_names,
        kingdom,
        phylum,
        class,
        "order",
        family,
        genus,
        native_region
    )
    VALUES
        (
            test_species_id,
            'Exporta boundedensis',
            '{"en":"Bounded export species"}'::JSONB,
            'Animalia',
            'Chordata',
            'Aves',
            'Passeriformes',
            'Exportidae',
            'Exporta',
            'Test region'
        ),
        (
            confirmed_species_id,
            'Exporta confirmata',
            '{"en":"Confirmed export species"}'::JSONB,
            'Animalia',
            'Chordata',
            'Aves',
            'Passeriformes',
            'Exportidae',
            'Exporta',
            'Confirmed region'
        );

    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        confirmed_species_id,
        image_storage_urls,
        ecological_interactions,
        ai_confidence_score
    )
    VALUES
        (
            first_scan_id,
            test_user_id,
            test_species_id,
            confirmed_species_id,
            ARRAY[
                'https://media.example.invalid/first-one.webp',
                'https://media.example.invalid/first-two.webp'
            ],
            ARRAY[pg_catalog.REPEAT('first interaction ', 20)],
            0.9
        ),
        (
            second_scan_id,
            test_user_id,
            test_species_id,
            NULL,
            ARRAY['https://media.example.invalid/second.webp'],
            ARRAY[pg_catalog.REPEAT('second interaction ', 20)],
            0.8
        ),
        (
            third_scan_id,
            test_user_id,
            test_species_id,
            NULL,
            ARRAY['https://media.example.invalid/third.webp'],
            ARRAY[pg_catalog.REPEAT('third interaction ', 20)],
            0.7
        );

    BEGIN
        UPDATE public.scans AS scans
        SET image_storage_urls = ARRAY(
            SELECT
                'https://media.example.invalid/' || value::TEXT || '.webp'
            FROM pg_catalog.GENERATE_SERIES(1, 25) AS value
        )
        WHERE scans.id = first_scan_id;
        RAISE EXCEPTION 'an oversized media array passed its DB constraint';
    EXCEPTION
        WHEN CHECK_VIOLATION THEN NULL;
    END;

    BEGIN
        UPDATE public.scans AS scans
        SET image_storage_urls = ARRAY[pg_catalog.REPEAT('x', 4097)]
        WHERE scans.id = first_scan_id;
        RAISE EXCEPTION 'an oversized media element passed its DB constraint';
    EXCEPTION
        WHEN CHECK_VIOLATION THEN NULL;
    END;

    BEGIN
        UPDATE public.scans AS scans
        SET ecological_interactions = ARRAY(
            SELECT value::TEXT
            FROM pg_catalog.GENERATE_SERIES(1, 11) AS value
        )
        WHERE scans.id = first_scan_id;
        RAISE EXCEPTION
            'an oversized interaction array passed its DB constraint';
    EXCEPTION
        WHEN CHECK_VIOLATION THEN NULL;
    END;

    BEGIN
        UPDATE public.scans AS scans
        SET ecological_interactions = ARRAY[pg_catalog.REPEAT('x', 2049)]
        WHERE scans.id = first_scan_id;
        RAISE EXCEPTION
            'an oversized interaction element passed its DB constraint';
    EXCEPTION
        WHEN CHECK_VIOLATION THEN NULL;
    END;

    BEGIN
        UPDATE public.species_dictionary AS species
        SET scientific_name = pg_catalog.REPEAT('x', 1025)
        WHERE species.id = test_species_id;
        RAISE EXCEPTION
            'an oversized taxonomy value passed its DB constraint';
    EXCEPTION
        WHEN CHECK_VIOLATION THEN NULL;
    END;

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        bounded_job_id,
        test_user_id,
        'personal',
        FALSE
    );

    SELECT
        source_state.source_scan_count,
        source_state.source_too_large
    INTO STRICT
        returned_rows,
        boolean_result
    FROM internal.export_job_source_state AS source_state
    WHERE source_state.job_id = bounded_job_id;

    IF returned_rows <> 3 OR boolean_result THEN
        RAISE EXCEPTION
            'job creation did not freeze the expected immutable source rows';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM internal.export_job_source_state AS source_state
        WHERE source_state.job_id = bounded_job_id
          AND source_state.snapshot_version = 2
          AND source_state.source_byte_count > 0
          AND source_state.source_byte_count
              <= source_state.max_source_bytes
    ) THEN
        RAISE EXCEPTION
            'job creation did not persist a bounded version-two snapshot';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_rows
    FROM internal.export_job_source_rows AS source_rows
    WHERE source_rows.job_id = bounded_job_id;

    IF returned_rows <> 3 THEN
        RAISE EXCEPTION
            'job creation did not persist every immutable source DTO';
    END IF;

    -- This scan is eligible but was created after the export job. Neither CSV
    -- phase may discover it through a later live-table query.
    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        image_storage_urls,
        ecological_interactions,
        ai_confidence_score
    )
    VALUES (
        fourth_scan_id,
        test_user_id,
        test_species_id,
        ARRAY['https://media.example.invalid/fourth.webp'],
        ARRAY['fourth interaction'],
        0.6
    );

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job_step(bounded_job_id, bounded_token);

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_AND(bounded_page.page_complete),
        pg_catalog.BOOL_OR(bounded_page.source_revision_changed)
    INTO
        returned_rows,
        batch_complete,
        batch_revision_changed
    FROM public.get_dwca_export_scan_batch(
        bounded_job_id,
        bounded_token,
        'occurrence',
        NULL,
        100,
        262144
    ) AS bounded_page
    WHERE bounded_page.scan_payload IS NOT NULL;

    IF returned_rows <> 3
       OR NOT batch_complete
       OR batch_revision_changed THEN
        RAISE EXCEPTION
            'the occurrence phase did not use immutable job DTOs';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.get_dwca_export_scan_batch(
            bounded_job_id,
            bounded_token,
            'occurrence',
            NULL,
            100,
            262144
        ) AS bounded_page
        WHERE bounded_page.scan_id = first_scan_id
          AND bounded_page.scan_payload ->> 'effective_species_id' =
              confirmed_species_id::TEXT
          AND NOT (bounded_page.scan_payload ? 'gps_lat_exact')
          AND NOT (bounded_page.scan_payload ? 'gps_long_exact')
          AND bounded_page.scan_payload #>>
              '{species_dictionary,scientific_name}' =
              'Exporta confirmata'
    ) THEN
        RAISE EXCEPTION
            'the immutable occurrence DTO ignored confirmed species identity';
    END IF;

    SELECT bounded_page.source_byte_count
    INTO STRICT first_source_bytes
    FROM public.get_dwca_export_scan_batch(
        bounded_job_id,
        bounded_token,
        'occurrence',
        NULL,
        100,
        262144
    ) AS bounded_page
    WHERE bounded_page.scan_id = first_scan_id;

    SELECT bounded_page.source_byte_count
    INTO STRICT second_source_bytes
    FROM public.get_dwca_export_scan_batch(
        bounded_job_id,
        bounded_token,
        'occurrence',
        NULL,
        100,
        262144
    ) AS bounded_page
    WHERE bounded_page.scan_id = second_scan_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.SUM(bounded_page.source_byte_count)::INTEGER,
        pg_catalog.BOOL_AND(bounded_page.page_complete),
        pg_catalog.BOOL_OR(bounded_page.source_row_oversize)
    INTO
        returned_rows,
        returned_source_bytes,
        batch_complete,
        batch_oversize
    FROM public.get_dwca_export_scan_batch(
        bounded_job_id,
        bounded_token,
        'occurrence',
        NULL,
        100,
        first_source_bytes + second_source_bytes - 1
    ) AS bounded_page
    WHERE bounded_page.scan_payload IS NOT NULL;

    IF returned_rows <> 1
       OR returned_source_bytes > first_source_bytes + second_source_bytes - 1
       OR batch_complete
       OR batch_oversize THEN
        RAISE EXCEPTION
            'the occurrence source page ignored its aggregate byte ceiling';
    END IF;

    UPDATE internal.export_job_work AS work
    SET phase = 'multimedia'
    WHERE work.job_id = bounded_job_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_AND(bounded_page.page_complete),
        pg_catalog.BOOL_OR(bounded_page.source_row_oversize)
    INTO
        returned_rows,
        batch_complete,
        batch_oversize
    FROM public.get_dwca_export_scan_batch(
        bounded_job_id,
        bounded_token,
        'multimedia',
        NULL,
        2,
        262144
    ) AS bounded_page
    WHERE bounded_page.scan_payload IS NOT NULL;

    IF returned_rows <> 2 OR batch_complete OR batch_oversize THEN
        RAISE EXCEPTION
            'the multimedia source page ignored its row or completion bound';
    END IF;

    UPDATE public.scans AS scans
    SET image_storage_urls =
        ARRAY['https://media.example.invalid/revised-first.webp']
    WHERE scans.id = first_scan_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_OR(bounded_page.source_revision_changed),
        pg_catalog.BOOL_AND(
            CASE
                WHEN bounded_page.scan_id = first_scan_id THEN
                    bounded_page.scan_payload -> 'image_storage_urls' =
                    pg_catalog.JSONB_BUILD_ARRAY(
                        'https://media.example.invalid/first-one.webp',
                        'https://media.example.invalid/first-two.webp'
                    )
                ELSE TRUE
            END
        )
    INTO
        returned_rows,
        batch_revision_changed,
        boolean_result
    FROM public.get_dwca_export_scan_batch(
        bounded_job_id,
        bounded_token,
        'multimedia',
        NULL,
        100,
        262144
    ) AS bounded_page;

    IF returned_rows <> 3
       OR batch_revision_changed
       OR NOT boolean_result THEN
        RAISE EXCEPTION
            'a live media change altered an immutable multimedia DTO';
    END IF;

    UPDATE public.scans AS scans
    SET is_tombstoned = TRUE
    WHERE scans.id = first_scan_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_AND(bounded_page.source_revision_changed),
        pg_catalog.BOOL_OR(bounded_page.scan_payload IS NOT NULL)
    INTO
        returned_rows,
        batch_revision_changed,
        boolean_result
    FROM public.get_dwca_export_scan_batch(
        bounded_job_id,
        bounded_token,
        'multimedia',
        NULL,
        100,
        262144
    ) AS bounded_page;

    IF returned_rows <> 1
       OR NOT batch_revision_changed
       OR boolean_result THEN
        RAISE EXCEPTION
            'a privacy eligibility revocation escaped the live export fence';
    END IF;

    UPDATE public.scans AS scans
    SET is_tombstoned = FALSE
    WHERE scans.id = first_scan_id;

    UPDATE internal.export_job_work AS work
    SET delivery_file_url =
        'https://r2.example.invalid/revoked-export.zip?signed=private'
    WHERE work.job_id = bounded_job_id;

    SELECT public.release_export_job_step(
        bounded_job_id,
        bounded_token,
        'archive_generation_failed',
        TRUE
    )
    INTO boolean_result;

    IF NOT boolean_result THEN
        RAISE EXCEPTION
            'the bounded source-page fixture could not release its active job';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_rows
    FROM internal.export_job_source_rows AS source_rows
    WHERE source_rows.job_id = bounded_job_id;

    SELECT
        source_state.purged_at IS NOT NULL
        AND work.delivery_file_url IS NULL
    INTO STRICT boolean_result
    FROM internal.export_job_source_state AS source_state
    INNER JOIN internal.export_job_work AS work
        ON work.job_id = source_state.job_id
    WHERE source_state.job_id = bounded_job_id;

    IF returned_rows <> 0 OR NOT boolean_result THEN
        RAISE EXCEPTION
            'terminal export retained source DTOs or a staged signed URL';
    END IF;

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        crc_job_id,
        test_user_id,
        'personal',
        FALSE
    );

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job_step(crc_job_id, crc_token);

    SELECT public.advance_export_job_step(
        crc_job_id,
        crc_token,
        'occurrence',
        fourth_scan_id,
        4,
        'exports/' || test_user_id::TEXT || '/' || crc_job_id::TEXT
            || '/work/occurrence/00000000-' || crc_token::TEXT || '.csv',
        3,
        expected_crc32,
        TRUE
    )
    INTO routine_signature;

    IF routine_signature <> 'multimedia' THEN
        RAISE EXCEPTION
            'the CRC-aware advance did not transition to multimedia';
    END IF;

    SELECT chunks.crc32
    INTO STRICT returned_crc32
    FROM internal.export_job_chunks AS chunks
    WHERE chunks.job_id = crc_job_id
      AND chunks.phase = 'occurrence'
      AND chunks.sequence = 0;

    IF returned_crc32 <> expected_crc32 THEN
        RAISE EXCEPTION
            'the fenced advance did not persist the unsigned chunk CRC';
    END IF;

    BEGIN
        UPDATE internal.export_job_chunks AS chunks
        SET crc32 = -1
        WHERE chunks.job_id = crc_job_id
          AND chunks.phase = 'occurrence'
          AND chunks.sequence = 0;
        RAISE EXCEPTION
            'the chunk manifest accepted an out-of-range CRC';
    EXCEPTION
        WHEN CHECK_VIOLATION THEN NULL;
    END;

    UPDATE internal.export_job_work AS work
    SET phase = 'assembling'
    WHERE work.job_id = crc_job_id;

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job_step(crc_job_id, crc_token);

    SELECT chunks.crc32
    INTO STRICT returned_crc32
    FROM public.get_export_job_chunks(
        crc_job_id,
        crc_token
    ) AS chunks
    WHERE chunks.chunk_phase = 'occurrence'
      AND chunks.chunk_sequence = 0;

    IF returned_crc32 <> expected_crc32 THEN
        RAISE EXCEPTION
            'the assembly manifest did not return the durable unsigned CRC';
    END IF;

    SELECT public.release_export_job_step(
        crc_job_id,
        crc_token,
        'archive_generation_failed',
        TRUE
    )
    INTO boolean_result;

    IF NOT boolean_result THEN
        RAISE EXCEPTION
            'the CRC manifest fixture could not release its active job';
    END IF;

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
