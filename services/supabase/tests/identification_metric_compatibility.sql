\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE
    helper REGPROCEDURE := 'internal.identification_metrics_are_gemini_compatible(jsonb,text)'::REGPROCEDURE;
    detail REGPROCEDURE := 'public.get_community_identification_detail(uuid,uuid)'::REGPROCEDURE;
    role_name TEXT;
    source TEXT;
    denied BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS p
        WHERE p.oid = helper AND NOT p.prosecdef AND p.provolatile = 'i' AND p.proparallel = 's'
          AND p.proconfig @> ARRAY['search_path=""']
          AND pg_catalog.PG_GET_USERBYID(p.proowner) = 'postgres') THEN
        RAISE EXCEPTION 'metric helper mode, owner, volatility or search path drift';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc AS p
        WHERE p.oid = detail AND NOT p.prosecdef AND p.provolatile = 's'
          AND p.proconfig @> ARRAY['search_path=""']) THEN
        RAISE EXCEPTION 'community projection invoker or search path drift';
    END IF;
    FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        IF pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name, helper, 'EXECUTE')
           OR pg_catalog.HAS_FUNCTION_PRIVILEGE(role_name, detail, 'EXECUTE') THEN
            RAISE EXCEPTION 'direct client metric or community RPC privilege exposed';
        END IF;
        EXECUTE pg_catalog.FORMAT('SET LOCAL ROLE %I', role_name);
        denied := FALSE;
        BEGIN PERFORM internal.identification_metrics_are_gemini_compatible(NULL, 'flash');
        EXCEPTION WHEN insufficient_privilege THEN denied := TRUE; END;
        IF NOT denied THEN RAISE EXCEPTION 'direct client metric invocation accepted'; END IF;
        denied := FALSE;
        BEGIN PERFORM public.get_community_identification_detail(NULL, NULL);
        EXCEPTION WHEN insufficient_privilege THEN denied := TRUE; END;
        IF NOT denied THEN RAISE EXCEPTION 'direct client community invocation accepted'; END IF;
        RESET ROLE;
    END LOOP;
    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', helper, 'EXECUTE')
       OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', detail, 'EXECUTE') THEN
        RAISE EXCEPTION 'service metric projection caller denied';
    END IF;
    SET LOCAL ROLE service_role;
    IF NOT internal.identification_metrics_are_gemini_compatible(NULL, 'flash')
       OR internal.identification_metrics_are_gemini_compatible('null', 'flash')
       OR internal.identification_metrics_are_gemini_compatible('{}', 'flash') THEN
        RAISE EXCEPTION 'legacy absence conflated with invalid presence';
    END IF;
    RESET ROLE;
    SELECT pg_catalog.PG_GET_FUNCTIONDEF('public.get_explore_author_profile(uuid,uuid,integer)'::REGPROCEDURE) INTO source;
    IF source NOT LIKE '%WHERE ai_confidence_qualified AND ai_confidence_score >= 0.98%'
       OR source NOT LIKE '%''type'', ''domestic_cat''%'
       OR source NOT LIKE '%''type'', ''domestic_dog''%'
       OR source NOT LIKE '%first_field_trip%'
       OR source NOT LIKE '%explore_projected_post_cards%' THEN
        RAISE EXCEPTION 'public profile lost later contracts or score gate';
    END IF;
    SELECT pg_catalog.PG_GET_FUNCTIONDEF('public.refresh_merian_reference_images(integer,integer,boolean,double precision)'::REGPROCEDURE) INTO source;
    IF source NOT LIKE '%PERFORM internal.require_service_role();%'
       OR (pg_catalog.LENGTH(source) - pg_catalog.LENGTH(pg_catalog.REPLACE(source,
          'AND internal.identification_metrics_are_gemini_compatible(s.identification_provenance, s.inference_tier)', '')))
          / pg_catalog.LENGTH('AND internal.identification_metrics_are_gemini_compatible(s.identification_provenance, s.inference_tier)') <> 2 THEN
        RAISE EXCEPTION 'reference worker lost auth or either quality gate';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS t
        WHERE t.tgrelid = 'public.scans'::REGCLASS
          AND t.tgname = 'trg_apply_ingested_scan_field_trip_progress_update'
          AND pg_catalog.PG_GET_TRIGGERDEF(t.oid) LIKE '%identification_provenance%') THEN
        RAISE EXCEPTION 'Field Trip trigger omits metric provenance';
    END IF;
    SELECT pg_catalog.PG_GET_FUNCTIONDEF('public.apply_field_trip_scan_progress_atomic(uuid,uuid,uuid,uuid)'::REGPROCEDURE) INTO source;
    IF source NOT LIKE '%''ai_confidence_qualified'', internal.identification_metrics_are_gemini_compatible%'
       OR source NOT LIKE '%PERFORM internal.require_service_role();%' THEN
        RAISE EXCEPTION 'Field Trip receipt or service boundary drift';
    END IF;
END;
$test$;
SELECT extensions.pass('metric compatibility catalog: private pure helper, actual role denials, quality gates, receipt and later profile contracts');
SELECT * FROM extensions.finish();
ROLLBACK;
