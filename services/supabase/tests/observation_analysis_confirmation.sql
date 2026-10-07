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

SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000fa01',('00000000-0000-4000-8000-00000000fa1'||n)::UUID,CASE n WHEN 2 THEN 'legacy' WHEN 3 THEN 'nonbio' ELSE 'species' END) FROM generate_series(1,3) n;
SELECT extensions.ok(NOT (SELECT confirmation_api_enabled FROM internal.observation_history_rollout WHERE singleton),'confirmation defaults closed');
SELECT extensions.ok(has_function_privilege('service_role','public.prepare_observation_analysis_confirmation(uuid,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.prepare_observation_analysis_confirmation(uuid,jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.complete_observation_analysis_confirmation(uuid,jsonb,integer,text,jsonb)','EXECUTE')
 AND NOT has_function_privilege('authenticated','public.complete_observation_analysis_confirmation(uuid,jsonb,integer,text,jsonb)','EXECUTE'),'only service wrappers accept verified proof');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_confirmation_intents','SELECT')
 AND NOT has_table_privilege('authenticated','internal.observation_confirmation_intents','INSERT'),'intent private even from service');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,state_reader_enabled=TRUE,rejection_api_enabled=TRUE,selection_enabled=TRUE,selection_api_enabled=TRUE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.enroll_owned_observation_history(('00000000-0000-4000-8000-00000000fa1'||n)::UUID,9) FROM generate_series(1,3) n;
RESET ROLE;
CREATE TEMP TABLE confirmations(id TEXT PRIMARY KEY,request JSONB,response JSONB);
CREATE TEMP TABLE proof(taxon JSONB);
INSERT INTO proof VALUES('{"scientific_name":"Savedfixture accepted","gbif_taxon_key":987699791,"rank":"SPECIES","status":"ACCEPTED","kingdom":"Plantae"}');
INSERT INTO confirmations(id,request) SELECT 'initial',jsonb_build_object('schema_version',1,'observation_id',observation_id,'analysis_id',selected_analysis_id,
 'operation_id','00000000-0000-4000-8000-00000000fa21','expected_observation_revision',1,'expected_review_revision',0,
 'action','confirm_primary','scientific_name',NULL) FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
GRANT ALL ON confirmations,proof TO service_role,authenticated;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='initial'$$,'55000','analysis_history_unavailable','closed gate prevents verification admission');
RESET ROLE;
UPDATE internal.observation_history_rollout SET confirmation_api_enabled=TRUE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,8) FROM confirmations WHERE id='initial'$$,'22023','invalid_analysis_history','protocol8 refused');
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request||'{"owner_id":"00000000-0000-4000-8000-00000000fa01"}',9) FROM confirmations WHERE id='initial'$$,'22023','invalid_analysis_history','body cannot supply owner');
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request||'{"scientific_name":"injected"}',9) FROM confirmations WHERE id='initial'$$,'22023','invalid_analysis_history','primary name comes from stored evidence');
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa02',request,9) FROM confirmations WHERE id='initial'$$,'P0002','analysis_history_not_found','foreign owner concealed');
SELECT extensions.throws_ok($$SELECT public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Savedfixture original',(SELECT taxon FROM proof)) FROM confirmations WHERE id='initial'$$,'55000','analysis_history_unavailable','completion requires persisted admission');
UPDATE confirmations SET response=public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) WHERE id='initial';
SELECT extensions.ok((SELECT response=jsonb_build_object('schema_version',1,'status','verify','request',request,'scientific_name','Savedfixture original') FROM confirmations WHERE id='initial'),'admission freezes exact primary name and request');
SELECT extensions.ok((SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9)=response FROM confirmations WHERE id='initial'),'unfinished retry reuses intent');
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request||'{"action":"confirm_name","scientific_name":"Changed query"}',9) FROM confirmations WHERE id='initial'$$,'22023','analysis_history_operation_conflict','pending operation cannot change action or query');
SELECT extensions.throws_ok($$SELECT public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Changed query',(SELECT taxon FROM proof)) FROM confirmations WHERE id='initial'$$,'22023','analysis_history_operation_conflict','verified query must match admitted name');
RESET ROLE;
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),1,'admission never changes authority');
SELECT extensions.throws_ok($$UPDATE internal.observation_confirmation_intents SET scientific_name='Changed query'$$,'22023','analysis_history_evidence_immutable','pending intents immutable');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis((request-'scientific_name')||'{"action":"reject","undo_operation_id":null}',9) FROM confirmations WHERE id='initial'$$,'22023','analysis_history_operation_conflict','Reject cannot claim pending confirmation operation');
SELECT public.review_owned_observation_analysis((request-'scientific_name')||'{"operation_id":"00000000-0000-4000-8000-00000000fa22","action":"reject","undo_operation_id":null}',9) FROM confirmations WHERE id='initial';
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
UPDATE confirmations SET response=public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Savedfixture original',(SELECT taxon FROM proof)) WHERE id='initial';
SELECT extensions.is((SELECT response#>>'{receipt,outcome}' FROM confirmations WHERE id='initial'),'revision_conflict','review change during verification gives durable conflict');
INSERT INTO confirmations(id,request) SELECT 'accept',request||'{"operation_id":"00000000-0000-4000-8000-00000000fa23","expected_observation_revision":2,"expected_review_revision":1}' FROM confirmations WHERE id='initial';
SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='accept';
UPDATE confirmations SET response=public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Savedfixture original',(SELECT taxon FROM proof)) WHERE id='accept';
SELECT extensions.is((SELECT response->'receipt' FROM confirmations WHERE id='accept'),(SELECT request||'{"outcome":"applied","observation_revision":3,"review_revision":2}' FROM confirmations WHERE id='accept'),'confirmed retry receipt binds both advanced revisions');
RESET ROLE;
SELECT extensions.ok((SELECT active_projection->>'verified'='true' AND active_projection->>'pending_review'='false' AND active_projection->>'scientific_name'='Savedfixture accepted' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),'explicit confirmation clears rejection and accepts verified synonym canonical name');
SELECT extensions.ok((SELECT review_snapshot->>'user_review_state'='ai_confirmed' AND review_snapshot#>>'{ai_identification_review,state}'='clear' FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),'authority records primary confirmation');
SELECT extensions.is((SELECT confirmed_species_identity FROM public.scans WHERE id='00000000-0000-4000-8000-00000000fa11'),NULL::JSONB,'legacy scan authority untouched');
INSERT INTO confirmations(id,request) SELECT 'unverified',request||'{"operation_id":"00000000-0000-4000-8000-00000000fa24","expected_observation_revision":3,"expected_review_revision":2,"action":"confirm_name","scientific_name":"Unverified fixture"}' FROM confirmations WHERE id='initial';
SET LOCAL ROLE service_role;
SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='unverified';
UPDATE confirmations SET response=public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Unverified fixture',NULL) WHERE id='unverified';
SELECT extensions.is((SELECT response#>>'{receipt,outcome}' FROM confirmations WHERE id='unverified'),'not_verified','negative verification durable');
SELECT extensions.ok((SELECT public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Unverified fixture',(SELECT taxon FROM proof))=response FROM confirmations WHERE id='unverified'),'negative replay cannot later become confirmation');
RESET ROLE;
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),3,'negative verification does not change authority');
-- Confirm a nonselected child without transferring authority to the selected child.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000fa32',observation_id,2,analysis_id,repeat('c',64),result_snapshot,'{"schema_version":1,"captured_media":[]}',now() FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000fa32',review_snapshot FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.select_owned_observation_analysis('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000fa11","analysis_id":"00000000-0000-4000-8000-00000000fa32","operation_id":"00000000-0000-4000-8000-00000000fa25","expected_observation_revision":3,"expected_review_revision":0}',9);
RESET ROLE;
CREATE TEMP TABLE before_inactive AS SELECT active_projection FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11';
INSERT INTO confirmations(id,request) SELECT 'inactive',request||'{"operation_id":"00000000-0000-4000-8000-00000000fa26","expected_observation_revision":4,"expected_review_revision":2,"action":"confirm_name","scientific_name":"Savedfixture synonym"}' FROM confirmations WHERE id='initial';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='inactive';
UPDATE confirmations SET response=public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Savedfixture synonym',(SELECT taxon FROM proof)) WHERE id='inactive';
RESET ROLE;
SELECT extensions.ok((SELECT state_revision=5 AND selected_analysis_id='00000000-0000-4000-8000-00000000fa32' AND active_projection=(SELECT active_projection FROM before_inactive) FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),'inactive confirmation advances revision but preserves selection and active authority');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_history_reconciliation WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),4,'one reconciliation per accepted authority or selection transition');
SELECT extensions.ok((SELECT review_snapshot->>'user_review_state'='user_overridden' AND review_snapshot->>'user_identification_override'='Savedfixture synonym' AND review_snapshot->>'user_confirmed_identification'='false' FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000fa11' AND analysis_id<>'00000000-0000-4000-8000-00000000fa32'),'named confirmation records explicit correction without confirming AI');
-- Exact receipt association survives unrelated parent revisions and distinct AI counters.
SELECT extensions.ok(NOT (SELECT confirmation_undo_api_enabled FROM internal.observation_history_rollout WHERE singleton),'Undo confirmation defaults closed');
UPDATE internal.observation_history_rollout SET confirmation_undo_api_enabled=TRUE;
SELECT extensions.ok(has_function_privilege('authenticated','public.get_owned_observation_confirmation_undo(jsonb,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.get_owned_observation_confirmation_undo(jsonb,integer)','EXECUTE') AND NOT has_function_privilege('service_role','internal.observation_confirmation_undo_eligibility(uuid,uuid)','EXECUTE'),'lookup owner-only; helper private');
CREATE TEMP TABLE undo_cases(id TEXT PRIMARY KEY, request JSONB, response JSONB);
INSERT INTO undo_cases(id,request) SELECT 'named', (request-'scientific_name')||jsonb_build_object('operation_id','00000000-0000-4000-8000-00000000fa80','action','undo_confirmation','undo_operation_id',request->>'operation_id','expected_observation_revision',5,'expected_review_revision',3) FROM confirmations WHERE id='inactive';
GRANT ALL ON undo_cases TO authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.is((SELECT public.get_owned_observation_confirmation_undo(request-ARRAY['operation_id','action','undo_operation_id'],9)->>'confirmation_operation_id' FROM undo_cases WHERE id='named'),'00000000-0000-4000-8000-00000000fa26','named confirmation discovered without exposing name or receipt');
SELECT extensions.is((SELECT public.get_owned_observation_confirmation_undo((request-ARRAY['operation_id','action','undo_operation_id'])||'{"expected_review_revision":2}',9)->>'reason' FROM undo_cases WHERE id='named'),'revision_conflict','lookup rejects stale displayed revision');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"undo_operation_id":"00000000-0000-4000-8000-00000000fa23"}',9) FROM undo_cases WHERE id='named'$$,'22023','invalid_identification_review','older applied confirmation cannot replace current association');
UPDATE undo_cases SET response=public.review_owned_observation_analysis(request,9) WHERE id='named';
SELECT extensions.is((SELECT response->>'outcome' FROM undo_cases WHERE id='named'),'applied','named Undo applied');
RESET ROLE;
SELECT extensions.ok((SELECT review_snapshot->>'user_review_state'='unreviewed' AND review_snapshot->'user_identification_override'='null'::JSONB AND review_snapshot->'confirmed_species_identity'='null'::JSONB AND review_snapshot#>>'{ai_identification_review,state}'='clear' FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000fa11' AND analysis_id<>'00000000-0000-4000-8000-00000000fa32'),'Undo removes correction without restoring earlier rejection');
SELECT extensions.ok((SELECT state_revision=6 AND selected_analysis_id='00000000-0000-4000-8000-00000000fa32' AND active_projection=(SELECT active_projection FROM before_inactive) FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),'historical Undo preserves selection and selected projection');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.observation_review_receipts WHERE operation_id='00000000-0000-4000-8000-00000000fa26'),'original confirmation retained');
-- Confirm selected child, then change selection: original receipt global revision becomes older.
INSERT INTO confirmations(id,request) SELECT 'undo-primary-source',request||'{"analysis_id":"00000000-0000-4000-8000-00000000fa32","operation_id":"00000000-0000-4000-8000-00000000fa81","expected_observation_revision":6,"expected_review_revision":0}' FROM confirmations WHERE id='initial';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='undo-primary-source';
UPDATE confirmations SET response=public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,'Savedfixture original',(SELECT taxon FROM proof)) WHERE id='undo-primary-source';
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fa01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.select_owned_observation_analysis((request-ARRAY['scientific_name','action'])||'{"operation_id":"00000000-0000-4000-8000-00000000fa82","expected_observation_revision":7,"expected_review_revision":4}',9) FROM confirmations WHERE id='initial';
INSERT INTO undo_cases(id,request) SELECT 'primary',(request-'scientific_name')||'{"operation_id":"00000000-0000-4000-8000-00000000fa83","action":"undo_confirmation","undo_operation_id":"00000000-0000-4000-8000-00000000fa81","expected_observation_revision":8,"expected_review_revision":1}' FROM confirmations WHERE id='undo-primary-source';
SELECT extensions.is((SELECT public.get_owned_observation_confirmation_undo(request-ARRAY['operation_id','action','undo_operation_id'],9)->>'status' FROM undo_cases WHERE id='primary'),'available','older receipt parent revision remains eligible after selection');
UPDATE undo_cases SET response=public.review_owned_observation_analysis(request,9) WHERE id='primary';
SELECT extensions.is((SELECT response->>'outcome' FROM undo_cases WHERE id='primary'),'applied','primary Undo applies with independent nested AI counter');
RESET ROLE;
SELECT extensions.ok((SELECT review_revision=2 AND review_snapshot#>>'{ai_identification_review,revision}'='4' AND review_snapshot->>'user_confirmed_identification'='false' AND review_snapshot->>'user_review_state'='unreviewed' FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000fa32'),'outer target revision and nested AI counter increment independently');
UPDATE internal.observation_history_rollout SET confirmation_undo_api_enabled=FALSE;
SET LOCAL ROLE authenticated;
SELECT extensions.ok((SELECT bool_and(public.review_owned_observation_analysis(request,9)=response) FROM undo_cases),'lost reply replays exact Undo before closed gate');
RESET ROLE;

-- Fail closed for imported evidence with no explicit primary and nonbiology.
INSERT INTO confirmations(id,request) SELECT 'unsupported'||observation_id, jsonb_build_object('schema_version',1,'observation_id',observation_id,'analysis_id',selected_analysis_id,'operation_id',gen_random_uuid(),'expected_observation_revision',1,'expected_review_revision',0,'action','confirm_name','scientific_name','Savedfixture accepted') FROM internal.observation_histories WHERE observation_id IN ('00000000-0000-4000-8000-00000000fa12','00000000-0000-4000-8000-00000000fa13');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='unsupported00000000-0000-4000-8000-00000000fa12'$$,'22023','species_review_requires_primary','legacy without primary remains held');
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='unsupported00000000-0000-4000-8000-00000000fa13'$$,'22023','invalid_identification_review','nonbiological authority cannot be confirmed');
RESET ROLE;
UPDATE internal.observation_history_rollout SET confirmation_api_enabled=FALSE,reader_enabled=FALSE,state_reader_enabled=FALSE;
SET LOCAL ROLE service_role;
SELECT extensions.ok((SELECT bool_and(public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9)=response AND public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9,NULL,NULL)=response) FROM confirmations WHERE response IS NOT NULL),'all terminal outcomes replay before gates without reapplying authority');
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa01');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fa01',request,9) FROM confirmations WHERE id='accept'$$,'P0002','analysis_history_not_found','deletion wins over completed retry');
RESET ROLE;
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000fa11';
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_confirmation_intents WHERE observation_id='00000000-0000-4000-8000-00000000fa11'),0,'deletion cascades private intents');
SELECT * FROM extensions.finish();
ROLLBACK;
