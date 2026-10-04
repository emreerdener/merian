\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
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

SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f811');
SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000f802','00000000-0000-4000-8000-00000000f812');
SELECT extensions.ok(NOT (SELECT selection_api_enabled OR selection_enabled FROM internal.observation_history_rollout WHERE singleton),'selection gates default closed');
SELECT extensions.ok(has_function_privilege('authenticated','public.select_owned_observation_analysis(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.select_owned_observation_analysis(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.select_owned_observation_analysis(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','internal.select_observation_analysis(uuid,jsonb)','EXECUTE'),'owner wrapper only; core not exposed');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,state_reader_enabled=TRUE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000f801","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000f811',9);
RESET ROLE;
-- Re-selecting the imported result exercises CAS without requiring fabricated inference.
CREATE TEMP TABLE selection_requests(id TEXT PRIMARY KEY,request JSONB, response JSONB);
INSERT INTO selection_requests(id,request)
SELECT 'success',jsonb_build_object('schema_version',1,'observation_id',observation_id,'analysis_id',selected_analysis_id,
 'operation_id','00000000-0000-4000-8000-00000000f821','expected_observation_revision',1,'expected_review_revision',0)
FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000f811';
INSERT INTO selection_requests(id,request) SELECT 'conflict',request||'{"operation_id":"00000000-0000-4000-8000-00000000f822"}' FROM selection_requests WHERE id='success';
GRANT ALL ON selection_requests TO authenticated;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request,9) FROM selection_requests WHERE id='success'$$,'55000','analysis_history_unavailable','API defaults closed');
RESET ROLE;
UPDATE internal.observation_history_rollout SET selection_api_enabled=TRUE,selection_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request,8) FROM selection_requests WHERE id='success'$$,'22023','invalid_analysis_history','old reader denied');
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request||'{"owner_id":"00000000-0000-4000-8000-00000000f802"}',9) FROM selection_requests WHERE id='success'$$,'22023','invalid_analysis_history','owner cannot be forged');
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request||'{"expected_review_revision":true}',9) FROM selection_requests WHERE id='success'$$,'22023','invalid_analysis_history','boolean revision denied');
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request||'{"observation_id":"00000000-0000-4000-8000-00000000f812"}',9) FROM selection_requests WHERE id='success'$$,'P0002','analysis_history_not_found','foreign observation concealed');
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request||'{"analysis_id":"00000000-0000-4000-8000-00000000f899"}',9) FROM selection_requests WHERE id='success'$$,'P0002','analysis_history_not_found','missing target is not terminal rejection');
UPDATE selection_requests SET response=public.select_owned_observation_analysis(request,9) WHERE id='success';
SELECT extensions.ok((SELECT response->>'observation_revision'='2' AND response->>'review_revision'='0' AND NOT response ? 'outcome' FROM selection_requests WHERE id='success'),'success preserves seven-field receipt contract');
UPDATE selection_requests SET response=public.select_owned_observation_analysis(request,9) WHERE id='conflict';
SELECT extensions.is((SELECT response FROM selection_requests WHERE id='conflict'),(SELECT request||'{"outcome":"revision_conflict"}' FROM selection_requests WHERE id='conflict'),'conflict records exact request-bound terminal proof');
RESET ROLE;
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_selection_receipts WHERE observation_id='00000000-0000-4000-8000-00000000f811'),2,'one immutable outcome per operation');
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000f811'),2,'conflict does not advance state');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_history_reconciliation WHERE observation_id='00000000-0000-4000-8000-00000000f811'),1,'conflict adds no reconciliation');
UPDATE internal.observation_analysis_authorities SET review_revision=1,review_snapshot=review_snapshot||'{"user_identification_override":"Changed fixture","user_review_state":"user_overridden"}' WHERE observation_id='00000000-0000-4000-8000-00000000f811';
UPDATE internal.observation_history_rollout SET selection_api_enabled=FALSE,selection_enabled=FALSE,reader_enabled=FALSE,state_reader_enabled=FALSE;
SET LOCAL ROLE authenticated;
SELECT extensions.ok((SELECT bool_and(public.select_owned_observation_analysis(request,9)=response) FROM selection_requests),'success and rejection replay after authority changes and all gates close');
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request||'{"expected_observation_revision":3}',9) FROM selection_requests WHERE id='conflict'$$,'22023','analysis_history_operation_conflict','changed retry cannot become a new selection');
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request||'{"operation_id":"00000000-0000-4000-8000-00000000f823"}',9) FROM selection_requests WHERE id='conflict'$$,'55000','analysis_history_unavailable','fresh request stays gated');
RESET ROLE;
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000f811'),3,'replays never reinstall old state');
SELECT extensions.throws_ok($$UPDATE internal.observation_selection_receipts SET receipt='{}' WHERE observation_id='00000000-0000-4000-8000-00000000f811'$$,'22023','analysis_history_evidence_immutable','terminal outcome cannot be rewritten');
SELECT set_config('request.jwt.claims','{}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request,9) FROM selection_requests WHERE id='success'$$,'22023','invalid_analysis_history','missing authenticated subject denied even on replay');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000f801","role":"authenticated"}',TRUE);
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f801');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.select_owned_observation_analysis(request,9) FROM selection_requests WHERE id='success'$$,'P0002','analysis_history_not_found','deletion fence wins even over replay');
RESET ROLE;
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000f811';
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_selection_receipts WHERE observation_id='00000000-0000-4000-8000-00000000f811'),0,'deletion cascades all outcomes');
SELECT * FROM extensions.finish();
ROLLBACK;
