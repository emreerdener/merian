\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS plpgsql_check WITH SCHEMA extensions;
SELECT extensions.plan(1);

UPDATE internal.dwca_export_release_control
SET enabled = TRUE,
    updated_at = pg_catalog.NOW()
WHERE singleton;

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
VALUES
    (
        '00000000-0000-0000-0000-000000000000'::UUID,
        '00000000-0000-4000-8000-00000000d101'::UUID,
        'authenticated',
        'authenticated',
        'scan-finalization@naturebook.invalid',
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        '{"provider":"email","providers":["email"]}'::JSONB,
        '{}'::JSONB,
        pg_catalog.NOW(),
        pg_catalog.NOW(),
        FALSE
    ),
    (
        '00000000-0000-0000-0000-000000000000'::UUID,
        '00000000-0000-4000-8000-00000000d102'::UUID,
        'authenticated',
        'authenticated',
        'scan-finalization-target@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000d101',
    'scan-finalization@naturebook.invalid',
    'scan_final_d101',
    'Scan Finalization',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source;

DO $test$
DECLARE
    test_user_id UUID := '00000000-0000-4000-8000-00000000d101';
    reparent_user_id UUID := '00000000-0000-4000-8000-00000000d102';
    no_ledger_scan_id UUID := '00000000-0000-4000-8000-00000000d110';
    recovered_scan_id UUID := '00000000-0000-4000-8000-00000000d111';
    active_scan_id UUID := '00000000-0000-4000-8000-00000000d112';
    deletion_scan_id UUID := '00000000-0000-4000-8000-00000000d113';
    retention_due_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d114';
    retention_recent_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d115';
    retention_biological_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d116';
    retention_account_tombstone_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d117';
    cleanup_generation_job_id UUID :=
        '00000000-0000-4000-8000-00000000d121';
    stale_archive_claim UUID :=
        '00000000-0000-4000-8000-00000000d122';
    current_archive_claim UUID :=
        '00000000-0000-4000-8000-00000000d123';
    cleanup_id UUID := '00000000-0000-4000-8000-00000000d124';
    cleanup_claim_token UUID :=
        '00000000-0000-4000-8000-00000000d125';
    deletion_claim_token UUID :=
        '00000000-0000-4000-8000-00000000d128';
    stale_deletion_claim_token UUID :=
        '00000000-0000-4000-8000-00000000d129';
    current_cleanup_id UUID :=
        '00000000-0000-4000-8000-00000000d126';
    current_cleanup_claim_token UUID :=
        '00000000-0000-4000-8000-00000000d127';
    stale_archive_key TEXT;
    current_archive_key TEXT;
    recovery_payload JSONB;
    result_text TEXT;
    result_json JSONB;
    authorization_result JSONB;
    health_row RECORD;
    deletion_claim RECORD;
    attempt INTEGER;
    retention_requested_count INTEGER;
    allowed_authenticated_scan_update_columns CONSTANT TEXT[] := ARRAY[
        'custom_tags',
        'user_identification_override',
        'user_confirmed_identification',
        'confirmed_species_id',
        'user_review_state'
    ]::TEXT[];
BEGIN
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_download_grants',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_download_grants',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_download_grants',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.export_archive_cleanup_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.export_archive_cleanup_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.export_archive_cleanup_jobs',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.scan_deletion_tombstones',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.scan_deletion_tombstones',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.scan_deletion_tombstones',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role can inspect private lifecycle state';
    END IF;

    -- Column privilege checks also report table-level privileges. Assert that
    -- broad table mutation is absent first, then compare effective column
    -- mutation privileges with the exact rolling-client compatibility
    -- allowlist.
    IF pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'INSERT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'UPDATE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'TRUNCATE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'REFERENCES'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'TRIGGER'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'MAINTAIN'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'INSERT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'UPDATE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'TRUNCATE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'REFERENCES'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'TRIGGER'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'MAINTAIN'
    ) THEN
        RAISE EXCEPTION 'an API role has a broad scan table mutation privilege';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.table_privileges AS privileges
        WHERE privileges.table_schema = 'public'
          AND privileges.table_name = 'scans'
          AND privileges.grantee = 'PUBLIC'
    ) OR EXISTS (
        SELECT 1
        FROM information_schema.column_privileges AS privileges
        WHERE privileges.table_schema = 'public'
          AND privileges.table_name = 'scans'
          AND privileges.grantee = 'PUBLIC'
    ) THEN
        RAISE EXCEPTION 'PUBLIC retains a direct scan privilege';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attributes
        WHERE attributes.attrelid = 'public.scans'::REGCLASS
          AND attributes.attnum > 0
          AND NOT attributes.attisdropped
          AND (
                pg_catalog.HAS_COLUMN_PRIVILEGE(
                    'anon',
                    'public.scans',
                    attributes.attname,
                    'INSERT'
                )
                OR pg_catalog.HAS_COLUMN_PRIVILEGE(
                    'anon',
                    'public.scans',
                    attributes.attname,
                    'UPDATE'
                )
                OR pg_catalog.HAS_COLUMN_PRIVILEGE(
                    'anon',
                    'public.scans',
                    attributes.attname,
                    'REFERENCES'
                )
          )
    ) THEN
        RAISE EXCEPTION 'anon can mutate or reference a scan column';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attributes
        WHERE attributes.attrelid = 'public.scans'::REGCLASS
          AND attributes.attnum > 0
          AND NOT attributes.attisdropped
          AND (
                pg_catalog.HAS_COLUMN_PRIVILEGE(
                    'authenticated',
                    'public.scans',
                    attributes.attname,
                    'INSERT'
                )
                OR pg_catalog.HAS_COLUMN_PRIVILEGE(
                    'authenticated',
                    'public.scans',
                    attributes.attname,
                    'REFERENCES'
                )
                OR (
                    attributes.attname::TEXT <> ALL (
                        allowed_authenticated_scan_update_columns
                    )
                    AND pg_catalog.HAS_COLUMN_PRIVILEGE(
                        'authenticated',
                        'public.scans',
                        attributes.attname,
                        'UPDATE'
                    )
                )
          )
    ) THEN
        RAISE EXCEPTION
            'authenticated can mutate or reference an unexpected scan column';
    END IF;

    IF NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'public.scans',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'public.scans',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'SELECT'
    ) THEN
        RAISE EXCEPTION 'an API role cannot perform its required scan read';
    END IF;

    IF NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'INSERT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'UPDATE'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'TRUNCATE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'REFERENCES'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'TRIGGER'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.scans',
        'MAINTAIN'
    ) THEN
        RAISE EXCEPTION 'service_role scan privileges are not exact canonical CRUD';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.UNNEST(
            allowed_authenticated_scan_update_columns
        ) AS allowed(column_name)
        WHERE NOT pg_catalog.HAS_COLUMN_PRIVILEGE(
            'authenticated',
            'public.scans',
            allowed.column_name,
            'UPDATE'
        )
    ) THEN
        RAISE EXCEPTION 'the rolling review/tag column grant is incomplete';
    END IF;

    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.update_owned_scan_custom_tags(uuid,text[])',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.update_owned_scan_identification_review(uuid,text,boolean,uuid,public.user_review_state)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.update_owned_scan_custom_tags(uuid,text[])',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.update_owned_scan_identification_review(uuid,text,boolean,uuid,public.user_review_state)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'the owner-only scan mutation RPC ACL is incorrect';
    END IF;

    IF NOT (
        SELECT class_row.relrowsecurity
        FROM pg_catalog.pg_class AS class_row
        WHERE class_row.oid =
            'internal.export_download_grants'::REGCLASS
    ) OR NOT (
        SELECT class_row.relrowsecurity
        FROM pg_catalog.pg_class AS class_row
        WHERE class_row.oid =
            'internal.export_archive_cleanup_jobs'::REGCLASS
    ) OR NOT (
        SELECT class_row.relrowsecurity
        FROM pg_catalog.pg_class AS class_row
        WHERE class_row.oid =
            'internal.scan_deletion_tombstones'::REGCLASS
    ) THEN
        RAISE EXCEPTION 'a private lifecycle table does not have RLS enabled';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.authorize_dwca_archive_download(text,text)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.recover_missing_owned_scan(uuid,uuid,jsonb)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_scan_deletion(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.request_nonbiological_scan_retention_deletions(integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.request_nonbiological_scan_retention_deletions(integer)',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.request_nonbiological_scan_retention_deletions(integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        'public.claim_scan_deletion_jobs(uuid,integer,integer)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_scan_deletion_health()',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.lock_dwca_export_generation(uuid)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'a public API role can invoke an internal fence';
    END IF;

    -- plpgsql_check requires a valid relation OID for trigger routines.
    -- Keep one typed registry so every new trigger must declare its analysis
    -- relation instead of being accidentally checked as an ordinary routine.
    IF EXISTS (
        SELECT 1
        FROM (
            VALUES
                (
                    'public.update_owned_scan_custom_tags(uuid,text[])'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.update_owned_scan_identification_review(uuid,text,boolean,uuid,public.user_review_state)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.request_scan_deletion(uuid,uuid)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.request_nonbiological_scan_retention_deletions(integer)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.claim_scan_deletion_jobs(uuid,integer,integer)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.release_scan_deletion_job(uuid,uuid,uuid,text)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.get_scan_deletion_health()'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.complete_scan_deletion(uuid,uuid)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'internal.reject_deleted_scan_generation_mutation()'
                        ::REGPROCEDURE::OID,
                    'public.scans'::REGCLASS::OID
                ),
                (
                    'internal.record_deleted_scan_generation()'
                        ::REGPROCEDURE::OID,
                    'public.scans'::REGCLASS::OID
                ),
                (
                    'internal.unlink_deleted_user_scan_tombstones()'
                        ::REGPROCEDURE::OID,
                    'public.users'::REGCLASS::OID
                ),
                (
                    'public.claim_scan_ingestion_job(text,uuid,text,jsonb,jsonb,uuid[],text,integer)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.recover_missing_owned_scan(uuid,uuid,jsonb)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.complete_scan_ingestion_finalization(uuid,uuid,jsonb,text[])'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'internal.enforce_scan_ingestion_completion_fence()'
                        ::REGPROCEDURE::OID,
                    'public.scan_ingestion_jobs'::REGCLASS::OID
                ),
                (
                    'public.authorize_dwca_archive_download(text,text)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.check_dwca_export_source_fence(uuid,uuid,text)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'public.claim_dwca_archive_cleanup_jobs(uuid,integer,integer)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'internal.lock_dwca_export_generation(uuid)'
                        ::REGPROCEDURE::OID,
                    0::OID
                ),
                (
                    'internal.revoke_completed_dwca_exports_for_scan()'
                        ::REGPROCEDURE::OID,
                    'public.scans'::REGCLASS::OID
                ),
                (
                    'internal.revoke_completed_dwca_exports_for_species()'
                        ::REGPROCEDURE::OID,
                    'public.species_dictionary'::REGCLASS::OID
                ),
                (
                    'public.complete_dwca_archive_cleanup_job(uuid,uuid)'
                        ::REGPROCEDURE::OID,
                    0::OID
                )
        ) AS checked(function_oid, trigger_relation_oid)
        CROSS JOIN LATERAL extensions.plpgsql_check_function_tb(
            checked.function_oid,
            checked.trigger_relation_oid
        ) AS issue
        WHERE issue.level IN ('error', 'fatal')
    ) THEN
        RAISE EXCEPTION 'a new privileged routine fails static validation';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgrelid =
            'public.scan_ingestion_jobs'::REGCLASS
          AND trigger_row.tgname =
              'enforce_scan_ingestion_completion_fence'
          AND NOT trigger_row.tgisinternal
    ) THEN
        RAISE EXCEPTION 'scan completion fence trigger is missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgrelid = 'public.scans'::REGCLASS
          AND trigger_row.tgname =
              'revoke_completed_dwca_exports_for_scan'
          AND NOT trigger_row.tgisinternal
    ) OR NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE trigger_row.tgrelid =
            'public.species_dictionary'::REGCLASS
          AND trigger_row.tgname =
              'revoke_completed_dwca_exports_for_species'
          AND NOT trigger_row.tgisinternal
    ) THEN
        RAISE EXCEPTION 'completed DwCA privacy revocation trigger is missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_trigger AS trigger_row
        WHERE (
            (
                trigger_row.tgrelid = 'public.scans'::REGCLASS
                AND trigger_row.tgname IN (
                    'invalidate_dwca_exports_for_scan',
                    'invalidate_dwca_exports_for_scan_truncate'
                )
            )
            OR (
                trigger_row.tgrelid =
                    'public.species_dictionary'::REGCLASS
                AND trigger_row.tgname IN (
                    'invalidate_dwca_exports_for_species',
                    'invalidate_dwca_exports_for_species_truncate'
                )
            )
        )
          AND NOT trigger_row.tgisinternal
    ) THEN
        RAISE EXCEPTION 'a source-state-first DwCA trigger remains active';
    END IF;

    recovery_payload := pg_catalog.JSONB_BUILD_OBJECT(
        'id', recovered_scan_id,
        'user_id', test_user_id,
        'species_id', NULL,
        'confirmed_species_id', NULL,
        'image_storage_urls', pg_catalog.JSONB_BUILD_ARRAY(),
        'timestamp', pg_catalog.CLOCK_TIMESTAMP(),
        'gps_lat_exact', 41.88,
        'gps_long_exact', -87.63,
        'gps_elevation', NULL,
        'geoprivacy', 'open',
        'weather_condition', NULL,
        'weather_temperature_f', NULL,
        'ai_confidence_score', 0.9,
        'ecology_type', 'wild',
        'is_invasive', FALSE,
        'invasive_status_region', NULL,
        'invasive_rationale', NULL,
        'invasive_confidence', NULL,
        'is_live_capture', TRUE,
        'is_biological_subject', TRUE,
        'ai_reasoning', NULL,
        'semantic_location', NULL,
        'public_location_label', 'Chicago, Illinois',
        'inference_tier', 'free',
        'image_quality_score', NULL,
        'user_identification_override', NULL,
        'user_confirmed_identification', FALSE,
        'user_review_state', 'unreviewed'
    );

    SELECT public.recover_missing_owned_scan(
        no_ledger_scan_id,
        test_user_id,
        pg_catalog.JSONB_SET(
            recovery_payload,
            '{id}',
            pg_catalog.TO_JSONB(no_ledger_scan_id)
        )
    )
    INTO STRICT result_text;
    IF result_text <> 'deferred'
       OR EXISTS (
            SELECT 1
            FROM public.scans AS scans
            WHERE scans.id = no_ledger_scan_id
       ) THEN
        RAISE EXCEPTION 'no-ledger client recovery did not fail closed';
    END IF;

    INSERT INTO public.scan_ingestion_jobs (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        terminal_reason_code,
        completed_at
    )
    VALUES (
        recovered_scan_id::TEXT,
        test_user_id,
        'identify-multimodal',
        'failed_terminal',
        'server_replay_limit_reached',
        'replay_exhausted',
        pg_catalog.NOW()
    );

    SELECT public.recover_missing_owned_scan(
        recovered_scan_id,
        test_user_id,
        recovery_payload
    )
    INTO STRICT result_text;
    IF result_text <> 'recovered' THEN
        RAISE EXCEPTION 'atomic owner recovery did not insert its row';
    END IF;

    SELECT (
        public.claim_scan_ingestion_job(
            recovered_scan_id::TEXT,
            test_user_id,
            'identify'
        )
    ).status
    INTO STRICT result_text;
    IF result_text <> 'complete' THEN
        RAISE EXCEPTION
            'compatibility claim replaced a completed recovery generation';
    END IF;

    SELECT public.begin_scan_ingestion(
        recovered_scan_id::TEXT,
        test_user_id,
        'identify-multimodal',
        '{}'::JSONB
    )
    INTO STRICT result_json;
    IF (result_json ->> 'already_complete')::BOOLEAN IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'a recovered scan allowed a later provider claim';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'request.jwt.claims',
        pg_catalog.JSONB_BUILD_OBJECT(
            'sub',
            test_user_id,
            'role',
            'authenticated'
        )::TEXT,
        TRUE
    );
    PERFORM public.update_owned_scan_custom_tags(
        recovered_scan_id,
        ARRAY['backyard', 'summer']::TEXT[]
    );
    PERFORM public.update_owned_scan_identification_review(
        recovered_scan_id,
        NULL,
        TRUE,
        NULL,
        'ai_confirmed'::public.user_review_state
    );
    IF NOT EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = recovered_scan_id
          AND scans.custom_tags =
              ARRAY['backyard', 'summer']::TEXT[]
          AND scans.user_confirmed_identification
          AND scans.user_review_state =
              'ai_confirmed'::public.user_review_state
    ) THEN
        RAISE EXCEPTION 'owner-derived scan mutation RPC did not persist';
    END IF;

    PERFORM pg_catalog.SET_CONFIG(
        'request.jwt.claims',
        pg_catalog.JSONB_BUILD_OBJECT(
            'sub',
            reparent_user_id,
            'role',
            'authenticated'
        )::TEXT,
        TRUE
    );
    BEGIN
        PERFORM public.update_owned_scan_custom_tags(
            recovered_scan_id,
            ARRAY['foreign-write']::TEXT[]
        );
        RAISE EXCEPTION 'foreign caller updated an owner scan';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN NULL;
    END;
    PERFORM pg_catalog.SET_CONFIG(
        'request.jwt.claims',
        '{}'::JSONB::TEXT,
        TRUE
    );

    SELECT public.begin_scan_ingestion(
        active_scan_id::TEXT,
        test_user_id,
        'identify-multimodal',
        '{}'::JSONB
    )
    INTO STRICT result_json;

    BEGIN
        UPDATE public.scan_ingestion_jobs AS jobs
        SET status = 'complete',
            completed_at = pg_catalog.NOW()
        WHERE jobs.scan_id = active_scan_id::TEXT
          AND jobs.user_id = test_user_id;
        RAISE EXCEPTION
            'direct ledger completion bypassed media finalization';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;

    SELECT public.recover_missing_owned_scan(
        active_scan_id,
        test_user_id,
        pg_catalog.JSONB_SET(
            recovery_payload,
            '{id}',
            pg_catalog.TO_JSONB(active_scan_id)
        )
    )
    INTO STRICT result_text;
    IF result_text <> 'deferred' THEN
        RAISE EXCEPTION 'owner recovery bypassed active ingestion';
    END IF;

    SELECT public.recover_missing_owned_scan(
        deletion_scan_id,
        test_user_id,
        pg_catalog.JSONB_SET(
            recovery_payload,
            '{id}',
            pg_catalog.TO_JSONB(deletion_scan_id)
        )
    )
    INTO STRICT result_text;
    IF result_text <> 'recovered' THEN
        RAISE EXCEPTION 'deletion fixture recovery failed';
    END IF;

    SELECT public.request_scan_deletion(
        deletion_scan_id,
        test_user_id
    )
    INTO STRICT result_text;
    IF result_text <> 'accepted' THEN
        RAISE EXCEPTION 'scan deletion intent was not durably accepted';
    END IF;

    SELECT *
    INTO STRICT deletion_claim
    FROM public.claim_scan_deletion_jobs(
        deletion_claim_token,
        1,
        120
    );
    IF deletion_claim.scan_id <> deletion_scan_id
       OR deletion_claim.user_id <> test_user_id
       OR deletion_claim.attempt_count <> 1 THEN
        RAISE EXCEPTION 'scan deletion worker claim was malformed';
    END IF;

    IF public.release_scan_deletion_job(
        deletion_scan_id,
        test_user_id,
        stale_deletion_claim_token,
        'stale_release'
    ) THEN
        RAISE EXCEPTION 'a stale scan deletion worker cleared a newer lease';
    END IF;

    SELECT public.recover_missing_owned_scan(
        deletion_scan_id,
        test_user_id,
        pg_catalog.JSONB_SET(
            recovery_payload,
            '{id}',
            pg_catalog.TO_JSONB(deletion_scan_id)
        )
    )
    INTO STRICT result_text;
    IF result_text <> 'deleted' THEN
        RAISE EXCEPTION 'pending deletion allowed owner-row recovery';
    END IF;

    BEGIN
        UPDATE public.scans AS scans
        SET ai_reasoning = 'delayed provider callback'
        WHERE scans.id = deletion_scan_id;
        RAISE EXCEPTION 'pending deletion allowed stale scan mutation';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;

    IF NOT public.complete_scan_deletion(
        deletion_scan_id,
        test_user_id
    ) OR EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = deletion_scan_id
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = deletion_scan_id
          AND tombstones.user_id IS NULL
          AND tombstones.completed_at IS NOT NULL
          AND tombstones.claim_token IS NULL
          AND tombstones.lease_expires_at IS NULL
    ) THEN
        RAISE EXCEPTION 'verified scan deletion did not complete';
    END IF;

    SELECT public.recover_missing_owned_scan(
        deletion_scan_id,
        test_user_id,
        pg_catalog.JSONB_SET(
            recovery_payload,
            '{id}',
            pg_catalog.TO_JSONB(deletion_scan_id)
        )
    )
    INTO STRICT result_text;
    IF result_text <> 'deleted' THEN
        RAISE EXCEPTION 'completed deletion allowed scan resurrection';
    END IF;

    INSERT INTO public.scans (
        id,
        user_id,
        ai_confidence_score,
        timestamp,
        is_biological_subject
    )
    VALUES
        (
            retention_due_scan_id,
            test_user_id,
            0.5,
            pg_catalog.NOW()
                - pg_catalog.MAKE_INTERVAL(days => 31),
            FALSE
        ),
        (
            retention_recent_scan_id,
            test_user_id,
            0.5,
            pg_catalog.NOW()
                - pg_catalog.MAKE_INTERVAL(days => 29),
            FALSE
        ),
        (
            retention_biological_scan_id,
            test_user_id,
            0.5,
            pg_catalog.NOW()
                - pg_catalog.MAKE_INTERVAL(days => 31),
            TRUE
        ),
        (
            retention_account_tombstone_scan_id,
            test_user_id,
            0.5,
            pg_catalog.NOW()
                - pg_catalog.MAKE_INTERVAL(days => 31),
            FALSE
        );
    UPDATE public.scans AS scans
    SET is_tombstoned = TRUE
    WHERE scans.id = retention_account_tombstone_scan_id;

    SELECT public.request_nonbiological_scan_retention_deletions(10)
    INTO STRICT retention_requested_count;
    IF retention_requested_count <> 1
       OR NOT EXISTS (
            SELECT 1
            FROM internal.scan_deletion_tombstones AS tombstones
            WHERE tombstones.scan_id = retention_due_scan_id
              AND tombstones.user_id = test_user_id
              AND tombstones.completed_at IS NULL
       ) OR EXISTS (
            SELECT 1
            FROM internal.scan_deletion_tombstones AS tombstones
            WHERE tombstones.scan_id IN (
                retention_recent_scan_id,
                retention_biological_scan_id,
                retention_account_tombstone_scan_id
            )
       ) OR NOT EXISTS (
            SELECT 1
            FROM public.scans AS scans
            WHERE scans.id = retention_due_scan_id
       ) THEN
        RAISE EXCEPTION
            'retention selection did not fence only the eligible generation';
    END IF;

    SELECT public.request_nonbiological_scan_retention_deletions(10)
    INTO STRICT retention_requested_count;
    IF retention_requested_count <> 0 THEN
        RAISE EXCEPTION 'retention selection duplicated pending erasure work';
    END IF;

    SELECT *
    INTO STRICT health_row
    FROM public.get_scan_deletion_health();
    IF health_row.pending_count < 0
       OR health_row.processing_count < 0
       OR health_row.expired_lease_count < 0 THEN
        RAISE EXCEPTION 'scan deletion health returned invalid counts';
    END IF;

    BEGIN
        UPDATE public.scan_ingestion_jobs AS jobs
        SET user_id = reparent_user_id
        WHERE jobs.scan_id = recovered_scan_id::TEXT
          AND jobs.user_id = test_user_id;
        RAISE EXCEPTION
            'completed ingestion evidence was arbitrarily reassigned';
    EXCEPTION
        WHEN SQLSTATE '55000' THEN NULL;
    END;

    PERFORM pg_catalog.SET_CONFIG(
        'internal.ai_usage_reparent_source',
        test_user_id::TEXT,
        TRUE
    );
    PERFORM pg_catalog.SET_CONFIG(
        'internal.ai_usage_reparent_target',
        reparent_user_id::TEXT,
        TRUE
    );
    PERFORM pg_catalog.SET_CONFIG(
        'internal.ai_usage_reparenting',
        'on',
        TRUE
    );
    UPDATE public.scan_ingestion_jobs AS jobs
    SET user_id = reparent_user_id
    WHERE jobs.scan_id = recovered_scan_id::TEXT
      AND jobs.user_id = test_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION
            'atomic ghost-profile merge markers did not permit reparenting';
    END IF;
    PERFORM pg_catalog.SET_CONFIG(
        'internal.ai_usage_reparenting',
        'off',
        TRUE
    );

    SELECT public.authorize_dwca_archive_download(
        pg_catalog.REPEAT('a', 64),
        pg_catalog.REPEAT('b', 64)
    )
    INTO STRICT authorization_result;
    IF authorization_result ->> 'status' <> 'not_found' THEN
        RAISE EXCEPTION 'an unknown DwCA capability was not rejected';
    END IF;

    FOR attempt IN 1..60 LOOP
        SELECT public.authorize_dwca_archive_download(
            pg_catalog.REPEAT('a', 64),
            pg_catalog.REPEAT('b', 64)
        )
        INTO STRICT authorization_result;
    END LOOP;
    IF authorization_result ->> 'status' <> 'rate_limited' THEN
        RAISE EXCEPTION 'distributed DwCA download rate limiting failed';
    END IF;

    stale_archive_key := 'exports/' || test_user_id::TEXT || '/'
        || cleanup_generation_job_id::TEXT || '/'
        || stale_archive_claim::TEXT || '.zip';
    current_archive_key := 'exports/' || test_user_id::TEXT || '/'
        || cleanup_generation_job_id::TEXT || '/'
        || current_archive_claim::TEXT || '.zip';

    INSERT INTO public.export_jobs (
        id,
        user_id,
        export_scope,
        include_precise_coordinates
    )
    VALUES (
        cleanup_generation_job_id,
        test_user_id,
        'personal',
        FALSE
    );

    ALTER TABLE public.export_jobs
        DISABLE TRIGGER enforce_export_job_update;
    UPDATE public.export_jobs AS jobs
    SET status = 'completed',
        archive_object_key = current_archive_key,
        completed_at = pg_catalog.NOW()
    WHERE jobs.id = cleanup_generation_job_id;
    ALTER TABLE public.export_jobs
        ENABLE TRIGGER enforce_export_job_update;

    INSERT INTO internal.export_download_grants (
        job_id,
        token_sha256,
        expires_at
    )
    VALUES (
        cleanup_generation_job_id,
        pg_catalog.REPEAT('c', 64),
        pg_catalog.NOW() + INTERVAL '1 hour'
    );

    INSERT INTO internal.export_archive_cleanup_jobs (
        id,
        job_id,
        object_key,
        reason_code,
        status,
        attempt_count,
        claim_token,
        lease_expires_at
    )
    VALUES (
        cleanup_id,
        cleanup_generation_job_id,
        stale_archive_key,
        'stale_attempt',
        'processing',
        1,
        cleanup_claim_token,
        pg_catalog.NOW() + INTERVAL '1 minute'
    );

    IF NOT public.complete_dwca_archive_cleanup_job(
        cleanup_id,
        cleanup_claim_token
    ) THEN
        RAISE EXCEPTION 'stale archive cleanup could not complete';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM internal.export_download_grants AS grants
        WHERE grants.job_id = cleanup_generation_job_id
          AND (
              grants.revoked_at IS NOT NULL
              OR grants.cleaned_at IS NOT NULL
          )
    ) OR EXISTS (
        SELECT 1
        FROM internal.export_job_source_state AS source_state
        WHERE source_state.job_id = cleanup_generation_job_id
          AND source_state.purged_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'stale archive cleanup invalidated a replacement grant';
    END IF;

    INSERT INTO internal.export_archive_cleanup_jobs (
        id,
        job_id,
        object_key,
        reason_code,
        status,
        attempt_count,
        claim_token,
        lease_expires_at
    )
    VALUES (
        current_cleanup_id,
        cleanup_generation_job_id,
        current_archive_key,
        'grant_revoked',
        'processing',
        1,
        current_cleanup_claim_token,
        pg_catalog.NOW() + INTERVAL '1 minute'
    );

    IF NOT public.complete_dwca_archive_cleanup_job(
        current_cleanup_id,
        current_cleanup_claim_token
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.export_download_grants AS grants
        WHERE grants.job_id = cleanup_generation_job_id
          AND grants.revoked_at IS NOT NULL
          AND grants.cleaned_at IS NOT NULL
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.export_job_source_state AS source_state
        WHERE source_state.job_id = cleanup_generation_job_id
          AND source_state.purged_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'current archive cleanup did not retire its grant and snapshot';
    END IF;

    SELECT *
    INTO STRICT health_row
    FROM public.get_dwca_archive_cleanup_health();
    IF health_row.pending_count < 0
       OR health_row.expired_lease_count < 0 THEN
        RAISE EXCEPTION 'DwCA cleanup health returned invalid counts';
    END IF;
END;
$test$;

SELECT extensions.pass(
    'scan recovery/finalization and DwCA download/cleanup fences are private, static-valid, and fail closed'
);
SELECT * FROM extensions.finish();
ROLLBACK;
