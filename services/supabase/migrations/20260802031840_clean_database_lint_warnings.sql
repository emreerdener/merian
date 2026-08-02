-- The production deploy lints a clean replay before it mutates production.
-- Keep that gate strict by repairing the reviewed warning set in a forward
-- migration instead of rewriting migrations that have already shipped.

ALTER FUNCTION public.sanitize_explore_location(TEXT) STABLE;
ALTER FUNCTION public.sanitize_explore_location(TEXT) SET search_path = '';

-- The SQL wrapper cannot promise stronger volatility than its sanitizer.
ALTER FUNCTION public.resolve_explore_location_label(TEXT, TEXT) STABLE;
ALTER FUNCTION public.resolve_explore_location_label(TEXT, TEXT)
    SET search_path = '';

-- Text-to-JSON conversion is classified STABLE by PostgreSQL. The helper is
-- deterministic for a given key, but its declaration must not over-promise.
ALTER FUNCTION internal.server_api_request_headers(TEXT) STABLE;

-- These three routines deliberately ignore helper return values or use an
-- integer FOR-loop's implicit variable. Rebuild their existing definitions
-- with only the redundant declarations/assignments removed. Fetching the
-- installed definition preserves the reviewed body, security mode, function
-- settings, return contract, owner, comments, and existing ACLs.
DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.reserve_ai_quota(uuid,text,uuid,text)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION 'reserve_ai_quota is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    ignored_count INTEGER;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        '    ignored_count := internal.consume_ai_quota_counter(',
        '    PERFORM internal.consume_ai_quota_counter('
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'ignored_count') > 0 THEN
        RAISE EXCEPTION
            'reserve_ai_quota lint repair did not match the reviewed definition';
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
            'public.refresh_scan_visual_media_assets(uuid)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'refresh_scan_visual_media_assets is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    i INTEGER;\n',
        ''
    );

    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'refresh_scan_visual_media_assets lint repair did not match the reviewed definition';
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
            'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'apply_revenuecat_customer_state is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    subject_index INTEGER;\n',
        ''
    );

    IF patched_sql = function_sql THEN
        RAISE EXCEPTION
            'apply_revenuecat_customer_state lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;
