BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(18);
CREATE FUNCTION pg_temp.seed_saved_observation(owner_id UUID,observation UUID,has_primary BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',now(),now()) ON CONFLICT DO NOTHING;
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,identification_provenance,primary_identification)
 VALUES(observation,owner_id,ARRAY['https://example.invalid/legacy-public.jpg'],0.9,TRUE,'flash','private',CASE WHEN has_primary THEN '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"synthetic_primary_fixture_v1","schema":"merian_identify_primary_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}'::JSONB END,CASE WHEN has_primary THEN '{"version":1,"resolution":"genus","scientific_name":"Savedfixture","common_name":null}'::JSONB END);
END;
$$;

SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811');
SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000e802','00000000-0000-4000-8000-00000000e812');
SELECT extensions.ok(NOT (SELECT state_reader_enabled FROM internal.observation_history_rollout WHERE singleton),'state read defaults closed');
SELECT extensions.ok(has_function_privilege('authenticated','public.get_owned_observation_analysis_state(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_owned_observation_analysis_state(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.get_owned_observation_analysis_state(jsonb,integer)','EXECUTE'),'owner-only exact role grants');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000e801","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000e811',9);
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":null}',9)$$,'55000','analysis_history_unavailable','separate state gate remains closed after enrollment');
RESET ROLE;
UPDATE internal.observation_history_rollout SET state_reader_enabled=TRUE,reader_enabled=FALSE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":null}',9)$$,'55000','analysis_history_unavailable','state gate cannot bypass history reader gate');
RESET ROLE;
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE;
CREATE TEMP TABLE state_read(value JSONB);
GRANT ALL ON state_read TO authenticated;
SET LOCAL ROLE authenticated;
INSERT INTO state_read SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":null}',9);
SELECT extensions.ok((SELECT value->>'state_revision'='1' AND value->>'selection_initialized'='true'
 AND value->>'selected_analysis_id'=(value#>>'{analysis,snapshot}')::JSONB->>'analysis_id' FROM state_read),'null target atomically resolves selected result');
SELECT extensions.ok((SELECT value#>>'{analysis,review_revision}'='0'
 AND (value#>>'{analysis,snapshot}')::JSONB->>'schema_version'='3'
 AND (SELECT count(*) FROM jsonb_object_keys(value#>'{analysis,review_snapshot}'))=7 FROM state_read),'V3 unknown execution and separate seven-field authority');
SELECT extensions.is((SELECT value#>>'{analysis,snapshot}' FROM state_read),
 (public.get_owned_observation_analysis_page('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","before_ordinal":null,"limit":1}',9)#>>'{items,0,snapshot}'),'state and immutable reader bytes agree');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":null}',8)$$,'22023','invalid_analysis_history','old protocol denied');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":true}',9)$$,'22023','invalid_analysis_history','typed target required');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":null,"owner_id":"00000000-0000-4000-8000-00000000e802"}',9)$$,'22023','invalid_analysis_history','owner cannot be supplied');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e812","analysis_id":null}',9)$$,'P0002','analysis_history_not_found','other owner indistinguishable from missing observation');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":"00000000-0000-4000-8000-00000000e899"}',9)$$,'P0002','analysis_history_not_found','missing child does not return current authority');
RESET ROLE;
-- A second synthetic result is unselected. Reading it cannot change selection.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,completed_at,result_snapshot,evidence_manifest)
SELECT '00000000-0000-4000-8000-00000000e899',observation_id,2,repeat('a',64),now(),'{"ai_reasoning":"Synthetic identification fixture.","blur_score":0.2,"candidates":null,"colors":[],"common_name":"Monarch Butterfly","confidence_score":0.87,"estimated_size_cm":8.5,"extracted_visual_traits":["orange wings"],"image_quality":{"diagnostic_utility":9,"framing":7,"overall_score":82,"sharpness":8},"inference_tier":"flash","is_biological_subject":true,"is_live_capture":true,"pet_identification":null,"scan_id":"00000000-0000-4000-8000-00000000e811","scientific_name":"Danaus plexippus"}'::JSONB,'{"captured_media":[{"description":{"_0":{"freeText":"Synthetic observation fixture."}}}],"schema_version":1}'::JSONB FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000e811';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000e899',review_snapshot FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000e811';
SET LOCAL ROLE authenticated;
SELECT extensions.ok((public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":"00000000-0000-4000-8000-00000000e899"}',9)->>'selected_analysis_id')=(SELECT value->>'selected_analysis_id' FROM state_read),'explicit preview does not select');
RESET ROLE;
UPDATE internal.observation_analysis_authorities SET review_revision=1,review_snapshot=review_snapshot||'{"user_identification_override":"Changed fixture","user_review_state":"user_overridden"}' WHERE analysis_id='00000000-0000-4000-8000-00000000e899';
SET LOCAL ROLE authenticated;
SELECT extensions.is((public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":null}',9)->>'state_revision'),'2','inactive authority still advances observation state');
SELECT extensions.is((public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":"00000000-0000-4000-8000-00000000e899"}',9)#>>'{analysis,review_revision}'),'1','target returns own review revision');
RESET ROLE;
SELECT extensions.is((SELECT COUNT(*)::INTEGER FROM internal.observation_history_reconciliation),1,'only authority mutation creates obligation, reads add none');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e801');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_state('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000e811","analysis_id":null}',9)$$,'P0002','analysis_history_not_found','deletion fence wins read');
RESET ROLE;
SELECT extensions.ok(NOT (SELECT selection_enabled OR dispatch_enabled FROM internal.observation_history_rollout WHERE singleton),'state reader does not enable mutations');
SELECT * FROM extensions.finish();
ROLLBACK;
