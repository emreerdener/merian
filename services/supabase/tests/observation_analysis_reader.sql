\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(19);

SELECT extensions.ok(NOT (SELECT reader_enabled FROM internal.observation_history_rollout WHERE singleton), 'reader defaults closed');
SELECT extensions.ok(pg_catalog.HAS_FUNCTION_PRIVILEGE('authenticated','public.get_owned_observation_analysis_page(jsonb,integer)','EXECUTE'), 'owner reader is callable by authenticated');
SELECT extensions.ok(NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('anon','public.get_owned_observation_analysis_page(jsonb,integer)','EXECUTE')
    AND NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role','public.get_owned_observation_analysis_page(jsonb,integer)','EXECUTE'), 'anonymous and service roles cannot call the owner reader');

INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-4000-8000-00000000d401','authenticated','authenticated','history-reader@example.invalid','{}','{}',NOW(),NOW());
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
VALUES('00000000-0000-4000-8000-00000000d411','00000000-0000-4000-8000-00000000d401','failed_terminal','server_replay_limit_reached','replay_exhausted');
INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
VALUES('00000000-0000-4000-8000-00000000d411','00000000-0000-4000-8000-00000000d401','{}',0.9,TRUE,'flash','open',TRUE);
UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
INSERT INTO internal.observation_histories(observation_id) VALUES('00000000-0000-4000-8000-00000000d411');
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT ('00000000-0000-4000-8000-00000000d42' || n)::UUID,'00000000-0000-4000-8000-00000000d411',n,
    pg_catalog.REPEAT('a',64),'{"scan_id":"00000000-0000-4000-8000-00000000d411"}',
    '{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic fixture"}}}]}',
    '2026-01-01T00:00:00Z'::TIMESTAMPTZ FROM pg_catalog.GENERATE_SERIES(1,3) n;
UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE;

SELECT extensions.throws_ok($$INSERT INTO internal.observation_analysis_results
    (analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
    VALUES('00000000-0000-4000-8000-00000000d499','00000000-0000-4000-8000-00000000d411',99,
        REPEAT('a',64),JSONB_BUILD_OBJECT('padding',REPEAT('x',700000)),
        JSONB_BUILD_OBJECT('padding',REPEAT('x',700000)),NOW())$$,
    '23514',NULL,'individually valid columns cannot commit an unreadable aggregate snapshot');

CREATE FUNCTION pg_temp.read_history_fixture(before_ordinal INTEGER DEFAULT NULL, page_limit INTEGER DEFAULT 20, reader INTEGER DEFAULT 7)
RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.get_owned_observation_analysis_page(
    pg_catalog.JSONB_BUILD_OBJECT('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000d411','before_ordinal',before_ordinal,'limit',page_limit), reader); $$;
GRANT EXECUTE ON FUNCTION pg_temp.read_history_fixture(INTEGER, INTEGER, INTEGER) TO authenticated;
SELECT pg_catalog.SET_CONFIG('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000d401","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.read_history_fixture()', '55000','analysis_history_unavailable','closed reader gate rejects even the owner');
RESET ROLE;
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT extensions.is(pg_catalog.JSONB_ARRAY_LENGTH(pg_temp.read_history_fixture() -> 'items'),3,'owner receives bounded private history');
SELECT extensions.is(pg_temp.read_history_fixture() ->> 'owner_id','00000000-0000-4000-8000-00000000d401','response derives owner from caller');
SELECT extensions.is(pg_temp.read_history_fixture(NULL,2) ->> 'next_before_ordinal','2','descending first page returns last accepted ordinal');
SELECT extensions.is((pg_temp.read_history_fixture(2,2) -> 'items' -> 0 ->> 'ordinal')::INTEGER,1,'cursor excludes prior results with tied timestamps');
SELECT extensions.is(pg_temp.read_history_fixture(2,2) -> 'next_before_ordinal','null'::JSONB,'final page terminates');
SELECT extensions.is((pg_temp.read_history_fixture() -> 'items' -> 0 ->> 'snapshot'),
    (pg_temp.read_history_fixture() -> 'items' -> 0 ->> 'snapshot'),'unchanged JSONB read-back has stable bytes');
SELECT extensions.throws_ok('SELECT pg_temp.read_history_fixture(NULL,21)', '22023','invalid_analysis_history','oversized page rejected');
SELECT extensions.throws_ok('SELECT pg_temp.read_history_fixture(NULL,20,6)', '22023','invalid_analysis_history','old reader rejected');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_page('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000d411","before_ordinal":null,"limit":20,"owner_id":"00000000-0000-4000-8000-00000000d401"}',7)$$,
    '22023','invalid_analysis_history','caller cannot supply owner authority');
SELECT pg_catalog.SET_CONFIG('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000d402","role":"authenticated"}',TRUE);
SELECT extensions.throws_ok('SELECT pg_temp.read_history_fixture()', 'P0002','analysis_history_not_found','public observation does not make private history cross-owner readable');
SELECT pg_catalog.SET_CONFIG('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000d401","role":"authenticated"}',TRUE);
RESET ROLE;

INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT ('00000000-0000-4000-8000-00000000d43' || n)::UUID,'00000000-0000-4000-8000-00000000d411',n+3,
    pg_catalog.REPEAT('a',64),pg_catalog.JSONB_BUILD_OBJECT('scan_id','00000000-0000-4000-8000-00000000d411','padding',pg_catalog.REPEAT('x',900000)),
    '{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic fixture"}}}]}',
    '2026-01-01T00:00:00Z'::TIMESTAMPTZ FROM pg_catalog.GENERATE_SERIES(1,5) n;
SET LOCAL ROLE authenticated;
SELECT extensions.ok(pg_catalog.OCTET_LENGTH(pg_temp.read_history_fixture()::TEXT) <= 4194304,'aggregate response stays within 4 MiB');
SELECT extensions.is(pg_temp.read_history_fixture() ->> 'next_before_ordinal','5','byte-bound page stops at a resumable prefix');
RESET ROLE;
-- Simulate deletion fence after a completed result exists; a prior result must not bypass it.
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000d411','00000000-0000-4000-8000-00000000d401');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.read_history_fixture()', 'P0002','analysis_history_not_found','deletion fence wins over stored results');
RESET ROLE;
SELECT extensions.ok(NOT (SELECT enrollment_enabled OR selection_enabled FROM internal.observation_history_rollout WHERE singleton), 'read testing never enables enrollment or selection');
SELECT * FROM extensions.finish();
ROLLBACK;
