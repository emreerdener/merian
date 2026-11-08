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

SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911',TRUE);
SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000f902','00000000-0000-4000-8000-00000000f912',TRUE);
INSERT INTO public.explore_posts(id,user_id,scan_id) VALUES('00000000-0000-4000-8000-00000000f940','00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911');
INSERT INTO public.explore_community_requests(id,post_id,scan_id,requested_by) VALUES('00000000-0000-4000-8000-00000000f941','00000000-0000-4000-8000-00000000f940','00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f901');
SELECT extensions.ok(NOT (SELECT rejection_api_enabled FROM internal.observation_history_rollout WHERE singleton),'review gate defaults closed');
SELECT extensions.ok(has_function_privilege('authenticated','public.review_owned_observation_analysis(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('anon','public.review_owned_observation_analysis(jsonb,integer)','EXECUTE')
 AND NOT has_function_privilege('service_role','public.review_owned_observation_analysis(jsonb,integer)','EXECUTE'),'only authenticated wrapper granted');
SELECT extensions.ok(NOT has_table_privilege('authenticated','internal.observation_review_receipts','SELECT')
 AND NOT has_table_privilege('service_role','internal.observation_review_receipts','INSERT'),'receipts private even from service');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,state_reader_enabled=TRUE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000f901","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000f911',9);
RESET ROLE;
CREATE TEMP TABLE review_requests(id TEXT PRIMARY KEY,request JSONB,response JSONB);
INSERT INTO review_requests(id,request)
SELECT 'reject',jsonb_build_object('schema_version',1,'observation_id',observation_id,'analysis_id',selected_analysis_id,
 'operation_id','00000000-0000-4000-8000-00000000f921','expected_observation_revision',1,'expected_review_revision',0,
 'action','reject','undo_operation_id',NULL)
FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000f911';
GRANT ALL ON review_requests TO authenticated;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request,9) FROM review_requests WHERE id='reject'$$,'55000','analysis_history_unavailable','closed gate refuses review');
RESET ROLE;
UPDATE internal.observation_history_rollout SET rejection_api_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request,8) FROM review_requests WHERE id='reject'$$,'22023','invalid_analysis_history','protocol 8 refused');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"owner_id":"00000000-0000-4000-8000-00000000f902"}',9) FROM review_requests WHERE id='reject'$$,'22023','invalid_analysis_history','extra owner cannot widen access');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"expected_review_revision":true}',9) FROM review_requests WHERE id='reject'$$,'22023','invalid_analysis_history','boolean revision refused');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"action":"confirm_primary"}',9) FROM review_requests WHERE id='reject'$$,'22023','invalid_analysis_history','confirmation not silently bound');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"observation_id":"00000000-0000-4000-8000-00000000f912"}',9) FROM review_requests WHERE id='reject'$$,'P0002','analysis_history_not_found','foreign owner concealed');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"analysis_id":"00000000-0000-4000-8000-00000000f999"}',9) FROM review_requests WHERE id='reject'$$,'P0002','analysis_history_not_found','foreign child refused');
UPDATE review_requests SET response=public.review_owned_observation_analysis(request,9) WHERE id='reject';
SELECT extensions.ok((SELECT response->>'outcome'='applied' AND response->>'review_revision'='1' AND response->>'observation_revision'='2' FROM review_requests WHERE id='reject'),'reject has exact resulting revisions');
RESET ROLE;
SELECT extensions.is((SELECT active_projection->>'pending_review' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000f911'),'true','selected rejection is unresolved');
SELECT extensions.is((SELECT ai_identification_review FROM public.scans WHERE id='00000000-0000-4000-8000-00000000f911'),NULL::JSONB,'legacy scan authority was not touched');
SELECT extensions.is((SELECT review_snapshot->>'confirmed_species_identity_revision' FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000f911'),'1','species review cleared with revision');
INSERT INTO review_requests(id,request) SELECT 'stale',request||'{"operation_id":"00000000-0000-4000-8000-00000000f922"}' FROM review_requests WHERE id='reject';
INSERT INTO review_requests(id,request) SELECT 'undo',request||'{"operation_id":"00000000-0000-4000-8000-00000000f923","expected_observation_revision":2,"expected_review_revision":1,"action":"undo","undo_operation_id":"00000000-0000-4000-8000-00000000f921"}' FROM review_requests WHERE id='reject';
SET LOCAL ROLE authenticated;
UPDATE review_requests SET response=public.review_owned_observation_analysis(request,9) WHERE id='stale';
SELECT extensions.is((SELECT response FROM review_requests WHERE id='stale'),(SELECT request||'{"outcome":"revision_conflict"}' FROM review_requests WHERE id='stale'),'stale decision is durable conflict');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"undo_operation_id":"00000000-0000-4000-8000-00000000f999"}',9) FROM review_requests WHERE id='undo'$$,'22023','invalid_identification_review','Undo requires exact accepted rejection');
SELECT extensions.is((SELECT public.get_owned_observation_rejection_undo(request-ARRAY['operation_id','action','undo_operation_id'],9)->>'rejection_operation_id' FROM review_requests WHERE id='undo'),'00000000-0000-4000-8000-00000000f921','rejection eligibility recovers exact original operation without a client receipt');
SELECT extensions.is((SELECT public.get_owned_observation_rejection_undo((request-ARRAY['operation_id','action','undo_operation_id'])||'{"expected_review_revision":0}',9)->>'reason' FROM review_requests WHERE id='undo'),'revision_conflict','lookup validates displayed target revision');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_rejection_undo((request-ARRAY['operation_id','action','undo_operation_id'])||'{"observation_id":"00000000-0000-4000-8000-00000000f912"}',9) FROM review_requests WHERE id='undo'$$,'P0002','analysis_history_not_found','lookup conceals another owner');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_rejection_undo(request-ARRAY['operation_id','action','undo_operation_id'],8) FROM review_requests WHERE id='undo'$$,'22023','invalid_analysis_history','lookup refuses unsupported reader');
UPDATE review_requests SET response=public.review_owned_observation_analysis(request,9) WHERE id='undo';
RESET ROLE;
SELECT extensions.is((SELECT review_snapshot->>'user_review_state' FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000f911'),'unreviewed','Undo never restores confirmation');
SELECT extensions.is((SELECT active_projection->>'pending_review' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000f911'),'false','Undo clears rejection');
-- A second immutable analysis stays selected while the original is reviewed.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000f932',observation_id,2,analysis_id,repeat('b',64),result_snapshot,
 '{"schema_version":1,"captured_media":[]}',now() FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000f911';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000f932',review_snapshot FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000f911';
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"analysis_id":"00000000-0000-4000-8000-00000000f932"}',9) FROM review_requests WHERE id='reject'$$,'22023','analysis_history_operation_conflict','operation cannot be rebound to another child');
RESET ROLE;
SELECT extensions.throws_ok($$INSERT INTO public.explore_community_requests(scan_id) VALUES('00000000-0000-4000-8000-00000000f911')$$,'55000','analysis_bound_review_required','legacy community insertion refused before writes');
SELECT extensions.throws_ok($$UPDATE public.explore_community_requests SET status='withdrawn',withdrawn_at=now() WHERE id='00000000-0000-4000-8000-00000000f941'$$,'55000','analysis_bound_review_required','existing community authority cannot change without child binding');
SELECT extensions.throws_ok($$UPDATE public.explore_community_requests SET scan_id='00000000-0000-4000-8000-00000000f912' WHERE id='00000000-0000-4000-8000-00000000f941'$$,'55000','analysis_bound_review_required','legacy reparent cannot move a request out of enrolled history');
SELECT set_config('merian.ai_identification_review','on',TRUE);
SELECT extensions.throws_ok($$UPDATE public.scans SET ai_identification_review=(SELECT review_snapshot->'ai_identification_review' FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000f932') WHERE id='00000000-0000-4000-8000-00000000f911'$$,'55000','analysis_bound_review_required','direct legacy authority projection refused');
SELECT set_config('merian.ai_identification_review','',TRUE);
UPDATE internal.observation_history_rollout SET selection_enabled=TRUE,selection_api_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT public.select_owned_observation_analysis(jsonb_build_object('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000f911','analysis_id','00000000-0000-4000-8000-00000000f932','operation_id','00000000-0000-4000-8000-00000000f924','expected_observation_revision',3,'expected_review_revision',0),9);
RESET ROLE;
INSERT INTO review_requests(id,request) SELECT 'inactive',request||'{"operation_id":"00000000-0000-4000-8000-00000000f925","expected_observation_revision":4,"expected_review_revision":2}' FROM review_requests WHERE id='reject';
SET LOCAL ROLE authenticated;
UPDATE review_requests SET response=public.review_owned_observation_analysis(request,9) WHERE id='inactive';
RESET ROLE;
SELECT extensions.ok((SELECT state_revision=5 AND selected_analysis_id='00000000-0000-4000-8000-00000000f932' AND active_projection->>'pending_review'='false' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000f911'),'inactive review advances parent without changing selection or projection');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_history_reconciliation WHERE observation_id='00000000-0000-4000-8000-00000000f911'),4,'one obligation for each selection or authority transition');
-- Advance only another child's review: the rejection receipt's parent revision is not today's CAS.
INSERT INTO review_requests(id,request) SELECT 'other-child',request||'{"analysis_id":"00000000-0000-4000-8000-00000000f932","operation_id":"00000000-0000-4000-8000-00000000f928","expected_observation_revision":5,"expected_review_revision":0}' FROM review_requests WHERE id='reject';
SET LOCAL ROLE authenticated;
UPDATE review_requests SET response=public.review_owned_observation_analysis(request,9) WHERE id='other-child';
SELECT extensions.is((SELECT public.get_owned_observation_rejection_undo((request-ARRAY['operation_id','action','undo_operation_id'])||'{"expected_observation_revision":6,"expected_review_revision":3}',9)->>'rejection_operation_id' FROM review_requests WHERE id='inactive'),'00000000-0000-4000-8000-00000000f925','older parent receipt stays eligible after another child review');
RESET ROLE;
-- A new immutable child starts with an independently advanced nested AI counter.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000f933',observation_id,3,analysis_id,repeat('c',64),result_snapshot,
 '{"schema_version":1,"captured_media":[]}',now() FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000f932';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000f933',jsonb_set(jsonb_set(review_snapshot,'{ai_identification_review,revision}','7'),'{ai_identification_review,state}','"clear"') FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000f932';
INSERT INTO review_requests(id,request) SELECT 'independent-counter',request||'{"analysis_id":"00000000-0000-4000-8000-00000000f933","operation_id":"00000000-0000-4000-8000-00000000f929","expected_observation_revision":6,"expected_review_revision":0}' FROM review_requests WHERE id='reject';
SET LOCAL ROLE authenticated;
UPDATE review_requests SET response=public.review_owned_observation_analysis(request,9) WHERE id='independent-counter';
SELECT extensions.is((SELECT public.get_owned_observation_rejection_undo((request-ARRAY['operation_id','action','undo_operation_id'])||'{"expected_observation_revision":7,"expected_review_revision":1}',9)->>'status' FROM review_requests WHERE id='independent-counter'),'available','nested AI counter 8 does not replace outer review counter 1');
RESET ROLE;
SELECT extensions.is((SELECT review_snapshot#>>'{ai_identification_review,revision}' FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000f933'),'8','fixture proves independent nested counter');
SELECT extensions.ok(has_function_privilege('authenticated','public.get_owned_observation_rejection_undo(jsonb,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.get_owned_observation_rejection_undo(jsonb,integer)','EXECUTE') AND NOT has_function_privilege('service_role','public.get_owned_observation_rejection_undo(jsonb,integer)','EXECUTE'),'rejection recovery lookup is authenticated only');
-- Malformed private receipts fail closed even when their operation association matches.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000f934',observation_id,4,analysis_id,repeat('d',64),result_snapshot,evidence_manifest,now() FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000f933';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000f934',jsonb_set(review_snapshot,'{ai_identification_review,operation_id}','"00000000-0000-4000-8000-00000000f930"') FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000f933';
INSERT INTO internal.observation_review_receipts(observation_id,analysis_id,operation_id,request_identity,receipt) VALUES('00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f934','00000000-0000-4000-8000-00000000f930','{}','{}');
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_rejection_undo('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000f911","analysis_id":"00000000-0000-4000-8000-00000000f934","expected_observation_revision":7,"expected_review_revision":0}',9)->>'reason','rejection_changed','missing receipt action/outcome/revision cannot qualify Undo');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000f911","analysis_id":"00000000-0000-4000-8000-00000000f934","operation_id":"00000000-0000-4000-8000-00000000f931","expected_observation_revision":7,"expected_review_revision":0,"action":"undo","undo_operation_id":"00000000-0000-4000-8000-00000000f930"}',9)$$,'22023','invalid_identification_review','mutation also denies malformed receipt association');
RESET ROLE;
UPDATE internal.observation_history_rollout SET rejection_api_enabled=FALSE,reader_enabled=FALSE,state_reader_enabled=FALSE;
SET LOCAL ROLE authenticated;
SELECT extensions.ok((SELECT bool_and(public.review_owned_observation_analysis(request,9)=response) FROM review_requests),'all outcomes replay unchanged after later authority and gate closure');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_rejection_undo(request-ARRAY['operation_id','action','undo_operation_id'],9) FROM review_requests WHERE id='undo'$$,'55000','analysis_history_unavailable','lookup does not bypass closed gates');
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request||'{"expected_observation_revision":5}',9) FROM review_requests WHERE id='stale'$$,'22023','analysis_history_operation_conflict','changed retry cannot overwrite history');
RESET ROLE;
SELECT extensions.throws_ok($$UPDATE internal.observation_review_receipts SET receipt='{}' WHERE observation_id='00000000-0000-4000-8000-00000000f911'$$,'22023','analysis_history_evidence_immutable','review outcomes cannot be rewritten');
-- Both legacy RPCs and carry sources fail under the same enrollment fence.
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.require_legacy_scan_review('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911')$$,'55000','analysis_bound_review_required','legacy preflight cannot admit enrolled result');
SELECT extensions.throws_ok($$SELECT public.apply_verified_scan_species_review('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911',0,'clear',NULL,NULL)$$,'55000','analysis_bound_review_required','legacy species commit rechecks enrollment');
SELECT extensions.throws_ok($$SELECT public.apply_scan_identification_review('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f911',0,'00000000-0000-4000-8000-00000000f926','reject',NULL,NULL,0,NULL,NULL)$$,'55000','analysis_bound_review_required','legacy rejection commit blocked');
RESET ROLE;
SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f913',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.apply_scan_identification_review('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f913',0,'00000000-0000-4000-8000-00000000f927','carry',NULL,NULL,0,'00000000-0000-4000-8000-00000000f911',1)$$,'55000','analysis_bound_review_required','carry cannot export an enrolled rejection');
SELECT extensions.lives_ok($$SELECT public.require_legacy_scan_review('00000000-0000-4000-8000-00000000f901','00000000-0000-4000-8000-00000000f913')$$,'unenrolled review remains admitted');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000f901","role":"authenticated"}',TRUE);
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000f911','00000000-0000-4000-8000-00000000f901');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.review_owned_observation_analysis(request,9) FROM review_requests WHERE id='reject'$$,'P0002','analysis_history_not_found','deletion wins over accepted replay');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_rejection_undo(request-ARRAY['operation_id','action','undo_operation_id'],9) FROM review_requests WHERE id='undo'$$,'P0002','analysis_history_not_found','deletion wins over eligibility lookup');
RESET ROLE;
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000f911';
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_review_receipts WHERE observation_id='00000000-0000-4000-8000-00000000f911'),0,'deletion cascades private outcomes');
SELECT * FROM extensions.finish();
ROLLBACK;
