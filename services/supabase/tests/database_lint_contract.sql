\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(1);

DO $test$
DECLARE
    function_definition TEXT;
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
END;
$test$;

SELECT extensions.pass(
    'reviewed routines satisfy the strict database lint contract'
);
SELECT * FROM extensions.finish();
ROLLBACK;
