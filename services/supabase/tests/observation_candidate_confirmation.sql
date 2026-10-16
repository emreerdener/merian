\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.seed_saved_observation(owner_id UUID,observation UUID,variant TEXT DEFAULT 'species') RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT||'@example.invalid','{}','{}',now(),now()) ON CONFLICT DO NOTHING;
 INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
 VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
 INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,identification_provenance,primary_identification)
 VALUES(observation,owner_id,ARRAY['https://example.invalid/legacy-public.jpg'],0.9,variant<>'nonbio','flash','private',CASE WHEN variant<>'legacy' THEN '{"version":2,"provider":"openai","binding":"openai_photo_v1","model":"gpt-6-sol","variant":"multimodal","operation":"scan_identification","policy_version":2,"prompt":"synthetic_primary_fixture_v1","schema":"merian_identify_primary_v1","confidence":"openai_unqualified_v1","diagnostic_trigger":null,"prompt_diagnostic_trigger":null,"safety":"openai_photo_moderation_v1","timeout_ms":90000,"generation":{"max_output_tokens":8192,"reasoning_effort":"low","image_detail":"high"}}'::JSONB END,CASE WHEN variant='species' THEN '{"version":1,"resolution":"species","scientific_name":"Savedfixture original","common_name":null}'::JSONB WHEN variant='nonbio' THEN '{"version":1,"resolution":"non_biological","scientific_name":null,"common_name":null}'::JSONB END);
END;
$$;

SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,state_reader_enabled=TRUE,confirmation_api_enabled=TRUE,confirmation_undo_api_enabled=TRUE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000fa11',9);
RESET ROLE;
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000fa32',observation_id,2,analysis_id,repeat('c',64),
 result_snapshot||'{"candidates":[{"taxon_rank":"species","scientific_name":"Savedfixture alternative","confidence_score":0.4},{"taxon_rank":"species","scientific_name":"Savedfixture second","confidence_score":0.2}]}',
 '{"schema_version":1,"captured_media":[]}',now()
FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000fa32',review_snapshot FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
CREATE TEMP TABLE candidate_request AS SELECT jsonb_build_object('schema_version',2,'observation_id',observation_id,'analysis_id','00000000-0000-4000-8000-00000000fa32',
 'operation_id','00000000-0000-4000-8000-00000000fa41','expected_observation_revision',state_revision,'expected_review_revision',0,'action','confirm_name','scientific_name','Savedfixture alternative',
 'candidate_reference',jsonb_build_object('version',1,'analysis_id','00000000-0000-4000-8000-00000000fa32','representation','stored_species_candidates_v1','ordinal',0)) AS request,
 NULL::JSONB AS response FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
CREATE TEMP TABLE candidate_before AS SELECT selected_analysis_id,active_projection FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
CREATE TEMP TABLE candidate_evidence AS SELECT * FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000fa32';
GRANT ALL ON candidate_request TO service_role,authenticated;
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.observation_candidate_name(uuid,jsonb,jsonb,jsonb)','EXECUTE') AND NOT has_function_privilege('authenticated','internal.observation_candidate_name(uuid,jsonb,jsonb,jsonb)','EXECUTE'),'resolver is ungranted');
SELECT extensions.is(internal.observation_candidate_name(analysis_id,result_snapshot,evidence_manifest,request->'candidate_reference'),'Savedfixture alternative','raw ordinal resolves exact saved name') FROM candidate_evidence,candidate_request;
SELECT extensions.is(internal.observation_candidate_name(analysis_id,result_snapshot,'{"schema_version":3}',request->'candidate_reference'),NULL::TEXT,'opaque imported candidates unsupported') FROM candidate_evidence,candidate_request;
SELECT extensions.is(internal.observation_candidate_name(analysis_id,result_snapshot||'{"candidates":[{"scientific_name":"Savedfixture alternative","confidence_score":0.4}]}',evidence_manifest,request->'candidate_reference'),NULL::TEXT,'rankless name cannot prove membership') FROM candidate_evidence,candidate_request;
SELECT extensions.is(internal.observation_candidate_name(analysis_id,result_snapshot||'{"primary_identification":{"resolution":"genus"}}',evidence_manifest,request->'candidate_reference'),NULL::TEXT,'broader primary never implies candidate species provenance') FROM candidate_evidence,candidate_request;
SELECT extensions.is(internal.observation_candidate_name(analysis_id,result_snapshot||'{"candidates":[{"taxon_rank":"species","scientific_name":"Savedfixture alternative","confidence_score":2}]}',evidence_manifest,request->'candidate_reference'),NULL::TEXT,'invalid score fails closed') FROM candidate_evidence,candidate_request;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request||'{"scientific_name":"Savedfixture forged"}',9) FROM candidate_request$$,'22023','invalid_analysis_history','name must match saved member');
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',jsonb_set(request,'{candidate_reference,analysis_id}','"00000000-0000-4000-8000-00000000fa33"'),9) FROM candidate_request$$,'22023','invalid_analysis_history','cross-child reference fails');
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',jsonb_set(request,'{candidate_reference,ordinal}','2'),9) FROM candidate_request$$,'22023','invalid_analysis_history','unsupported ordinal fails');
UPDATE candidate_request SET response=public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9);
SELECT extensions.ok(response->'request'=request AND response->>'scientific_name'='Savedfixture alternative','preparation retains full reference and derived query') FROM candidate_request;
SELECT extensions.ok(public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9)=response,'preparation replay exact') FROM candidate_request;
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',jsonb_set(request,'{candidate_reference,ordinal}','1'),9) FROM candidate_request$$,'22023','analysis_history_operation_conflict','same UUID cannot select different member');
UPDATE candidate_request SET response=public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Savedfixture alternative','{"scientific_name":"Savedfixture accepted","gbif_taxon_key":987699791,"rank":"SPECIES","status":"ACCEPTED","kingdom":"Plantae"}');
SELECT extensions.ok(response#>>'{receipt,outcome}'='applied' AND response#>'{receipt,candidate_reference}'=request->'candidate_reference','applied receipt preserves candidate reference') FROM candidate_request;
RESET ROLE;
SELECT extensions.ok((SELECT selected_analysis_id=(SELECT selected_analysis_id FROM candidate_before) AND active_projection=(SELECT active_projection FROM candidate_before) FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),'historical candidate confirmation does not select or project child');
SELECT extensions.is(internal.observation_confirmation_undo_eligibility('00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa32')->>'confirmation_action','confirm_name','candidate correction remains named Undo');
UPDATE internal.observation_history_rollout SET confirmation_api_enabled=FALSE;
SET LOCAL ROLE service_role;
SELECT extensions.ok(public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,NULL,NULL)=response,'lost reply replays original candidate receipt before closed gate') FROM candidate_request;
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.review_owned_observation_analysis(jsonb_build_object('schema_version',1,'observation_id',request->>'observation_id','analysis_id',request->>'analysis_id','operation_id','00000000-0000-4000-8000-00000000fa42','expected_observation_revision',response#>'{receipt,observation_revision}','expected_review_revision',response#>'{receipt,review_revision}','action','undo_confirmation','undo_operation_id',request->>'operation_id'),9)->>'outcome','applied','Undo applies to candidate correction') FROM candidate_request;
RESET ROLE;
SELECT extensions.ok((SELECT review_snapshot->>'user_review_state'='unreviewed' AND review_snapshot->'user_identification_override'='null'::JSONB AND review_snapshot#>>'{ai_identification_review,state}'='clear' FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000fa32'),'Undo exposes original AI without restoring rejection');
SELECT extensions.ok((SELECT current.result_snapshot=before.result_snapshot AND current.evidence_manifest=before.evidence_manifest FROM internal.observation_analysis_results AS current JOIN candidate_evidence AS before USING(analysis_id)),'candidate confirmation and Undo preserve exact evidence');
SELECT * FROM extensions.finish();
ROLLBACK;
