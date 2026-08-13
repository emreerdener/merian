\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(1);

DO $test$
DECLARE
    function_definition TEXT;
    normalized_definition TEXT;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM (
            VALUES
                ('public.sanitize_explore_location(text)'),
                ('public.resolve_explore_location_label(text,text)'),
                ('internal.server_api_request_headers(text)')
        ) AS routine(signature)
        WHERE pg_catalog.TO_REGPROCEDURE(routine.signature) IS NULL
    ) THEN
        RAISE EXCEPTION 'a volatility-reviewed routine is missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc AS procedure_row
        WHERE procedure_row.oid IN (
            pg_catalog.TO_REGPROCEDURE(
                'public.sanitize_explore_location(text)'
            ),
            pg_catalog.TO_REGPROCEDURE(
                'public.resolve_explore_location_label(text,text)'
            ),
            pg_catalog.TO_REGPROCEDURE(
                'internal.server_api_request_headers(text)'
            )
        )
          AND procedure_row.provolatile <> 's'
    ) THEN
        RAISE EXCEPTION
            'a routine still promises stronger than STABLE volatility';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.reserve_ai_quota(uuid,text,uuid,text)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* '\mignored_count\M' THEN
        RAISE EXCEPTION
            'reserve_ai_quota retains its unread lint-only variable';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.refresh_scan_visual_media_assets(uuid)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* E'\\mi\\M[[:space:]]+integer[[:space:]]*;' THEN
        RAISE EXCEPTION
            'refresh_scan_visual_media_assets still shadows its loop variable';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* E'\\msubject_index\\M[[:space:]]+integer[[:space:]]*;' THEN
        RAISE EXCEPTION
            'apply_revenuecat_customer_state still shadows its loop variable';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_revenuecat_identity_state(text,bigint,text,text,bigint,jsonb)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* E'\\msubject_index\\M[[:space:]]+integer[[:space:]]*;' THEN
        RAISE EXCEPTION
            'apply_revenuecat_identity_state still shadows its loop variable';
    END IF;

    IF pg_catalog.TO_REGPROCEDURE(
        'internal.inline_scan_recovery_ledger_matches(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,text[],text[])'
    ) IS NULL THEN
        RAISE EXCEPTION
            'inline_scan_recovery_ledger_matches is missing';
    END IF;
    IF (
        SELECT procedure_row.provolatile
        FROM pg_catalog.pg_proc AS procedure_row
        WHERE procedure_row.oid = pg_catalog.TO_REGPROCEDURE(
            'internal.inline_scan_recovery_ledger_matches(public.scan_ingestion_jobs,public.scan_ingestion_intents,uuid,text[],text[])'
        )
    ) <> 's' THEN
        RAISE EXCEPTION
            'inline_scan_recovery_ledger_matches still promises IMMUTABLE volatility';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.authorize_species_observation_stats_request(uuid,text,uuid)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* '\mignored_count\M' THEN
        RAISE EXCEPTION
            'authorize_species_observation_stats_request retains its unread variable';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.claim_species_observation_stats_population(uuid,uuid,text)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* '\mignored_count\M' THEN
        RAISE EXCEPTION
            'claim_species_observation_stats_population retains its unread variable';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition !~*
        'PERFORM[[:space:]]+p_manifest_checksum,[[:space:]]*p_payload_checksum;' THEN
        RAISE EXCEPTION
            'begin_scan_ingestion does not document its compatibility-only checksum inputs';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'internal.materialize_dwca_export_source_snapshot(uuid)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition !~*
        '''dwca_export_snapshot_cursor''::refcursor' THEN
        RAISE EXCEPTION
            'materialize_dwca_export_source_snapshot lacks an explicit cursor cast';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* '\mqueue_row\M' THEN
        RAISE EXCEPTION
            'apply_revenuecat_reconciliation retains its unread lock row';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_purchase_principal_reconciliation(uuid,uuid,bigint,text,timestamp with time zone,text,timestamp with time zone)'
        )
    )
    INTO STRICT function_definition;
    normalized_definition := pg_catalog.REGEXP_REPLACE(
        function_definition,
        '[[:space:]]+',
        ' ',
        'g'
    );
    IF function_definition ~* '\mqueue_row\M'
       OR normalized_definition !~*
            'PERFORM 1 FROM internal[.]purchase_principal_reconciliation_queue AS queue WHERE queue[.]purchase_principal_id = principal[.]id AND queue[.]claim_token = p_claim_token AND queue[.]claim_expires_at > pg_catalog[.]clock_timestamp[(][)] FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION ''purchase_principal_reconciliation_claim_lost'''
       OR pg_catalog.STRPOS(
            function_definition,
            'purchase_principal_reconciliation_claim_lost'
          ) <= pg_catalog.STRPOS(
            function_definition,
            'PERFORM 1'
          )
       OR pg_catalog.STRPOS(
            function_definition,
            'FROM internal.apply_purchase_principal_snapshot('
          ) <= pg_catalog.STRPOS(
            function_definition,
            'purchase_principal_reconciliation_claim_lost'
          ) THEN
        RAISE EXCEPTION
            'apply_purchase_principal_reconciliation lacks its lint-clean claim lock';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.release_export_job_step(uuid,uuid,text,boolean)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* '\m(job_row|work_row)\M' THEN
        RAISE EXCEPTION
            'release_export_job_step retains an unread lock row';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.complete_prepared_export_job(uuid,uuid)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* '\mjob_row\M' THEN
        RAISE EXCEPTION
            'complete_prepared_export_job retains its unread lock row';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.ensure_scan_user_profile(uuid)'
        )
    )
    INTO STRICT function_definition;
    IF function_definition ~* '\musername_attempt\M'
       OR function_definition !~* 'FOR profile_attempt IN 1[.][.]5 LOOP'
       OR function_definition !~* 'scan_user_profile_creation_failed' THEN
        RAISE EXCEPTION
            'ensure_scan_user_profile lacks its fail-closed terminal path';
    END IF;
END;
$test$;

SELECT extensions.pass(
    'reviewed routines satisfy the strict database lint contract'
);
SELECT * FROM extensions.finish();
ROLLBACK;
