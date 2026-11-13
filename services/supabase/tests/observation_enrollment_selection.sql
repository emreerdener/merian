\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES('00000000-0000-4000-8000-00000000b901','authenticated','authenticated','baseline-fixture@example.invalid','{}','{}',now(),now()),
 ('00000000-0000-4000-8000-00000000b902','authenticated','authenticated','baseline-foreign@example.invalid','{}','{}',now(),now());
INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 SELECT ('00000000-0000-4000-8000-00000000b91'||n),'00000000-0000-4000-8000-00000000b901','failed_terminal','server_replay_limit_reached','replay_exhausted'
 FROM generate_series(1,2) n;
INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy)
 SELECT ('00000000-0000-4000-8000-00000000b91'||n)::UUID,'00000000-0000-4000-8000-00000000b901','{}',0.9,TRUE,'flash','private'
 FROM generate_series(1,2) n;

SELECT extensions.ok(has_function_privilege('authenticated','public.get_owned_observation_enrollment_selection(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_owned_observation_enrollment_selection(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.get_owned_observation_enrollment_selection(jsonb,integer)','EXECUTE'),'pair reader is authenticated-only');
SELECT set_config('request.jwt.claims','{}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',11)$$,'22023','invalid_analysis_history','authenticated grant still requires caller identity');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000b901","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',11)$$,'55000','analysis_history_unavailable','inactive reader denies pair');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)$$,'22023','invalid_analysis_history','pair requires current reader11');
RESET ROLE;
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,state_reader_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',11)$$,'P0002','analysis_history_not_found','pair does not create history');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911","analysis_id":null}',11)$$,'22023','invalid_analysis_history','caller cannot nominate baseline');
RESET ROLE;
UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE,saved_import_enabled=TRUE;
SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000b911',9); END $$;
RESET ROLE;
UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE,saved_import_enabled=FALSE;
CREATE TEMP TABLE pair_reply(value JSONB);
GRANT ALL ON pair_reply TO authenticated;
SET LOCAL ROLE authenticated;
INSERT INTO pair_reply SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',11);
SELECT extensions.ok((SELECT value->'baseline_state'=value->'selected_state' FROM pair_reply),'baseline-selected pair is coherent');
RESET ROLE;
DELETE FROM pair_reply;

INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,completed_at,result_snapshot,evidence_manifest)
VALUES('00000000-0000-4000-8000-00000000b999','00000000-0000-4000-8000-00000000b911',2,repeat('a',64),now(),'{"ai_reasoning":"Synthetic identification fixture.","blur_score":0.2,"candidates":null,"colors":[],"common_name":"Monarch Butterfly","confidence_score":0.87,"estimated_size_cm":8.5,"extracted_visual_traits":["orange wings"],"image_quality":{"diagnostic_utility":9,"framing":7,"overall_score":82,"sharpness":8},"inference_tier":"flash","is_biological_subject":true,"is_live_capture":true,"pet_identification":null,"scan_id":"00000000-0000-4000-8000-00000000b911","scientific_name":"Danaus plexippus"}'::JSONB,'{"captured_media":[{"description":{"_0":{"freeText":"Synthetic observation fixture."}}}],"schema_version":1}'::JSONB);

INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000b999',review_snapshot FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000b911';
UPDATE internal.observation_histories SET selected_analysis_id='00000000-0000-4000-8000-00000000b999',state_revision=8 WHERE observation_id='00000000-0000-4000-8000-00000000b911';
SET LOCAL ROLE authenticated;
INSERT INTO pair_reply SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',11);
SELECT extensions.ok((SELECT value#>'{baseline_state,state_revision}'='8'::JSONB AND value#>'{selected_state,state_revision}'='8'::JSONB
 AND value#>>'{baseline_state,selected_analysis_id}'='00000000-0000-4000-8000-00000000b999'
 AND value#>>'{selected_state,selected_analysis_id}'='00000000-0000-4000-8000-00000000b999' FROM pair_reply),'pair retains current selected B and one revision');
SELECT extensions.ok((SELECT value#>>'{baseline_state,analysis,snapshot}'=public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)->>'snapshot'
 AND value->>'baseline_sha256'=public.get_owned_observation_enrollment_baseline('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',9)->>'snapshot_sha256' FROM pair_reply),'baseline uses exact original serializer and digest');
SELECT extensions.ok((SELECT value->'selected_state'=public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911","analysis_id":null}',11)
 AND value-ARRAY['schema_version','baseline_sha256','baseline_state','selected_state']='{}'::JSONB FROM pair_reply),'selected state and closed envelope use existing contract');
RESET ROLE;
SELECT extensions.ok((SELECT state_revision=8 AND selected_analysis_id='00000000-0000-4000-8000-00000000b999' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000b911')
 AND (SELECT count(*) FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000b911')=2,'read preserves both results and selection');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000b902","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_enrollment_selection('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000b911"}',11)$$,'P0002','analysis_history_not_found','foreign account cannot read pair');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
