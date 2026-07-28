\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-4000-8000-00000000e201';
    test_species_id UUID := '00000000-0000-4000-8000-00000000e202';
    first_scan_id UUID := '00000000-0000-4000-8000-00000000e203';
    second_scan_id UUID := '00000000-0000-4000-8000-00000000e204';
    later_scan_id UUID := '00000000-0000-4000-8000-00000000e205';
    test_job_id UUID := '00000000-0000-4000-8000-00000000e206';
    claim_token UUID := '00000000-0000-4000-8000-00000000e207';
    claim_row RECORD;
    returned_rows INTEGER;
    page_complete BOOLEAN;
    revision_changed BOOLEAN;
    payload_returned BOOLEAN;
    boolean_result BOOLEAN;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'internal.materialize_dwca_export_source_snapshot(uuid)'
                ::REGPROCEDURE
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')

        UNION ALL

        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'public.get_dwca_export_scan_batch(uuid,uuid,text,uuid,integer,integer)'
                ::REGPROCEDURE
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')

        UNION ALL

        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'internal.initialize_dwca_export_source_snapshot()'
                ::REGPROCEDURE,
            'public.export_jobs'::REGCLASS
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')

        UNION ALL

        SELECT 1
        FROM extensions.plpgsql_check_function_tb(
            'internal.purge_dwca_export_source_snapshot()'
                ::REGPROCEDURE,
            'public.export_jobs'::REGCLASS
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')
    ) THEN
        RAISE EXCEPTION
            'a DwC-A source-snapshot routine fails static validation';
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
        'dwca-snapshot-test@naturebook.invalid',
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
    VALUES (
        test_species_id,
        'Snapshotia immutable',
        '{"en":"Immutable snapshot species"}'::JSONB,
        'Animalia',
        'Chordata',
        'Aves',
        'Passeriformes',
        'Snapshotidae',
        'Snapshotia',
        'Test region'
    );

    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        image_storage_urls,
        ecological_interactions,
        ai_confidence_score
    )
    VALUES
        (
            first_scan_id,
            test_user_id,
            test_species_id,
            ARRAY['https://media.example.invalid/snapshot-first.webp'],
            ARRAY['visiting flowers'],
            0.9
        ),
        (
            second_scan_id,
            test_user_id,
            test_species_id,
            ARRAY['https://media.example.invalid/snapshot-second.webp'],
            ARRAY['carrying pollen'],
            0.8
        );

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

    SELECT source_state.source_scan_count
    INTO STRICT returned_rows
    FROM internal.export_job_source_state AS source_state
    WHERE source_state.job_id = test_job_id
      AND source_state.snapshot_version = 2
      AND source_state.source_byte_count > 0
      AND source_state.source_byte_count <= source_state.max_source_bytes
      AND NOT source_state.source_too_large
      AND source_state.purged_at IS NULL;

    IF returned_rows <> 2 THEN
        RAISE EXCEPTION
            'job creation did not atomically snapshot immutable source DTOs';
    END IF;

    INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        image_storage_urls,
        ecological_interactions,
        ai_confidence_score
    )
    VALUES (
        later_scan_id,
        test_user_id,
        test_species_id,
        ARRAY['https://media.example.invalid/snapshot-later.webp'],
        ARRAY['created too late'],
        0.7
    );

    SELECT *
    INTO STRICT claim_row
    FROM public.claim_export_job_step(test_job_id, claim_token);

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_AND(source_page.page_complete),
        pg_catalog.BOOL_OR(source_page.source_revision_changed)
    INTO
        returned_rows,
        page_complete,
        revision_changed
    FROM public.get_dwca_export_scan_batch(
        test_job_id,
        claim_token,
        'occurrence',
        NULL,
        100,
        262144
    ) AS source_page
    WHERE source_page.scan_payload IS NOT NULL;

    IF returned_rows <> 2
       OR NOT page_complete
       OR revision_changed THEN
        RAISE EXCEPTION
            'a later scan changed the occurrence membership snapshot';
    END IF;

    UPDATE public.species_dictionary AS species
    SET family = 'RevisedSnapshotidae'
    WHERE species.id = test_species_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_OR(source_page.source_revision_changed),
        pg_catalog.BOOL_AND(
            source_page.scan_payload #>>
                '{species_dictionary,family}' = 'Snapshotidae'
        )
    INTO
        returned_rows,
        revision_changed,
        payload_returned
    FROM public.get_dwca_export_scan_batch(
        test_job_id,
        claim_token,
        'occurrence',
        NULL,
        100,
        262144
    ) AS source_page;

    IF returned_rows <> 2
       OR revision_changed
       OR NOT payload_returned THEN
        RAISE EXCEPTION
            'a live taxonomy change altered immutable occurrence DTOs';
    END IF;

    UPDATE public.species_dictionary AS species
    SET family = 'Snapshotidae'
    WHERE species.id = test_species_id;

    UPDATE public.scans AS scans
    SET geoprivacy = 'private'
    WHERE scans.id = second_scan_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_OR(source_page.source_revision_changed),
        pg_catalog.BOOL_AND(source_page.scan_payload IS NOT NULL)
    INTO
        returned_rows,
        revision_changed,
        payload_returned
    FROM public.get_dwca_export_scan_batch(
        test_job_id,
        claim_token,
        'occurrence',
        NULL,
        100,
        262144
    ) AS source_page;

    IF returned_rows <> 2
       OR revision_changed
       OR NOT payload_returned THEN
        RAISE EXCEPTION
            'personal snapshot eligibility incorrectly depended on geoprivacy';
    END IF;

    UPDATE public.scans AS scans
    SET geoprivacy = 'open'
    WHERE scans.id = second_scan_id;

    -- A conservation change is not an ordinary taxonomy edit: it changes the
    -- coordinate-redaction rule used by both export scopes and must revoke the
    -- snapshot before its old unprotected projection can be encoded.
    UPDATE public.species_dictionary AS species
    SET iucn_red_list_status = 'vulnerable'
    WHERE species.id = test_species_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_AND(source_page.source_revision_changed),
        pg_catalog.BOOL_OR(source_page.scan_payload IS NOT NULL)
    INTO
        returned_rows,
        revision_changed,
        payload_returned
    FROM public.get_dwca_export_scan_batch(
        test_job_id,
        claim_token,
        'occurrence',
        NULL,
        100,
        262144
    ) AS source_page;

    IF returned_rows <> 1
       OR NOT revision_changed
       OR payload_returned THEN
        RAISE EXCEPTION
            'a protected-species coordinate rule change escaped the live fence';
    END IF;

    UPDATE public.species_dictionary AS species
    SET iucn_red_list_status = NULL
    WHERE species.id = test_species_id;

    UPDATE internal.export_job_work AS work
    SET phase = 'multimedia'
    WHERE work.job_id = test_job_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_AND(source_page.page_complete),
        pg_catalog.BOOL_OR(source_page.source_revision_changed)
    INTO
        returned_rows,
        page_complete,
        revision_changed
    FROM public.get_dwca_export_scan_batch(
        test_job_id,
        claim_token,
        'multimedia',
        NULL,
        100,
        262144
    ) AS source_page
    WHERE source_page.scan_payload IS NOT NULL;

    IF returned_rows <> 2
       OR NOT page_complete
       OR revision_changed THEN
        RAISE EXCEPTION
            'the multimedia phase did not reuse immutable job membership';
    END IF;

    UPDATE public.scans AS scans
    SET image_storage_urls =
        ARRAY['https://media.example.invalid/snapshot-revised.webp']
    WHERE scans.id = first_scan_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_OR(source_page.source_revision_changed),
        pg_catalog.BOOL_AND(
            CASE
                WHEN source_page.scan_id = first_scan_id THEN
                    source_page.scan_payload -> 'image_storage_urls' =
                    pg_catalog.JSONB_BUILD_ARRAY(
                        'https://media.example.invalid/snapshot-first.webp'
                    )
                ELSE TRUE
            END
        )
    INTO
        returned_rows,
        revision_changed,
        payload_returned
    FROM public.get_dwca_export_scan_batch(
        test_job_id,
        claim_token,
        'multimedia',
        NULL,
        100,
        262144
    ) AS source_page;

    IF returned_rows <> 2
       OR revision_changed
       OR NOT payload_returned THEN
        RAISE EXCEPTION
            'a live media change altered immutable multimedia DTOs';
    END IF;

    UPDATE public.scans AS scans
    SET is_tombstoned = TRUE
    WHERE scans.id = first_scan_id;

    SELECT
        pg_catalog.COUNT(*)::INTEGER,
        pg_catalog.BOOL_AND(source_page.source_revision_changed),
        pg_catalog.BOOL_OR(source_page.scan_payload IS NOT NULL)
    INTO
        returned_rows,
        revision_changed,
        payload_returned
    FROM public.get_dwca_export_scan_batch(
        test_job_id,
        claim_token,
        'multimedia',
        NULL,
        100,
        262144
    ) AS source_page;

    IF returned_rows <> 1
       OR NOT revision_changed
       OR payload_returned THEN
        RAISE EXCEPTION
            'a later privacy eligibility revocation escaped the live fence';
    END IF;

    SELECT public.release_export_job_step(
        test_job_id,
        claim_token,
        'source_snapshot_changed',
        TRUE
    )
    INTO boolean_result;

    IF NOT boolean_result THEN
        RAISE EXCEPTION
            'the changed source snapshot could not become terminal';
    END IF;

    SELECT pg_catalog.COUNT(*)::INTEGER
    INTO returned_rows
    FROM internal.export_job_source_rows AS source_rows
    WHERE source_rows.job_id = test_job_id;

    SELECT source_state.purged_at IS NOT NULL
    INTO STRICT boolean_result
    FROM internal.export_job_source_state AS source_state
    WHERE source_state.job_id = test_job_id;

    IF returned_rows <> 0 OR NOT boolean_result THEN
        RAISE EXCEPTION
            'terminal completion retained immutable source DTOs';
    END IF;

    ALTER TABLE public.export_jobs
        ENABLE TRIGGER on_export_job_created;
END;
$test$;

SELECT extensions.pass(
    'DwC-A phases share immutable DTOs and reject later privacy revocation'
);
SELECT * FROM extensions.finish();
ROLLBACK;
