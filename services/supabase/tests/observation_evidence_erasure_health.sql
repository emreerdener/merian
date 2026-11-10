\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(NOT (SELECT enabled FROM internal.observation_evidence_worker_state),'worker starts inactive');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='observation_evidence_erasure_every_minute'),'migration does not schedule transport');
SELECT extensions.ok(NOT has_function_privilege('anon','public.get_observation_evidence_erasure_health()','execute') AND NOT has_function_privilege('authenticated','public.get_observation_evidence_erasure_health()','execute'),'health is service-only');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.dispatch_observation_evidence_erasure()','execute'),'service API cannot dispatch scheduler');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_evidence_worker_state','select'),'private telemetry table is not exposed');
SET LOCAL ROLE service_role;
SELECT extensions.is((public.get_observation_evidence_erasure_health()->>'schema_version')::INTEGER,1,'service role reads aggregate');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT public.get_observation_evidence_erasure_health()', '42501', NULL, 'authenticated health denied');
RESET ROLE;
-- The maintenance postgres role is intentionally trusted by the shared guard.
-- Temporarily grant only this transactional fixture's client call so the
-- in-function denial is exercised independently of its permanent API ACL.
GRANT EXECUTE ON FUNCTION public.get_observation_evidence_erasure_health() TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"role":"authenticated"}',TRUE);
SELECT extensions.throws_ok('SELECT public.get_observation_evidence_erasure_health()', '42501', NULL, 'inside guard rejects caller with no service identity');
RESET ROLE;
REVOKE EXECUTE ON FUNCTION public.get_observation_evidence_erasure_health() FROM authenticated;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);

INSERT INTO internal.observation_evidence_erasure(object_id,available_at,first_observed_at,claim_token,claim_expires_at) VALUES
 ('00000000-0000-4000-8000-00000000ed01',statement_timestamp()-INTERVAL '2 hours',statement_timestamp()-INTERVAL '3 hours',NULL,NULL),
 ('00000000-0000-4000-8000-00000000ed02',statement_timestamp()+INTERVAL '1 hour',statement_timestamp()-INTERVAL '2 hours',NULL,NULL),
 ('00000000-0000-4000-8000-00000000ed03',statement_timestamp()-INTERVAL '1 hour',statement_timestamp()-INTERVAL '1 hour','00000000-0000-4000-8000-00000000ed13',statement_timestamp()+INTERVAL '1 hour'),
 ('00000000-0000-4000-8000-00000000ed04',statement_timestamp()-INTERVAL '1 hour',NULL,'00000000-0000-4000-8000-00000000ed14',statement_timestamp()-INTERVAL '1 minute');
SELECT extensions.is((public.get_observation_evidence_erasure_health()->'queue'->>'pending')::BIGINT,4::BIGINT,'pending includes live claim and backoff');
SELECT extensions.is((public.get_observation_evidence_erasure_health()->'queue'->>'claimable')::BIGINT,2::BIGINT,'expired claims are claimable');
SELECT extensions.is((public.get_observation_evidence_erasure_health()->'queue'->>'deferred')::BIGINT,1::BIGINT,'backoff remains visible');
SELECT extensions.is((public.get_observation_evidence_erasure_health()->'queue'->>'live_claims')::BIGINT,1::BIGINT,'live claim is separate');
SELECT extensions.is((public.get_observation_evidence_erasure_health()->'queue'->>'unknown_age')::BIGINT,1::BIGINT,'historical age remains unknown');
SELECT extensions.cmp_ok((public.get_observation_evidence_erasure_health()->'queue'->>'oldest_pending_age_seconds')::NUMERIC,'>=',10800::NUMERIC,'original pending age survives retry clocks');
UPDATE internal.observation_evidence_erasure SET available_at=clock_timestamp()+INTERVAL '2 hours' WHERE object_id='00000000-0000-4000-8000-00000000ed01';
SELECT extensions.cmp_ok((public.get_observation_evidence_erasure_health()->'queue'->>'oldest_pending_age_seconds')::NUMERIC,'>=',10800::NUMERIC,'backoff never resets original age');
SELECT extensions.throws_ok($$UPDATE internal.observation_evidence_erasure SET first_observed_at=clock_timestamp() WHERE object_id='00000000-0000-4000-8000-00000000ed01'$$,'22023','evidence_erasure_observation_clock_immutable','immutable original age');
CREATE TEMP TABLE health_before AS SELECT to_jsonb(s) state FROM internal.observation_evidence_worker_state s;
SELECT public.get_observation_evidence_erasure_health() IS NOT NULL AS read_performed;
SELECT extensions.is((SELECT to_jsonb(s) FROM internal.observation_evidence_worker_state s),(SELECT state FROM health_before),'health reads do not mutate worker telemetry');

SELECT extensions.ok(internal.valid_observation_evidence_worker_receipt('{"retired":5,"video_retired":7,"retirement_failures":0,"claimed":1,"marked":1,"acknowledged":1}'),'both maximum lane counts parse');
SELECT extensions.ok(NOT internal.valid_observation_evidence_worker_receipt('{"retired":5,"video_retired":8,"retirement_failures":0,"claimed":1,"marked":1,"acknowledged":1}'),'video over-bound rejected');
SELECT extensions.ok(NOT internal.valid_observation_evidence_worker_receipt('{"retired":0,"video_retired":0,"retirement_failures":0,"claimed":0,"marked":1,"acknowledged":0}'),'marker without claim rejected');
SELECT extensions.ok(NOT internal.valid_observation_evidence_worker_receipt('{"retired":0,"video_retired":0,"retirement_failures":0,"claimed":0,"marked":0,"acknowledged":0,"object_id":"synthetic"}'),'receipt identities rejected');
SELECT extensions.ok(NOT internal.valid_observation_evidence_worker_receipt('{"retired":null,"video_retired":0,"retirement_failures":0,"claimed":0,"marked":0,"acknowledged":0}'),'null receipt value rejected');

-- Synthetic response rows only, rolled back. No HTTP is queued by these cases:
-- enabled stays false and pending-slot reconciliation precedes that gate.
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id IS NULL FROM internal.observation_evidence_worker_state),'disabled worker queues nothing');
UPDATE internal.observation_evidence_worker_state SET pending_request_id=-31001,last_dispatched_at=clock_timestamp()-INTERVAL '5 minutes';
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id=-31001 AND last_result='unknown' FROM internal.observation_evidence_worker_state),'missing response retains unknown slot');
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-31001,200,'{"retired":0,"video_retired":7,"retirement_failures":1,"claimed":1,"marked":1,"acknowledged":0}',FALSE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id IS NULL AND last_result='failure' AND consecutive_failures=1 AND last_success_at IS NULL FROM internal.observation_evidence_worker_state),'HTTP200 partial acknowledgement is a failure');
UPDATE internal.observation_evidence_worker_state SET pending_request_id=-31002,last_dispatched_at=clock_timestamp();
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-31002,200,'{"retired":0,"video_retired":0,"retirement_failures":0,"claimed":0,"marked":0,"acknowledged":0}',FALSE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id IS NULL AND last_result='success' AND consecutive_failures=0 AND last_success_at IS NOT NULL AND last_marker_success_at IS NULL FROM internal.observation_evidence_worker_state),'idle receipt is a heartbeat but not marker progress');
UPDATE internal.observation_evidence_worker_state SET pending_request_id=-31003,last_dispatched_at=clock_timestamp();
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-31003,200,'{"retired":0,"video_retired":0,"retirement_failures":0,"claimed":1,"marked":1,"acknowledged":1}',FALSE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT last_marker_success_at IS NOT NULL FROM internal.observation_evidence_worker_state),'acknowledged marker records progress');
UPDATE internal.observation_evidence_worker_state SET pending_request_id=-31004,last_dispatched_at=clock_timestamp();
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-31004,NULL,NULL,TRUE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id=-31004 AND last_result='unknown' FROM internal.observation_evidence_worker_state),'transport timeout retains slot rather than overlapping remote execution');
SELECT extensions.ok((public.get_observation_evidence_erasure_health()::TEXT NOT LIKE '%object_id%') AND (public.get_observation_evidence_erasure_health()::TEXT NOT LIKE '%pending_request_id%'),'health excludes object and transport identities');
-- All network calls are replaced transaction-locally before testing enabled
-- scheduling. No real request can leave this disposable catalog transaction.
CREATE TEMP TABLE evidence_test_dispatches(url TEXT,headers JSONB,timeout_ms INTEGER);
CREATE FUNCTION pg_temp.capture_evidence_dispatch(url TEXT,body JSONB DEFAULT '{}'::JSONB,params JSONB DEFAULT '{}'::JSONB,
 headers JSONB DEFAULT '{"Content-Type":"application/json"}'::JSONB,timeout_milliseconds INTEGER DEFAULT 1000)
RETURNS BIGINT LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO pg_temp.evidence_test_dispatches VALUES(url,headers,timeout_milliseconds);
 RETURN -31100;
END;
$$;
-- postgres can call pg_net but cannot replace extension-owned functions. Adapt
-- exactly the transport call in its own dispatcher for this rolled-back test;
-- retain every production branch, lock, receipt check and state update.
SELECT extensions.ok(has_function_privilege('postgres','net.http_post(text,jsonb,jsonb,jsonb,integer)','EXECUTE'),'real scheduler owner may call pg_net transport');
DO $$
DECLARE definition TEXT := pg_get_functiondef('internal.dispatch_observation_evidence_erasure()'::regprocedure);
BEGIN
 IF (length(definition)-length(replace(definition,'net.http_post(','')))/length('net.http_post(') <> 1 THEN
  RAISE EXCEPTION 'unexpected_dispatch_transport_boundary';
 END IF;
 EXECUTE replace(definition,'net.http_post(','pg_temp.capture_evidence_dispatch(');
END;
$$;
SELECT extensions.is((SELECT count(*) FROM vault.secrets WHERE name IN ('SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY')),0::BIGINT,'fresh disposable transport configuration has no secrets');
SELECT vault.create_secret('https://abcdefghijklmnopqrst.supabase.co','SUPABASE_URL') IS NOT NULL AS synthetic_url_created;
SELECT vault.create_secret('sb_secret_'||repeat('a',30),'SUPABASE_SERVICE_ROLE_KEY') IS NOT NULL AS synthetic_key_created;
SELECT extensions.ok(internal.observation_evidence_worker_transport('wrong') IS NULL,'invalid approved project denied');
SELECT extensions.ok(internal.observation_evidence_worker_transport('tsrqponmlkjihgfedcba') IS NULL,'other project denied');
SELECT extensions.is(internal.observation_evidence_worker_transport('abcdefghijklmnopqrst')->'headers'->>'apikey','sb_secret_'||repeat('a',30),'opaque key uses reviewed apikey helper');
SELECT extensions.ok(NOT(internal.observation_evidence_worker_transport('abcdefghijklmnopqrst')->'headers' ? 'Authorization'),'opaque key is not placed in Bearer');
SELECT vault.update_secret((SELECT id FROM vault.secrets WHERE name='SUPABASE_SERVICE_ROLE_KEY'),'');
SELECT set_config('app.settings.supabase_service_role_key','sb_secret_'||repeat('b',30),TRUE);
SELECT extensions.ok(internal.observation_evidence_worker_transport('abcdefghijklmnopqrst') IS NULL,'blank Vault key does not fall through to valid setting');
SELECT vault.update_secret((SELECT id FROM vault.secrets WHERE name='SUPABASE_SERVICE_ROLE_KEY'),'sb_secret_'||repeat('a',30));
UPDATE internal.observation_evidence_worker_state SET pending_request_id=NULL,enabled=TRUE,approved_project='abcdefghijklmnopqrst';
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.is((SELECT count(*) FROM evidence_test_dispatches),1::BIGINT,'enabled scheduler dispatches exactly once');
SELECT extensions.is((SELECT timeout_ms FROM evidence_test_dispatches),120000,'explicit bounded transport timeout');
SELECT extensions.is((SELECT url FROM evidence_test_dispatches),'https://abcdefghijklmnopqrst.supabase.co/functions/v1/erase-observation-evidence','fixed private endpoint on approved target');
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.is((SELECT count(*) FROM evidence_test_dispatches),1::BIGINT,'pending asynchronous request prevents overlap');
INSERT INTO net._http_response(id,status_code,content,timed_out,created) VALUES(-31100,503,'synthetic proxy unavailable',FALSE,clock_timestamp());
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id=-31100 AND last_result='unknown' FROM internal.observation_evidence_worker_state),'proxy error cannot prove remote quiescence');
DO $$
DECLARE sample TEXT;
BEGIN
 FOREACH sample IN ARRAY ARRAY['','not-json',repeat('a',2049),'{"retired":0,"video_retired":8,"retirement_failures":0,"claimed":0,"marked":0,"acknowledged":0}','{"retired":1e1000000}'] LOOP
  UPDATE net._http_response SET status_code=200,content=sample WHERE id=-31100;
  PERFORM internal.dispatch_observation_evidence_erasure();
 END LOOP;
END;
$$;
SELECT extensions.is((SELECT count(*) FROM evidence_test_dispatches),1::BIGINT,'malformed oversized and invalid counters never replace unknown request');
UPDATE net._http_response SET status_code=204,content='' WHERE id=-31100;
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id=-31100 FROM internal.observation_evidence_worker_state),'empty204 retains slot');
UPDATE net._http_response SET status_code=200,content='{"retired":0,"video_retired":0,"retirement_failures":0,"claimed":1,"marked":1,"acknowledged":1}',created=clock_timestamp()-INTERVAL '1 hour' WHERE id=-31100;
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id=-31100 FROM internal.observation_evidence_worker_state),'response from before this dispatch is uncorrelated');
UPDATE net._http_response SET created='infinity' WHERE id=-31100;
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id=-31100 FROM internal.observation_evidence_worker_state),'infinite timestamp denied');
UPDATE net._http_response SET created=clock_timestamp()+INTERVAL '1 hour' WHERE id=-31100;
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id=-31100 FROM internal.observation_evidence_worker_state),'future response timestamp denied');
UPDATE internal.observation_evidence_worker_state SET enabled=FALSE,last_dispatched_at=clock_timestamp()-INTERVAL '2 hours';
UPDATE net._http_response SET created=clock_timestamp()-INTERVAL '1 hour' WHERE id=-31100;
SELECT internal.dispatch_observation_evidence_erasure();
SELECT extensions.ok((SELECT pending_request_id IS NULL AND last_result='success' AND last_success_at<clock_timestamp()-INTERVAL '59 minutes' FROM internal.observation_evidence_worker_state),'delayed reconciliation preserves old response age');
SELECT extensions.cmp_ok((public.get_observation_evidence_erasure_health()->'worker'->>'marker_success_age_seconds')::NUMERIC,'>=',3599::NUMERIC,'old marker is not a fresh heartbeat');
SELECT extensions.is((SELECT count(*) FROM evidence_test_dispatches),1::BIGINT,'paused reconciliation never dispatches');
SELECT * FROM extensions.finish();
ROLLBACK;
