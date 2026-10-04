\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN COMMUNITY ADMISSION HELPERS
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


CREATE FUNCTION pg_temp.seed_admission_history(owner_id UUID,observation UUID) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE analysis UUID;
BEGIN
 PERFORM pg_temp.seed_saved_observation(owner_id,observation,TRUE);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner_id)::TEXT,TRUE);
 PERFORM public.enroll_owned_observation_history(observation,9);
 SELECT selected_analysis_id INTO analysis FROM internal.observation_histories WHERE observation_id=observation;
 PERFORM set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
 RETURN analysis;
END;
$$;
CREATE FUNCTION pg_temp.admit_fixture(owner_id UUID,observation UUID,operation UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.admit_observation_community_request(owner_id,operation,observation,
 (SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id=observation),1,0,
 public.active_taxonomy_version_id(),NULL,'Synthetic public note',
 '[{"kind":"image","url":"https://example.invalid/approved.jpg","thumbnail_url":"https://example.invalid/approved.jpg","order_index":0,"duration_seconds":null,"has_audio":false}]'::JSONB);
$$;
-- END COMMUNITY ADMISSION HELPERS
SELECT extensions.ok(NOT (SELECT community_admission_enabled FROM internal.observation_history_rollout WHERE singleton),'admission is closed by default');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.admit_observation_community_request(uuid,uuid,uuid,uuid,integer,integer,uuid,uuid,text,jsonb)','EXECUTE'),'no API writer including service');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_community_admission_fences','INSERT') AND NOT has_table_privilege('authenticated','internal.observation_community_admissions','SELECT'),'fence and receipt remain private');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,community_authority_enabled=TRUE;
SELECT pg_temp.seed_admission_history('00000000-0000-4000-8000-00000000fd01','00000000-0000-4000-8000-00000000fd11');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd01','00000000-0000-4000-8000-00000000fd11','00000000-0000-4000-8000-00000000fd21')$$,'55000','analysis_history_unavailable','closed gate cannot publish');
UPDATE internal.observation_history_rollout SET community_admission_enabled=TRUE;
CREATE TEMP TABLE admitted AS SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd01','00000000-0000-4000-8000-00000000fd11','00000000-0000-4000-8000-00000000fd21') AS receipt;
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_community_admissions),1,'one immutable receipt');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_community_admission_fences),0,'transaction proof consumed');
SELECT extensions.is((SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd01','00000000-0000-4000-8000-00000000fd11','00000000-0000-4000-8000-00000000fd21')),(SELECT receipt FROM admitted),'lost response returns same durable receipt');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_community_requests WHERE scan_id='00000000-0000-4000-8000-00000000fd11'),1,'retry does not duplicate request');
SELECT extensions.ok((SELECT state_revision=2 AND selected_analysis_id=(receipt->>'analysis_id')::UUID FROM internal.observation_histories,admitted WHERE observation_id='00000000-0000-4000-8000-00000000fd11'),'admission advances authority without changing selection');
SELECT extensions.throws_ok($$SELECT internal.admit_observation_community_request(owner_id,operation_id,observation_id,analysis_id,1,0,public.active_taxonomy_version_id(),NULL,'changed',intent->'media') FROM internal.observation_community_admissions$$,'22023','analysis_history_operation_conflict','changed intent cannot replay');
SELECT extensions.ok((SELECT hero_image_url='https://example.invalid/approved.jpg' AND inference_tier IS NULL AND NOT ai_confidence_qualified AND suggested_taxa='[]'::JSONB FROM public.get_community_identification_detail(NULL,(SELECT (receipt->>'request_id')::UUID FROM admitted))),'pending detail is sanitized and pinned');
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,(SELECT (receipt->>'post_id')::UUID FROM admitted))),0,'needs_id is not an Explore publication');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_public_projection),0,'admission creates no resolved publication sidecar');
SELECT extensions.is((SELECT hero_image_url FROM public.get_community_identification_feed(NULL,30,NULL,NULL,NULL,NULL,'all','all') WHERE request_id=(SELECT (receipt->>'request_id')::UUID FROM admitted)),'https://example.invalid/approved.jpg','community feed uses frozen cohort');
SELECT extensions.throws_ok($$UPDATE public.explore_post_media SET url='https://example.invalid/replaced.jpg' WHERE post_id=(SELECT (receipt->>'post_id')::UUID FROM admitted)$$,'22023','analysis_history_evidence_immutable','pending media cannot be replaced');
SELECT extensions.lives_ok($$UPDATE public.explore_post_media SET health_checked_at=now() WHERE post_id=(SELECT (receipt->>'post_id')::UUID FROM admitted)$$,'health remains mutable');
UPDATE public.scans SET image_storage_urls='{}' WHERE id='00000000-0000-4000-8000-00000000fd11';
SELECT extensions.lives_ok($$SELECT public.refresh_explore_post_media((SELECT (receipt->>'post_id')::UUID FROM admitted))$$,'legacy refresh leaves admitted cohort alone');
SELECT extensions.is((SELECT hero_image_url FROM public.get_community_identification_detail(NULL,(SELECT (receipt->>'request_id')::UUID FROM admitted))),'https://example.invalid/approved.jpg','private media change does not affect public evidence');
SELECT extensions.throws_ok($$UPDATE internal.observation_community_admissions SET intent='{}'$$,'22023','analysis_history_evidence_immutable','intent cannot mutate');
SELECT extensions.throws_ok($$UPDATE public.explore_community_requests SET note='changed' WHERE id=(SELECT (receipt->>'request_id')::UUID FROM admitted)$$,'22023','analysis_history_evidence_immutable','initial request evidence cannot drift');
SELECT pg_temp.seed_admission_history('00000000-0000-4000-8000-00000000fd02','00000000-0000-4000-8000-00000000fd12');
INSERT INTO public.explore_posts(id,user_id,scan_id) VALUES('00000000-0000-4000-8000-00000000fd32','00000000-0000-4000-8000-00000000fd02','00000000-0000-4000-8000-00000000fd12');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd02','00000000-0000-4000-8000-00000000fd12','00000000-0000-4000-8000-00000000fd22')$$,'22023','analysis_history_operation_conflict','existing legacy post cannot be replaced');
SELECT extensions.throws_ok($$INSERT INTO public.explore_community_requests(post_id,scan_id,requested_by) VALUES('00000000-0000-4000-8000-00000000fd32','00000000-0000-4000-8000-00000000fd12','00000000-0000-4000-8000-00000000fd02')$$,'55000','analysis_bound_review_required','direct enrolled request insertion still denied');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_community_admissions),1,'rejected operation leaves no receipt');
SELECT pg_temp.seed_admission_history('00000000-0000-4000-8000-00000000fd03','00000000-0000-4000-8000-00000000fd13');
SELECT extensions.throws_ok($$SELECT internal.admit_observation_community_request('00000000-0000-4000-8000-00000000fd03','00000000-0000-4000-8000-00000000fd23',observation_id,selected_analysis_id,0,0,public.active_taxonomy_version_id(),NULL,NULL,(SELECT intent->'media' FROM internal.observation_community_admissions)) FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fd13'$$,'40001','analysis_history_revision_conflict','stale revision refuses before publication');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_posts WHERE scan_id='00000000-0000-4000-8000-00000000fd13'),0,'stale admission leaves no post');
SELECT extensions.throws_ok($$SELECT internal.admit_observation_community_request(owner_id,'00000000-0000-4000-8000-00000000fd24',observation_id,analysis_id,1,0,public.active_taxonomy_version_id(),NULL,NULL,jsonb_set(intent->'media','{0,url}','"https://example.invalid/private.jpg?signature=secret"')) FROM internal.observation_community_admissions$$,'22023','invalid_analysis_history','signed media tickets refused');
UPDATE internal.observation_history_rollout SET community_admission_enabled=FALSE;
SELECT extensions.is((SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd01','00000000-0000-4000-8000-00000000fd11','00000000-0000-4000-8000-00000000fd21')),(SELECT receipt FROM admitted),'closed admission does not break retry');
DELETE FROM public.explore_community_requests WHERE id=(SELECT (receipt->>'request_id')::UUID FROM admitted);
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,(SELECT (receipt->>'post_id')::UUID FROM admitted))),0,'request removal cannot fall back to legacy Explore identity');
SELECT extensions.is((SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd01','00000000-0000-4000-8000-00000000fd11','00000000-0000-4000-8000-00000000fd21')),(SELECT receipt FROM admitted),'historical receipt does not recreate deleted request');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_community_requests WHERE scan_id='00000000-0000-4000-8000-00000000fd11'),0,'request stays deleted');
-- Post/account deletion wins; private operation storage cascades with history.
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000fd01');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_community_admissions),0,'account deletion removes private intent');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_community_posts),0,'account deletion erases public marker');
SELECT extensions.throws_ok($$SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd01','00000000-0000-4000-8000-00000000fd11','00000000-0000-4000-8000-00000000fd21')$$,'22023','invalid_analysis_history','missing local analysis cannot replay');
-- A resolved request can later register the same frozen approved cohort.
UPDATE internal.observation_history_rollout SET community_admission_enabled=TRUE,publication_snapshot_enabled=TRUE;
SELECT pg_temp.seed_admission_history('00000000-0000-4000-8000-00000000fd04','00000000-0000-4000-8000-00000000fd14');
SELECT pg_temp.admit_fixture('00000000-0000-4000-8000-00000000fd04','00000000-0000-4000-8000-00000000fd14','00000000-0000-4000-8000-00000000fd24');
INSERT INTO public.taxon_nodes(id,path,rank,scientific_name,taxonomy_version_id) VALUES('00000000-0000-4000-8000-00000000fd44','admissionfixture'::public.ltree,'species','Admissionfixture approved',public.active_taxonomy_version_id());
UPDATE public.explore_community_requests SET status='resolved',resolved_at=now(),resolved_taxon_node_id='00000000-0000-4000-8000-00000000fd44',explore_published_at=now() WHERE scan_id='00000000-0000-4000-8000-00000000fd14';
SELECT internal.reconcile_observation_community_authority(owner_id,request_id) FROM internal.observation_community_admissions;
SELECT extensions.lives_ok($$SELECT internal.register_observation_publication(a.owner_id,a.request_id,'00000000-0000-4000-8000-00000000fd54',h.state_revision,r.review_revision,a.intent->'media') FROM internal.observation_community_admissions a JOIN internal.observation_histories h USING(observation_id) JOIN internal.observation_analysis_authorities r USING(observation_id,analysis_id)$$,'resolved admission registers without replacing public evidence');
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,(SELECT post_id FROM internal.observation_community_admissions))),1,'registered resolution becomes Explore eligible');
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT internal.admit_observation_community_request(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)$$,'42501',NULL,'service cannot call private admission');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT * FROM internal.observation_community_admissions$$,'42501',NULL,'authenticated cannot read private intent');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_community_posts),0,'public marker direct reads remain denied');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
