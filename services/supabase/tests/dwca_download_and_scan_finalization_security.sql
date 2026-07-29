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
    media_abandoned_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d118';
    unproven_media_abandoned_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d130';
    later_policy_overwrite_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d131';
    moderation_overwrite_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d132';
    replay_policy_overwrite_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d134';
    unrelated_old_quota_request_id UUID :=
        '00000000-0000-4000-8000-00000000d135';
    structured_media_abandoned_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d136';
    moderation_pipeline_overwrite_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d137';
    post_cutoff_unstructured_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d138';
    pre_safety_unstructured_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d139';
    incomplete_structured_safety_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d140';
    legacy_moderation_message_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d141';
    wrong_endpoint_recovery_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d142';
    active_replay_recovery_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d143';
    invalid_timestamp_recovery_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d144';
    policy_rejected_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d119';
    unknown_terminal_scan_id UUID :=
        '00000000-0000-4000-8000-00000000d120';
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
    legacy_unstructured_before TIMESTAMPTZ;
    recovery_payload JSONB;
    result_text TEXT;
    result_json JSONB;
    authorization_result JSONB;
    health_row RECORD;
    deletion_claim RECORD;
    scan_deletion_completed BOOLEAN;
    current_archive_cleanup_completed BOOLEAN;
    blocked_recovery_scan_id UUID;
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
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.scan_recovery_evidence_control',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.scan_recovery_evidence_control',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.scan_recovery_evidence_control',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'anon',
        'internal.scan_recovery_legacy_dead_letters',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'authenticated',
        'internal.scan_recovery_legacy_dead_letters',
        'SELECT'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'internal.scan_recovery_legacy_dead_letters',
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
    ) OR NOT (
        SELECT class_row.relrowsecurity
        FROM pg_catalog.pg_class AS class_row
        WHERE class_row.oid =
            'internal.scan_recovery_evidence_control'::REGCLASS
    ) OR NOT (
        SELECT class_row.relrowsecurity
        FROM pg_catalog.pg_class AS class_row
        WHERE class_row.oid =
            'internal.scan_recovery_legacy_dead_letters'::REGCLASS
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
        'anon',
        'public.get_media_abandoned_scan_recovery_proofs(uuid,uuid[])',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        'public.get_media_abandoned_scan_recovery_proofs(uuid,uuid[])',
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'public.get_media_abandoned_scan_recovery_proofs(uuid,uuid[])',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.media_abandoned_scan_has_recovery_proof(uuid,uuid)',
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        'internal.derive_ai_quota_request_id(uuid,text)',
        'EXECUTE'
    ) OR NOT EXISTS (
        SELECT 1
        FROM internal.privileged_routine_grants AS grants
        WHERE grants.role_name = 'service_role'
          AND grants.routine_signature =
              'public.get_media_abandoned_scan_recovery_proofs(uuid,uuid[])'
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

    -- plpgsql_check accepts only PL/pgSQL routines and requires a valid
    -- relation OID for trigger routines. LANGUAGE SQL helpers are exercised
    -- by the direct behavioral assertions below instead. Keep one typed
    -- registry so every new PL/pgSQL trigger must declare its analysis
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
                    'public.get_media_abandoned_scan_recovery_proofs(uuid,uuid[])'
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

    SELECT controls.legacy_unstructured_before
    INTO STRICT legacy_unstructured_before
    FROM internal.scan_recovery_evidence_control AS controls
    WHERE controls.singleton;

    INSERT INTO public.scan_ingestion_jobs (
        scan_id,
        user_id,
        endpoint,
        status,
        stage,
        terminal_reason_code,
        completed_at
    )
    VALUES
        (
            media_abandoned_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            policy_rejected_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'moderation_rejected',
            'content_policy_rejected',
            pg_catalog.NOW()
        ),
        (
            unknown_terminal_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'legacy_terminal_failure',
            'legacy_terminal_unknown',
            pg_catalog.NOW()
        ),
        (
            unproven_media_abandoned_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            later_policy_overwrite_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            moderation_overwrite_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            replay_policy_overwrite_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            structured_media_abandoned_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            moderation_pipeline_overwrite_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            post_cutoff_unstructured_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            pre_safety_unstructured_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            incomplete_structured_safety_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            legacy_moderation_message_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            wrong_endpoint_recovery_scan_id::TEXT,
            test_user_id,
            'identify',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            active_replay_recovery_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            invalid_timestamp_recovery_scan_id::TEXT,
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        ),
        (
            'legacy-malformed-scan-id',
            test_user_id,
            'identify-multimodal',
            'failed_terminal',
            'media_reconciliation_abandoned',
            'media_reconciliation_abandoned',
            pg_catalog.NOW()
        );

    INSERT INTO internal.ai_quota_reservations (
        user_id,
        operation,
        request_id,
        state,
        lease_expires_at,
        model,
        effective_plan,
        effective_tier,
        subscription_tier,
        trial_active,
        entitlement_version,
        policy_version,
        failed_at,
        committed_at
    )
    VALUES
        (
            test_user_id,
            'scan_identification',
            media_abandoned_scan_id,
            'committed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            legacy_unstructured_before - INTERVAL '2 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            later_policy_overwrite_scan_id,
            'committed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            legacy_unstructured_before - INTERVAL '1 minute'
        ),
        (
            test_user_id,
            'scan_identification',
            moderation_overwrite_scan_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            legacy_unstructured_before - INTERVAL '2 minutes',
            legacy_unstructured_before - INTERVAL '3 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            replay_policy_overwrite_scan_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            legacy_unstructured_before - INTERVAL '4 minutes',
            legacy_unstructured_before - INTERVAL '5 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            internal.derive_ai_quota_request_id(
                replay_policy_overwrite_scan_id,
                'scan-ingestion-replay:1'
            ),
            'committed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            legacy_unstructured_before - INTERVAL '1 minute'
        ),
        (
            test_user_id,
            'scan_identification',
            internal.derive_ai_quota_request_id(
                replay_policy_overwrite_scan_id,
                'scan-ingestion-replay:2'
            ),
            'refunded',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            NULL
        ),
        (
            test_user_id,
            'scan_identification',
            unrelated_old_quota_request_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            pg_catalog.NOW() - INTERVAL '31 days',
            pg_catalog.NOW() - INTERVAL '31 days 1 second'
        ),
        (
            test_user_id,
            'scan_identification',
            structured_media_abandoned_scan_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '1 second',
            pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '2 seconds'
        ),
        (
            test_user_id,
            'scan_identification',
            moderation_pipeline_overwrite_scan_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            legacy_unstructured_before - INTERVAL '2 minutes',
            legacy_unstructured_before - INTERVAL '3 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            post_cutoff_unstructured_scan_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            legacy_unstructured_before - INTERVAL '2 minutes',
            legacy_unstructured_before - INTERVAL '3 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            pre_safety_unstructured_scan_id,
            'committed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            legacy_unstructured_before - INTERVAL '2 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            incomplete_structured_safety_scan_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '1 second',
            pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '2 seconds'
        ),
        (
            test_user_id,
            'scan_identification',
            legacy_moderation_message_scan_id,
            'committed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            legacy_unstructured_before - INTERVAL '2 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            wrong_endpoint_recovery_scan_id,
            'committed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            legacy_unstructured_before - INTERVAL '2 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            active_replay_recovery_scan_id,
            'committed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            legacy_unstructured_before - INTERVAL '2 minutes'
        ),
        (
            test_user_id,
            'scan_identification',
            internal.derive_ai_quota_request_id(
                active_replay_recovery_scan_id,
                'scan-ingestion-replay:1'
            ),
            'reserved',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            NULL,
            NULL
        ),
        (
            test_user_id,
            'scan_identification',
            invalid_timestamp_recovery_scan_id,
            'failed',
            pg_catalog.NOW() + INTERVAL '10 minutes',
            'gemini-2.5-flash',
            'free',
            'free',
            'free',
            FALSE,
            1,
            1,
            legacy_unstructured_before - INTERVAL '3 minutes',
            legacy_unstructured_before - INTERVAL '2 minutes'
        );

    INSERT INTO public.scan_ingestion_intents (
        scan_id,
        user_id,
        endpoint,
        request_payload,
        replay_attempt_count
    )
    VALUES (
        replay_policy_overwrite_scan_id::TEXT,
        test_user_id,
        'identify-multimodal',
        '{}'::JSONB,
        2
    );

    IF internal.derive_ai_quota_request_id(
        media_abandoned_scan_id,
        'scan-ingestion-replay:1'
    ) IS DISTINCT FROM
        '5bd14510-252c-85f2-adbb-7ae15e071de5'::UUID THEN
        RAISE EXCEPTION
            'SQL AI request-id derivation diverged from the Edge UUIDv8 contract';
    END IF;

    INSERT INTO public.scan_media_assets (
        client_scan_id,
        upload_session_id,
        user_id,
        kind,
        role,
        status,
        source,
        storage_key,
        order_index,
        failure_reason
    )
    VALUES
        (
            moderation_overwrite_scan_id,
            '00000000-0000-4000-8000-00000000d133'::UUID,
            test_user_id,
            'image',
            'display',
            'failed',
            'capture_upload',
            'staging/00000000-0000-4000-8000-00000000d101/'
                || moderation_overwrite_scan_id::TEXT
                || '_policy.webp',
            0,
            'moderation_rejected'
        ),
        (
            moderation_pipeline_overwrite_scan_id,
            '00000000-0000-4000-8000-00000000d137'::UUID,
            test_user_id,
            'image',
            'display',
            'failed',
            'capture_upload',
            'staging/00000000-0000-4000-8000-00000000d101/'
                || moderation_pipeline_overwrite_scan_id::TEXT
                || '_pipeline.webp',
            0,
            'moderation_pipeline_error'
        );

    INSERT INTO public.failed_scan_ingestions (
        scan_id,
        user_id,
        error_message,
        failed_at,
        quota_reservation_id,
        quota_request_id,
        failure_kind,
        provider_result_validated,
        identify_safety_evaluation_completed
    )
    VALUES
        (
            media_abandoned_scan_id::TEXT,
            test_user_id,
            'legacy post-result scan finalization failed before owner row commit',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            later_policy_overwrite_scan_id::TEXT,
            test_user_id,
            'older post-result failure preceded a permanent provider decision',
            legacy_unstructured_before - INTERVAL '2 minutes',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            moderation_overwrite_scan_id::TEXT,
            test_user_id,
            'older post-result failure preceded a moderation decision',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            replay_policy_overwrite_scan_id::TEXT,
            test_user_id,
            'older post-result failure preceded a replay policy decision',
            legacy_unstructured_before - INTERVAL '3 minutes',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            structured_media_abandoned_scan_id::TEXT,
            test_user_id,
            'structured post-result durability failure',
            pg_catalog.CLOCK_TIMESTAMP(),
            (
                SELECT reservations.id
                FROM internal.ai_quota_reservations AS reservations
                WHERE reservations.user_id = test_user_id
                  AND reservations.operation = 'scan_identification'
                  AND reservations.request_id =
                      structured_media_abandoned_scan_id
            ),
            structured_media_abandoned_scan_id,
            'post_result_scan_durability_failure',
            TRUE,
            TRUE
        ),
        (
            moderation_pipeline_overwrite_scan_id::TEXT,
            test_user_id,
            'legacy moderation infrastructure failure',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            post_cutoff_unstructured_scan_id::TEXT,
            test_user_id,
            'unstructured evidence inserted after rollout with backdated transaction timestamp',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            pre_safety_unstructured_scan_id::TEXT,
            test_user_id,
            'Failed to ensure scan user exists: post-result prerequisite unavailable',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            incomplete_structured_safety_scan_id::TEXT,
            test_user_id,
            'structured durability failure before required safety completed',
            pg_catalog.CLOCK_TIMESTAMP(),
            (
                SELECT reservations.id
                FROM internal.ai_quota_reservations AS reservations
                WHERE reservations.user_id = test_user_id
                  AND reservations.operation = 'scan_identification'
                  AND reservations.request_id =
                      incomplete_structured_safety_scan_id
            ),
            incomplete_structured_safety_scan_id,
            'post_result_scan_durability_failure',
            TRUE,
            FALSE
        ),
        (
            legacy_moderation_message_scan_id::TEXT,
            test_user_id,
            'Multimodal moderation pipeline failed.',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            wrong_endpoint_recovery_scan_id::TEXT,
            test_user_id,
            'legacy compatibility producer failed after provider result',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            active_replay_recovery_scan_id::TEXT,
            test_user_id,
            'legacy durability failure while later replay remains active',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        ),
        (
            invalid_timestamp_recovery_scan_id::TEXT,
            test_user_id,
            'legacy durability failure with corrupt quota chronology',
            legacy_unstructured_before - INTERVAL '1 minute',
            NULL,
            NULL,
            NULL,
            NULL,
            NULL
        );

    -- This fixture runs after every migration, so simulate the exact immutable
    -- identities that were visible to the hardening migration. Deliberately
    -- omit the post-cutoff row even though its transaction timestamp is
    -- backdated before the cutoff; row identity, not timestamp alone, must
    -- prevent a lock-blocked older producer from gaining legacy authority.
    INSERT INTO internal.scan_recovery_legacy_dead_letters (
        failed_scan_ingestion_id,
        captured_at
    )
    SELECT
        failures.id,
        legacy_unstructured_before
    FROM public.failed_scan_ingestions AS failures
    WHERE failures.user_id = test_user_id
      AND failures.scan_id <> post_cutoff_unstructured_scan_id::TEXT
      AND failures.quota_reservation_id IS NULL
      AND failures.quota_request_id IS NULL
      AND failures.failure_kind IS NULL
      AND failures.provider_result_validated IS NULL
      AND failures.identify_safety_evaluation_completed IS NULL
    ON CONFLICT (failed_scan_ingestion_id) DO NOTHING;

    -- The fixture backdates charged authority around the immutable migration
    -- cutoff. Keep reserve -> commit chronology realistic before exercising
    -- the proof and its deliberately corrupt failed-before-commit case.
    UPDATE internal.ai_quota_reservations AS reservations
    SET reserved_at = reservations.committed_at - INTERVAL '1 second'
    WHERE reservations.user_id = test_user_id
      AND reservations.operation = 'scan_identification'
      AND reservations.committed_at IS NOT NULL
      AND reservations.reserved_at > reservations.committed_at;

    UPDATE internal.ai_quota_reservations AS reservations
    SET updated_at = pg_catalog.NOW() - INTERVAL '31 days'
    WHERE reservations.user_id = test_user_id
      AND reservations.operation = 'scan_identification'
      AND reservations.request_id = ANY (
          ARRAY[
              media_abandoned_scan_id,
              later_policy_overwrite_scan_id,
              moderation_overwrite_scan_id,
              replay_policy_overwrite_scan_id,
              internal.derive_ai_quota_request_id(
                  replay_policy_overwrite_scan_id,
                  'scan-ingestion-replay:1'
              ),
              internal.derive_ai_quota_request_id(
                  replay_policy_overwrite_scan_id,
                  'scan-ingestion-replay:2'
              ),
              structured_media_abandoned_scan_id,
              moderation_pipeline_overwrite_scan_id,
              post_cutoff_unstructured_scan_id,
              pre_safety_unstructured_scan_id,
              incomplete_structured_safety_scan_id,
              legacy_moderation_message_scan_id,
              wrong_endpoint_recovery_scan_id,
              active_replay_recovery_scan_id,
              internal.derive_ai_quota_request_id(
                  active_replay_recovery_scan_id,
                  'scan-ingestion-replay:1'
              ),
              invalid_timestamp_recovery_scan_id,
              unrelated_old_quota_request_id
          ]::UUID[]
      );

    -- This call also proves the malformed legacy text scan id above cannot
    -- abort hourly quota maintenance.
    PERFORM internal.prune_ai_quota_state();

    IF EXISTS (
        SELECT 1
        FROM internal.ai_quota_reservations AS reservations
        WHERE reservations.user_id = test_user_id
          AND reservations.operation = 'scan_identification'
          AND reservations.request_id = unrelated_old_quota_request_id
    ) OR EXISTS (
        SELECT 1
        FROM internal.ai_quota_reservations AS reservations
        WHERE reservations.user_id = test_user_id
          AND reservations.operation = 'scan_identification'
          AND reservations.request_id =
              internal.derive_ai_quota_request_id(
                  replay_policy_overwrite_scan_id,
                  'scan-ingestion-replay:2'
              )
    ) OR (
        SELECT pg_catalog.COUNT(*)
        FROM internal.ai_quota_reservations AS reservations
        WHERE reservations.user_id = test_user_id
          AND reservations.operation = 'scan_identification'
          AND reservations.request_id = ANY (
              ARRAY[
                  media_abandoned_scan_id,
                  later_policy_overwrite_scan_id,
                  moderation_overwrite_scan_id,
                  replay_policy_overwrite_scan_id,
                  internal.derive_ai_quota_request_id(
                      replay_policy_overwrite_scan_id,
                      'scan-ingestion-replay:1'
                  ),
                  structured_media_abandoned_scan_id,
                  moderation_pipeline_overwrite_scan_id,
                  post_cutoff_unstructured_scan_id,
                  pre_safety_unstructured_scan_id,
                  incomplete_structured_safety_scan_id,
                  legacy_moderation_message_scan_id,
                  wrong_endpoint_recovery_scan_id,
                  active_replay_recovery_scan_id,
                  internal.derive_ai_quota_request_id(
                      active_replay_recovery_scan_id,
                      'scan-ingestion-replay:1'
                  ),
                  invalid_timestamp_recovery_scan_id
              ]::UUID[]
          )
    ) <> 15 THEN
        RAISE EXCEPTION
            'quota pruning lost recovery proof, policy, or active authority';
    END IF;

    IF (
        SELECT pg_catalog.ARRAY_AGG(proofs.scan_id ORDER BY proofs.scan_id)
        FROM public.get_media_abandoned_scan_recovery_proofs(
            test_user_id,
            ARRAY[
                media_abandoned_scan_id,
                later_policy_overwrite_scan_id,
                moderation_overwrite_scan_id,
                replay_policy_overwrite_scan_id,
                structured_media_abandoned_scan_id,
                moderation_pipeline_overwrite_scan_id,
                post_cutoff_unstructured_scan_id,
                pre_safety_unstructured_scan_id,
                incomplete_structured_safety_scan_id,
                legacy_moderation_message_scan_id,
                wrong_endpoint_recovery_scan_id,
                active_replay_recovery_scan_id,
                invalid_timestamp_recovery_scan_id
            ]::UUID[]
        ) AS proofs
    ) IS DISTINCT FROM ARRAY[
        media_abandoned_scan_id,
        structured_media_abandoned_scan_id
    ]::UUID[] THEN
        RAISE EXCEPTION
            'restore signer proof lookup admitted unsafe media abandonment';
    END IF;

    SELECT public.recover_missing_owned_scan(
        media_abandoned_scan_id,
        test_user_id,
        pg_catalog.JSONB_SET(
            recovery_payload,
            '{id}',
            pg_catalog.TO_JSONB(media_abandoned_scan_id)
        )
    )
    INTO STRICT result_text;
    IF result_text <> 'recovered'
       OR NOT EXISTS (
            SELECT 1
            FROM public.scans AS scans
            WHERE scans.id = media_abandoned_scan_id
              AND scans.user_id = test_user_id
       )
       OR NOT EXISTS (
            SELECT 1
            FROM public.scan_ingestion_jobs AS jobs
            WHERE jobs.scan_id = media_abandoned_scan_id::TEXT
              AND jobs.user_id = test_user_id
              AND jobs.status = 'complete'
              AND jobs.stage = 'client_recovery_complete'
              AND jobs.terminal_reason_code IS NULL
       ) THEN
        RAISE EXCEPTION
            'explicit media-abandonment owner recovery did not complete atomically';
    END IF;

    FOREACH blocked_recovery_scan_id IN ARRAY ARRAY[
        policy_rejected_scan_id,
        unknown_terminal_scan_id,
        unproven_media_abandoned_scan_id,
        later_policy_overwrite_scan_id,
        moderation_overwrite_scan_id,
        replay_policy_overwrite_scan_id,
        moderation_pipeline_overwrite_scan_id,
        post_cutoff_unstructured_scan_id,
        pre_safety_unstructured_scan_id,
        incomplete_structured_safety_scan_id,
        legacy_moderation_message_scan_id,
        wrong_endpoint_recovery_scan_id,
        active_replay_recovery_scan_id,
        invalid_timestamp_recovery_scan_id
    ]::UUID[]
    LOOP
        SELECT public.recover_missing_owned_scan(
            blocked_recovery_scan_id,
            test_user_id,
            pg_catalog.JSONB_SET(
                recovery_payload,
                '{id}',
                pg_catalog.TO_JSONB(blocked_recovery_scan_id)
            )
        )
        INTO STRICT result_text;
        IF result_text <> 'deferred'
           OR EXISTS (
                SELECT 1
                FROM public.scans AS scans
                WHERE scans.id = blocked_recovery_scan_id
           ) THEN
            RAISE EXCEPTION
                'unsafe or unproven terminal reason recovered scan %',
                blocked_recovery_scan_id;
        END IF;
    END LOOP;

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

    -- Recovery deliberately fails closed without an eligible ingestion ledger.
    -- Establish exact same-generation replay evidence before recovery creates
    -- the scan used by the deletion scenario.
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
        deletion_scan_id::TEXT,
        test_user_id,
        'identify-multimodal',
        'failed_terminal',
        'server_replay_limit_reached',
        'replay_exhausted',
        pg_catalog.NOW()
    );

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
        RAISE EXCEPTION
            'deletion fixture recovery failed with status %',
            COALESCE(result_text, '<null>');
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

    SELECT public.complete_scan_deletion(
        deletion_scan_id,
        test_user_id
    )
    INTO STRICT scan_deletion_completed;
    IF scan_deletion_completed IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'verified scan deletion RPC returned false';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM public.scans AS scans
        WHERE scans.id = deletion_scan_id
    ) THEN
        RAISE EXCEPTION 'verified scan deletion left the owner row';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM internal.scan_deletion_tombstones AS tombstones
        WHERE tombstones.scan_id = deletion_scan_id
          AND tombstones.user_id IS NULL
          AND tombstones.completed_at IS NOT NULL
          AND tombstones.claim_token IS NULL
          AND tombstones.lease_expires_at IS NULL
    ) THEN
        RAISE EXCEPTION 'verified scan deletion left a nonterminal tombstone';
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

    SELECT public.complete_dwca_archive_cleanup_job(
        current_cleanup_id,
        current_cleanup_claim_token
    )
    INTO STRICT current_archive_cleanup_completed;
    IF current_archive_cleanup_completed IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'current archive cleanup RPC returned false';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM internal.export_download_grants AS grants
        WHERE grants.job_id = cleanup_generation_job_id
          AND grants.revoked_at IS NOT NULL
          AND grants.cleaned_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'current archive cleanup did not retire its grant';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM internal.export_job_source_state AS source_state
        WHERE source_state.job_id = cleanup_generation_job_id
          AND source_state.purged_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'current archive cleanup did not purge its snapshot';
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
