\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN COMMUNITY HISTORY HELPERS
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

CREATE FUNCTION pg_temp.seed_bound_community(owner_id UUID,observation UUID,request UUID,post UUID,bind_result BOOLEAN DEFAULT TRUE) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE analysis UUID;
BEGIN
 PERFORM pg_temp.seed_saved_observation(owner_id,observation,TRUE);
 INSERT INTO public.explore_posts(id,user_id,scan_id) VALUES(post,owner_id,observation);
 INSERT INTO public.explore_community_requests(id,post_id,scan_id,requested_by) VALUES(request,post,observation,owner_id);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner_id)::TEXT,TRUE);
 PERFORM public.enroll_owned_observation_history(observation,9);
 SELECT selected_analysis_id INTO analysis FROM internal.observation_histories WHERE observation_id=observation;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
 IF bind_result THEN PERFORM internal.bind_observation_community_request(owner_id,observation,analysis,request,1,0); END IF;
 RETURN analysis;
END;
$$;
-- END COMMUNITY HISTORY HELPERS
SELECT extensions.ok(NOT (SELECT community_authority_enabled FROM internal.observation_history_rollout WHERE singleton),'community admission defaults closed');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.bind_observation_community_request(uuid,uuid,uuid,uuid,integer,integer)','EXECUTE')
 AND NOT has_function_privilege('authenticated','internal.reconcile_observation_community_authority(uuid,uuid)','EXECUTE')
 AND NOT has_table_privilege('service_role','internal.observation_community_bindings','INSERT')
 AND NOT has_table_privilege('anon','internal.observation_community_reconciliation','SELECT'),'no API role can bind, project or inspect history');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,state_reader_enabled=TRUE,selection_enabled=TRUE,selection_api_enabled=TRUE,confirmation_api_enabled=TRUE;
-- A preexisting request never gets fresh insertion proof from enrollment.
SELECT pg_temp.seed_saved_observation('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb12',TRUE);
INSERT INTO public.explore_posts(id,user_id,scan_id) VALUES('00000000-0000-4000-8000-00000000fb42','00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb12');
INSERT INTO public.explore_community_requests(id,post_id,scan_id,requested_by) VALUES('00000000-0000-4000-8000-00000000fb22','00000000-0000-4000-8000-00000000fb42','00000000-0000-4000-8000-00000000fb12','00000000-0000-4000-8000-00000000fb01');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fb01","role":"authenticated"}',TRUE);
SELECT public.enroll_owned_observation_history('00000000-0000-4000-8000-00000000fb12',9);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.throws_ok($$SELECT internal.bind_observation_community_request('00000000-0000-4000-8000-00000000fb01',observation_id,selected_analysis_id,'00000000-0000-4000-8000-00000000fb22',1,0) FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb12'$$,'55000','analysis_history_unavailable','closed admission refused');
UPDATE internal.observation_history_rollout SET community_authority_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT internal.bind_observation_community_request('00000000-0000-4000-8000-00000000fb01',observation_id,selected_analysis_id,'00000000-0000-4000-8000-00000000fb22',1,0) FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb12'$$,'55000','analysis_history_community_requires_new_request','legacy request cannot be attached to imported selection');
SELECT pg_temp.seed_bound_community('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb11','00000000-0000-4000-8000-00000000fb21','00000000-0000-4000-8000-00000000fb41');
SELECT extensions.ok((SELECT state_revision=2 AND active_projection->>'pending_review'='true' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb11'),'binding atomically makes only named result await community');
SELECT extensions.is(internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb21'),'current','initial outcome already reconciled');
SELECT extensions.lives_ok($$SELECT internal.bind_observation_community_request(owner_id,observation_id,analysis_id,request_id,1,0) FROM internal.observation_community_bindings$$,'exact admission replay changes nothing');
SELECT extensions.throws_ok($$SELECT internal.bind_observation_community_request(owner_id,observation_id,analysis_id,request_id,2,0) FROM internal.observation_community_bindings$$,'22023','analysis_history_operation_conflict','binding cannot be rebased');
SELECT extensions.throws_ok($$UPDATE internal.observation_community_bindings SET bound_review_revision=2$$,'22023','analysis_history_evidence_immutable','binding immutable');
SELECT extensions.throws_ok($$UPDATE public.explore_community_requests SET requested_at=requested_at+interval '1 second' WHERE id='00000000-0000-4000-8000-00000000fb21'$$,'22023','analysis_history_evidence_immutable','request generation cannot be rebound');
SELECT extensions.throws_ok($$UPDATE public.explore_community_requests SET post_id='00000000-0000-4000-8000-00000000fb42' WHERE id='00000000-0000-4000-8000-00000000fb21'$$,'22023','analysis_history_evidence_immutable','publication cannot be rebound');
INSERT INTO public.taxon_nodes(id,path,rank,scientific_name,taxonomy_version_id) VALUES
 ('00000000-0000-4000-8000-00000000fb51','boundcommunity','genus','Boundcommunity',public.active_taxonomy_version_id()),
 ('00000000-0000-4000-8000-00000000fb52','boundcommunity.species','species','Boundcommunity species',public.active_taxonomy_version_id());
UPDATE public.explore_community_requests SET status='resolved',resolved_at=now(),resolved_taxon_node_id='00000000-0000-4000-8000-00000000fb51' WHERE id='00000000-0000-4000-8000-00000000fb21';
SELECT extensions.is((SELECT ai_identification_review FROM public.scans WHERE id='00000000-0000-4000-8000-00000000fb11'),NULL::JSONB,'consensus does not write legacy scan authority');
SELECT extensions.is(internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb21'),'applied','genus resolution applied');
SELECT extensions.ok((SELECT active_projection->>'rank'='genus' AND active_projection->>'verified'='false' AND active_projection->>'pending_review'='false' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb11'),'genus visible without species credit');
UPDATE public.explore_community_requests SET resolved_taxon_node_id='00000000-0000-4000-8000-00000000fb52' WHERE id='00000000-0000-4000-8000-00000000fb21';
SELECT internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb21');
SELECT extensions.ok((SELECT active_projection->>'rank'='species' AND active_projection->>'verified'='true' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb11'),'species consensus independently verified');
-- A delayed invocation after resolve -> withdraw never replays resolved evidence.
UPDATE public.explore_community_requests SET status='needs_id',resolved_at=NULL,resolved_taxon_node_id=NULL WHERE id='00000000-0000-4000-8000-00000000fb21';
UPDATE internal.observation_history_rollout SET community_authority_enabled=FALSE;
SELECT extensions.is(internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb21'),'applied','revocation continues after new-admission hold closes');
SELECT extensions.ok((SELECT active_projection->>'pending_review'='true' AND active_projection->>'verified'='false' AND active_projection->'species_id'='null'::JSONB FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb11'),'withdrawal removes species authority');
SELECT extensions.is(internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb21'),'current','late duplicate cannot restore withdrawn authority');
-- Owner acceptance supersedes this request permanently, even future resolution.
CREATE TEMP TABLE accept_request AS SELECT jsonb_build_object('schema_version',1,'observation_id',h.observation_id,'analysis_id',b.analysis_id,'operation_id','00000000-0000-4000-8000-00000000fb61','expected_observation_revision',h.state_revision,'expected_review_revision',a.review_revision,'action','confirm_name','scientific_name','Boundcommunity accepted') request
 FROM internal.observation_community_bindings b JOIN internal.observation_histories h USING(observation_id) JOIN internal.observation_analysis_authorities a ON a.analysis_id=b.analysis_id;
SELECT public.prepare_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fb01',request,9) FROM accept_request;
SELECT public.complete_observation_analysis_confirmation('00000000-0000-4000-8000-00000000fb01',request,9,'Boundcommunity accepted','{"scientific_name":"Boundcommunity accepted","gbif_taxon_key":987699793,"rank":"SPECIES","status":"ACCEPTED","kingdom":"Plantae"}') FROM accept_request;
UPDATE public.explore_community_requests SET status='resolved',resolved_at=now(),resolved_taxon_node_id='00000000-0000-4000-8000-00000000fb52' WHERE id='00000000-0000-4000-8000-00000000fb21';
SELECT extensions.is(internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb21'),'superseded','community cannot overwrite subsequent owner acceptance');
SELECT extensions.is((SELECT active_projection->>'scientific_name' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb11'),'Boundcommunity accepted','owner acceptance retained');
-- Separate request deletion retains durable revocation work until the observation erases it.
UPDATE internal.observation_history_rollout SET community_authority_enabled=TRUE;
SELECT pg_temp.seed_bound_community('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb13','00000000-0000-4000-8000-00000000fb23','00000000-0000-4000-8000-00000000fb43');
UPDATE public.explore_community_requests SET status='resolved',resolved_at=now(),resolved_taxon_node_id='00000000-0000-4000-8000-00000000fb52' WHERE id='00000000-0000-4000-8000-00000000fb23';
SELECT internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb23');
DELETE FROM public.explore_community_requests WHERE id='00000000-0000-4000-8000-00000000fb23';
SELECT extensions.is(internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb23'),'applied','missing request revokes instead of dropping pending work');
SELECT extensions.is((SELECT active_projection->>'pending_review' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fb13'),'true','deleted request cannot retain resolved species');
SELECT extensions.throws_ok($$SELECT internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb02','00000000-0000-4000-8000-00000000fb21')$$,'P0002','analysis_history_not_found','foreign owner concealed');
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000fb01');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_community_bindings),0,'account erasure clears private bindings');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_community_reconciliation),0,'account erasure clears queue');
SELECT extensions.throws_ok($$SELECT internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fb01','00000000-0000-4000-8000-00000000fb21')$$,'P0002','analysis_history_not_found','deleted owner cannot replay authority');
SELECT * FROM extensions.finish();
ROLLBACK;
