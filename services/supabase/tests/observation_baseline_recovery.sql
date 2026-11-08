\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
SELECT extensions.ok(has_function_privilege('authenticated','public.get_owned_observation_enrollment_baseline(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_owned_observation_enrollment_baseline(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.get_owned_observation_enrollment_baseline(jsonb,integer)','EXECUTE'),
 'only authenticated callers can request existing baseline recovery');

INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES('00000000-0000-4000-8000-00000000b901','authenticated','authenticated','baseline-fixture@example.invalid','{}','{}',now(),now()),
 ('00000000-0000-4000-8000-00000000b902','authenticated','authenticated','baseline-foreign@example.invalid','{}','{}',now(),now());
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 SELECT ('00000000-0000-4000-8000-00000000b91'||n),'00000000-0000-4000-8000-00000000b901','failed_terminal','server_replay_limit_reached','replay_exhausted'
 FROM generate_series(1,2) n;
INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy)
 SELECT ('00000000-0000-4000-8000-00000000b91'||n)::UUID,'00000000-0000-4000-8000-00000000b901','{}',0.9,TRUE,'flash','private'
 FROM generate_series(1,2) n;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000b901","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,
 '55000','analysis_history_unavailable','closed reader denies recovery');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911","owner_id":"00000000-0000-4000-8000-00000000b901"}',9)$$,
 '22023','invalid_analysis_history','request cannot nominate owner');
RESET ROLE;
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,state_reader_enabled=FALSE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,
 '55000','analysis_history_unavailable','state-reader gate independently denies recovery');
RESET ROLE;
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,state_reader_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,
 'P0002','analysis_history_not_found','missing history is not enrolled by recovery');
RESET ROLE;
SELECT extensions.is((SELECT count(*)::INTEGER FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000b911'),0,'read created no history');
UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE,saved_import_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000b911',9);
RESET ROLE;
UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE,saved_import_enabled=FALSE;
CREATE TEMP TABLE baseline_response(value JSONB);
GRANT ALL ON baseline_response TO authenticated;
SET LOCAL ROLE authenticated;
INSERT INTO baseline_response SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9);
RESET ROLE;
SELECT extensions.ok((SELECT value->>'snapshot'=internal.observation_analysis_snapshot(r.observation_id,r.analysis_id,r.source_analysis_id,r.request_digest,r.ordinal,r.completed_at,r.result_snapshot,r.evidence_manifest)
 AND value->>'baseline_analysis_id'=r.analysis_id::TEXT AND value->>'owner_id'='00000000-0000-4000-8000-00000000b901'
 FROM baseline_response CROSS JOIN internal.observation_analysis_results r WHERE r.observation_id='00000000-0000-4000-8000-00000000b911'),
 'recovery returns exact immutable baseline bytes and bound identity');
SELECT extensions.ok((SELECT value->>'snapshot_sha256'=encode(extensions.digest(convert_to(E'merian.observation-history.enrollment-baseline.v1\n'||(value->>'snapshot'),'UTF8'),'sha256'),'hex')
 AND value-ARRAY['schema_version','owner_id','observation_id','baseline_analysis_id','snapshot','snapshot_sha256']='{}'::JSONB FROM baseline_response),
 'domain-separated exact-byte digest carries no selected review or invented intent');

DO $$ DECLARE base internal.observation_analysis_results; later UUID:='00000000-0000-4000-8000-00000000b999'; BEGIN
 SELECT * INTO base FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000b911' AND ordinal=1;
 INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,completed_at,result_snapshot,evidence_manifest)
 VALUES(later,base.observation_id,2,repeat('a',64),now(),base.result_snapshot,'{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic later result"}}}]}');
 INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
 SELECT base.observation_id,later,review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id=base.analysis_id;
 UPDATE internal.observation_histories SET selected_analysis_id=later,state_revision=4 WHERE observation_id=base.observation_id;
END $$;
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9),
 (SELECT value FROM baseline_response),'later selection does not change recovered baseline');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b912"}',9)$$,
 'P0002','analysis_history_not_found','second missing history remains absent after recovery of first');
RESET ROLE;
SELECT extensions.ok((SELECT selected_analysis_id='00000000-0000-4000-8000-00000000b999' AND state_revision=4
 FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000b911'),'recovery preserves later selection and revision');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000b902","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,
 'P0002','analysis_history_not_found','existing foreign account cannot recover baseline');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,'42501',NULL,'anonymous execution denied');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,'42501',NULL,'service execution denied');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000b901","role":"authenticated"}',TRUE);
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000b911','00000000-0000-4000-8000-00000000b901');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,
 'P0002','analysis_history_not_found','deletion fences existing recovery');
RESET ROLE;
SELECT extensions.ok(NOT (SELECT enrollment_enabled OR saved_import_enabled OR selection_enabled OR admission_enabled OR dispatch_enabled FROM internal.observation_history_rollout WHERE singleton),
 'recovery does not enable enrollment selection or execution');
SELECT * FROM extensions.finish();
ROLLBACK;
