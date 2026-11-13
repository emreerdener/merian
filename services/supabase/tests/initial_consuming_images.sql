-- Private witness preparation only; no row writer or guard recognizes this data.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.empty_consuming_row(relation TEXT) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE row_value JSONB;
BEGIN
 EXECUTE format('SELECT to_jsonb(jsonb_populate_record(NULL::%s,''{}''::JSONB))',relation::regclass) INTO row_value;
 RETURN row_value;
END $$;
CREATE FUNCTION pg_temp.image_rejected(relation TEXT,row_value JSONB) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
 PERFORM internal.initial_consuming_row_image(relation,row_value);
 RETURN FALSE;
EXCEPTION WHEN SQLSTATE '22023' THEN RETURN TRUE;
END $$;
CREATE TEMP TABLE consuming_relations(relation TEXT PRIMARY KEY);
INSERT INTO consuming_relations VALUES ('internal.ai_quota_reservations'),('internal.ai_quota_reservation_counters'),
 ('internal.identification_invocations'),('public.ai_usage_events'),('internal.initial_analysis_results'),('internal.initial_analysis_lifecycle_fences');
SELECT extensions.ok(internal.initial_consuming_row_image(relation,NULL) IS NULL,'SQL absent row preserved: '||relation) FROM consuming_relations;
SELECT extensions.is(internal.initial_consuming_row_image(relation,pg_temp.empty_consuming_row(relation)),
 CASE WHEN relation='internal.ai_quota_reservations' THEN (pg_temp.empty_consuming_row(relation)-'lease_token')||'{"lease_sha256":null}'::JSONB ELSE pg_temp.empty_consuming_row(relation) END,
 'exact catalog column set accepted: '||relation) FROM consuming_relations;
SELECT extensions.ok(pg_temp.image_rejected(relation,pg_temp.empty_consuming_row(relation)||'{"unexpected_column":null}'),'added column denied: '||relation) FROM consuming_relations;
SELECT extensions.ok(pg_temp.image_rejected(relation,pg_temp.empty_consuming_row(relation)-(SELECT k FROM jsonb_object_keys(pg_temp.empty_consuming_row(relation)) k ORDER BY k LIMIT 1)),'removed column denied: '||relation) FROM consuming_relations;
SELECT extensions.ok(pg_temp.image_rejected(relation,'null'::JSONB),'JSON null is not absent row: '||relation) FROM consuming_relations;
CREATE TEMP TABLE quota_image AS SELECT pg_temp.empty_consuming_row('internal.ai_quota_reservations')||'{"lease_token":"00000000-0000-4000-8000-000000000101","state":"reserved","attempt_count":1}'::JSONB row_value;
SELECT extensions.is(internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value)-'lease_sha256',row_value-'lease_token','all nonsecret quota fields preserved') FROM quota_image;
SELECT extensions.ok(NOT internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value) ? 'lease_token','raw lease key absent') FROM quota_image;
SELECT extensions.ok(strpos(internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value)::TEXT,'00000000-0000-4000-8000-000000000101')=0,'raw synthetic lease absent') FROM quota_image;
SELECT extensions.is(internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value)->>'lease_sha256','16fcf70839634f753e124cbc83e9234b8e37cee619b2b9de4809e9ff3add3a2b','fixed UUID UTF8 SHA256 vector') FROM quota_image;
SELECT extensions.ok(internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value) IS DISTINCT FROM internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value||'{"lease_token":"00000000-0000-4000-8000-000000000102"}'),'changed original token differs') FROM quota_image;
SELECT extensions.ok(internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value) IS DISTINCT FROM internal.initial_consuming_row_image('internal.ai_quota_reservations',row_value||'{"state":"committed"}'),'nonsecret mutation differs') FROM quota_image;
SELECT extensions.ok(pg_temp.image_rejected('internal.ai_quota_reservations',row_value||jsonb_build_object('lease_token',value)),'invalid token representation: '||label)
 FROM quota_image CROSS JOIN (VALUES ('empty','""'::JSONB),('number','1'),('array','[]'),('uppercase','"00000000-0000-4000-8000-00000000010A"'),('not uuid','"invalid"')) cases(label,value);
SELECT extensions.ok(pg_temp.image_rejected('public.users','{}'),'unlisted relation denied');
SELECT extensions.is((SELECT jsonb_agg(x->>'key') FROM jsonb_array_elements(internal.initial_consuming_statement_catalog('dispatch')) x),'["quota.commit","quota.links.delete","invocation.insert","lifecycle.dispatch"]'::JSONB,'dispatch statement order fixed');
SELECT extensions.is(internal.initial_consuming_statement_catalog('dispatch')->1->>'rows','original_links','charge-link count derives from original locked roster');
SELECT extensions.is((SELECT jsonb_agg(x->>'key') FROM jsonb_array_elements(internal.initial_consuming_statement_catalog('report')) x),'["usage.insert","invocation.account"]'::JSONB,'report statement order fixed');
SELECT extensions.is(internal.initial_consuming_statement_catalog('report')->0->>'rows','zero_or_one','usage conflict branch explicitly bounded');
SELECT extensions.is(internal.initial_consuming_statement_catalog('result'),'[{"key":"result.insert","relation":"internal.initial_analysis_results","action":"INSERT","rows":"one"}]'::JSONB,'result only inserts one immutable result');
SELECT extensions.throws_ok($$SELECT internal.initial_consuming_statement_catalog('complete')$$,'22023','initial_analysis_consuming_operation_unavailable','unfinished completion has no catalog');
SELECT extensions.throws_ok($$SELECT internal.initial_consuming_statement_catalog('arbitrary')$$,'22023','initial_analysis_consuming_operation_unavailable','arbitrary operation denied');
SELECT extensions.throws_ok($$SELECT internal.initial_consuming_statement_catalog(NULL)$$,'22023','initial_analysis_consuming_operation_unavailable','null operation denied');
SELECT extensions.ok(NOT has_function_privilege(role_name,signature,'EXECUTE'),role_name||' denied '||signature)
 FROM unnest(ARRAY['anon','authenticated','service_role']) role_name
 CROSS JOIN unnest(ARRAY['internal.initial_consuming_statement_catalog(text)','internal.initial_consuming_row_image(text,jsonb)']) signature;
SELECT extensions.ok(NOT prosecdef,proname||' remains invoker') FROM pg_proc
 WHERE oid IN ('internal.initial_consuming_statement_catalog(text)'::regprocedure,'internal.initial_consuming_row_image(text,jsonb)'::regprocedure);
SELECT * FROM extensions.finish();
ROLLBACK;
