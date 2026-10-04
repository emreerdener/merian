\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN PUBLICATION HELPERS
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
CREATE FUNCTION pg_temp.seed_publication(owner_id UUID,observation UUID,request UUID,post UUID,publication UUID,register_snapshot BOOLEAN DEFAULT TRUE) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE analysis UUID; taxon UUID:=gen_random_uuid(); media JSONB;
BEGIN
 analysis:=pg_temp.seed_bound_community(owner_id,observation,request,post);
 INSERT INTO public.taxon_nodes(id,path,rank,scientific_name,taxonomy_version_id) VALUES(taxon,('publicationfixture_'||replace(taxon::TEXT,'-',''))::public.ltree,'species','Publicationfixture '||replace(taxon::TEXT,'-',''),public.active_taxonomy_version_id());
 UPDATE public.explore_community_requests SET status='resolved',resolved_at=now(),resolved_taxon_node_id=taxon,explore_published_at=now() WHERE id=request;
 PERFORM internal.reconcile_observation_community_authority(owner_id,request);
 DELETE FROM public.explore_post_media WHERE post_id=post;
 INSERT INTO public.explore_post_media(post_id,kind,url,thumbnail_url,order_index) VALUES(post,'image','https://example.invalid/approved-public.jpg','https://example.invalid/approved-public.jpg',0);
 SELECT jsonb_agg(jsonb_build_object('kind',kind,'url',url,'thumbnail_url',thumbnail_url,'order_index',order_index,'duration_seconds',duration_seconds,'has_audio',has_audio) ORDER BY order_index) INTO media FROM public.explore_post_media WHERE post_id=post;
 IF register_snapshot THEN
   PERFORM internal.register_observation_publication(owner_id,request,publication,
      (SELECT state_revision FROM internal.observation_histories WHERE observation_id=observation),
      (SELECT review_revision FROM internal.observation_analysis_authorities WHERE analysis_id=analysis),media);
 END IF;
 RETURN analysis;
END;
$$;
-- END PUBLICATION HELPERS
SELECT extensions.ok(NOT (SELECT publication_snapshot_enabled FROM internal.observation_history_rollout WHERE singleton),'publication admission defaults closed');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.register_observation_publication(uuid,uuid,uuid,integer,integer,jsonb)','EXECUTE') AND NOT has_table_privilege('authenticated','internal.observation_analysis_publications','SELECT') AND NOT has_table_privilege('service_role','public.explore_analysis_public_projection','UPDATE'),'private writer and immutable storage have no API grants');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE,enrollment_enabled=TRUE,saved_import_enabled=TRUE,state_reader_enabled=TRUE,selection_enabled=TRUE,selection_api_enabled=TRUE,community_authority_enabled=TRUE,publication_snapshot_enabled=TRUE;
SELECT pg_temp.seed_publication('00000000-0000-4000-8000-00000000fc01','00000000-0000-4000-8000-00000000fc11','00000000-0000-4000-8000-00000000fc21','00000000-0000-4000-8000-00000000fc31','00000000-0000-4000-8000-00000000fc41',FALSE);
-- An existing derived reference for the bound post is evicted at registration.
INSERT INTO public.species_reference_images(id,species_id,url,source) SELECT '00000000-0000-4000-8000-00000000fc51',(active_projection->>'species_id')::UUID,'https://example.invalid/old-reference.jpg','merian' FROM internal.observation_histories;
INSERT INTO public.species_reference_image_merian_sources(reference_image_id,species_id,explore_post_id,scan_id,user_id,image_url,image_index,image_quality_score,author_attribution,source_shared_at,is_promoted)
SELECT id,species_id,'00000000-0000-4000-8000-00000000fc31','00000000-0000-4000-8000-00000000fc11','00000000-0000-4000-8000-00000000fc01',url,0,90,'Synthetic fixture',now(),TRUE FROM public.species_reference_images WHERE id='00000000-0000-4000-8000-00000000fc51';
INSERT INTO public.species_reference_images(id,species_id,url,source) SELECT '00000000-0000-4000-8000-00000000fc52',species_id,'https://example.invalid/unrelated-reference.jpg','wikipedia' FROM public.species_reference_images WHERE id='00000000-0000-4000-8000-00000000fc51';
UPDATE public.species_dictionary SET kingdom='Plantae',phylum='Tracheophyta',reference_image_url='https://example.invalid/old-reference.jpg,https://example.invalid/unrelated-reference.jpg' WHERE id=(SELECT species_id FROM public.species_reference_images WHERE id='00000000-0000-4000-8000-00000000fc51');
SELECT internal.register_observation_publication('00000000-0000-4000-8000-00000000fc01','00000000-0000-4000-8000-00000000fc21','00000000-0000-4000-8000-00000000fc41',3,2,
 (SELECT jsonb_agg(jsonb_build_object('kind',kind,'url',url,'thumbnail_url',thumbnail_url,'order_index',order_index,'duration_seconds',duration_seconds,'has_audio',has_audio) ORDER BY order_index) FROM public.explore_post_media WHERE post_id='00000000-0000-4000-8000-00000000fc31'));
SELECT extensions.is((SELECT count(*)::INT FROM public.species_reference_images WHERE id='00000000-0000-4000-8000-00000000fc51'),0,'old derived reference immediately evicted');
SELECT extensions.ok((SELECT NOT is_promoted AND disqualified_at IS NOT NULL FROM public.species_reference_image_merian_sources WHERE explore_post_id='00000000-0000-4000-8000-00000000fc31'),'old reference provenance disqualified');
SELECT extensions.is((SELECT count(*)::INT FROM public.species_reference_images WHERE id='00000000-0000-4000-8000-00000000fc52'),1,'unrelated reference retained');
SELECT extensions.is((SELECT reference_image_url FROM public.species_dictionary WHERE id=(SELECT species_id FROM public.explore_analysis_public_projection)),'https://example.invalid/unrelated-reference.jpg','legacy reference fallback pruned without removing unrelated URL');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_analysis_publications),1,'one immutable public snapshot');
SELECT extensions.ok((SELECT species_id IS NOT NULL AND identification->>'label_source'='community' FROM public.explore_analysis_public_projection),'current reconciled community species projected');
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,'00000000-0000-4000-8000-00000000fc31')),1,'approved bound post appears');
SELECT extensions.is((SELECT identification->>'original_scientific_name' FROM public.explore_projected_post_cards(NULL) WHERE post_id='00000000-0000-4000-8000-00000000fc31'),'Savedfixture','original label pinned to immutable result');
SELECT extensions.ok((SELECT ai_reasoning IS NULL AND pet_identification IS NULL FROM public.get_explore_post_detail(NULL,'00000000-0000-4000-8000-00000000fc31')),'private reasoning and pet payload never copied to public detail');
SELECT extensions.is((SELECT internal.explore_effective_species_id(s,'00000000-0000-4000-8000-00000000fc31') FROM public.scans s WHERE id='00000000-0000-4000-8000-00000000fc11'),(SELECT species_id FROM public.explore_analysis_public_projection),'species helper uses published result');
SELECT extensions.lives_ok($$SELECT internal.register_observation_publication(owner_id,request_id,publication_id,observation_revision,review_revision,media_manifest) FROM internal.observation_analysis_publications$$,'exact publication retry');
SELECT extensions.throws_ok($$SELECT internal.register_observation_publication(owner_id,request_id,publication_id,observation_revision+1,review_revision,media_manifest) FROM internal.observation_analysis_publications$$,'22023','analysis_history_operation_conflict','replay cannot change revisions');
SELECT extensions.throws_ok($$UPDATE internal.observation_analysis_publications SET original_identity='{}'$$,'22023','analysis_history_evidence_immutable','published original cannot mutate');
SELECT extensions.throws_ok($$UPDATE public.explore_post_media SET url='https://example.invalid/other.jpg' WHERE post_id='00000000-0000-4000-8000-00000000fc31'$$,'22023','analysis_history_evidence_immutable','media cohort cannot be replaced');
SELECT extensions.throws_ok($$DELETE FROM public.explore_post_media WHERE post_id='00000000-0000-4000-8000-00000000fc31'$$,'22023','analysis_history_evidence_immutable','shared media cannot be dropped');
SELECT extensions.lives_ok($$UPDATE public.explore_post_media SET health_checked_at=now() WHERE post_id='00000000-0000-4000-8000-00000000fc31'$$,'health metadata stays mutable');
SELECT extensions.lives_ok($$SELECT public.refresh_explore_post_media('00000000-0000-4000-8000-00000000fc31')$$,'legacy media refresh leaves publication alone');
SELECT extensions.is((SELECT url FROM public.explore_post_media WHERE post_id='00000000-0000-4000-8000-00000000fc31'),'https://example.invalid/approved-public.jpg','refresh did not copy original scan media');
SELECT set_config('request.headers','{"x-merian-identification-protocol":"9"}',TRUE);
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fc02","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_projected_post_cards('00000000-0000-4000-8000-00000000fc02')),0,'non-owner direct invoker keeps existing post RLS');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_public_projection),0,'non-owner direct sidecar follows post RLS');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_public_projection),0,'anonymous direct sidecar is denied');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SET LOCAL ROLE service_role;
SELECT extensions.ok((SELECT identification->>'label_source'='community' FROM public.get_explore_post('00000000-0000-4000-8000-00000000fc02','00000000-0000-4000-8000-00000000fc31')),'service viewer receives published authority');
SELECT extensions.ok((SELECT identification->>'label_source'='community' FROM public.get_public_web_explore_posts('00000000-0000-4000-8000-00000000fc31',1)),'public web receives approved authority');
SELECT extensions.is(jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000fc02','Publicationfixture',NULL,NULL,'sightings',NULL,TRUE)->'sightings'),1,'discovery finds published species independent of legacy scan');
RESET ROLE;
SELECT extensions.ok((SELECT hero_image_url='https://example.invalid/approved-public.jpg' AND suggested_taxa='[]'::JSONB AND inference_tier IS NULL AND ai_confidence_qualified=FALSE FROM public.get_community_identification_detail('00000000-0000-4000-8000-00000000fc02','00000000-0000-4000-8000-00000000fc21')),'community detail uses only approved public media and no private suggestions');
-- Changing the old scan payload cannot hide or relabel the publication.
UPDATE public.scans SET image_storage_urls='{}' WHERE id='00000000-0000-4000-8000-00000000fc11';
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,'00000000-0000-4000-8000-00000000fc31')),1,'empty private media cannot hide published identity');
SELECT extensions.is((SELECT count(*)::INT FROM public.get_community_identification_detail(NULL,'00000000-0000-4000-8000-00000000fc21')),1,'community detail uses approved cohort after private scan media removal');
INSERT INTO public.explore_post_notifications(user_id,post_id,community_request_id,type)
SELECT '00000000-0000-4000-8000-00000000fc01','00000000-0000-4000-8000-00000000fc31','00000000-0000-4000-8000-00000000fc21','community_request_resolved'
WHERE NOT EXISTS(SELECT 1 FROM public.explore_post_notifications WHERE community_request_id='00000000-0000-4000-8000-00000000fc21');
-- Private A -> B -> A changes never select a different public identity.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,source_analysis_id,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000fc61',observation_id,2,analysis_id,repeat('c',64),result_snapshot,'{"schema_version":1,"captured_media":[]}'::JSONB,now() FROM internal.observation_analysis_results WHERE observation_id='00000000-0000-4000-8000-00000000fc11';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000fc61',review_snapshot FROM internal.observation_analysis_authorities WHERE observation_id='00000000-0000-4000-8000-00000000fc11';
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fc01","role":"authenticated"}',TRUE);
SELECT public.select_owned_observation_analysis('{"schema_version":1,"observation_id":"00000000-0000-4000-8000-00000000fc11","analysis_id":"00000000-0000-4000-8000-00000000fc61","operation_id":"00000000-0000-4000-8000-00000000fc71","expected_observation_revision":3,"expected_review_revision":0}',9);
SELECT extensions.ok((SELECT identification IS NOT NULL FROM public.explore_analysis_public_projection),'selecting private B preserves published A');
SELECT public.select_owned_observation_analysis(jsonb_build_object('schema_version',1,'observation_id',observation_id,'analysis_id',analysis_id,'operation_id','00000000-0000-4000-8000-00000000fc72','expected_observation_revision',4,'expected_review_revision',2),9) FROM internal.observation_analysis_publications;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.is(internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fc01','00000000-0000-4000-8000-00000000fc21'),'current','late reconciliation after A -> B -> A does not republish');
UPDATE internal.observation_history_rollout SET publication_snapshot_enabled=FALSE;
-- Commit visibility and authority invalidation share the request transaction.
UPDATE public.explore_community_requests SET status='needs_id',resolved_at=NULL,resolved_taxon_node_id=NULL WHERE id='00000000-0000-4000-8000-00000000fc21';
SELECT extensions.ok((SELECT species_id IS NULL AND identification IS NULL FROM public.explore_analysis_public_projection),'withdrawal immediately invalidates public authority before worker');
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,'00000000-0000-4000-8000-00000000fc31')),1,'withdrawal preserves public post and discussion');
SELECT extensions.ok((SELECT identification IS NULL AND species_scientific_name='' FROM public.get_explore_post(NULL,'00000000-0000-4000-8000-00000000fc31')),'withdrawn card is unresolved');
SELECT extensions.ok((SELECT species_dictionary_id IS NULL AND ai_reasoning IS NULL FROM public.get_explore_post_detail(NULL,'00000000-0000-4000-8000-00000000fc31')),'withdrawn detail loses species and reasoning');
SELECT extensions.is((SELECT internal.explore_effective_species_id(s,'00000000-0000-4000-8000-00000000fc31') FROM public.scans s WHERE id='00000000-0000-4000-8000-00000000fc11'),NULL::UUID,'species filters lose eligibility before worker');
SELECT internal.reconcile_observation_community_authority('00000000-0000-4000-8000-00000000fc01','00000000-0000-4000-8000-00000000fc21');
SELECT extensions.ok((SELECT identification IS NULL FROM public.explore_analysis_public_projection),'late reconciliation does not restore withdrawn labels');
SET LOCAL ROLE service_role;
SELECT extensions.ok((SELECT identification IS NULL FROM public.get_public_web_explore_posts('00000000-0000-4000-8000-00000000fc31',1)),'public web immediately loses revoked authority');
SELECT extensions.is(jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000fc02','Publicationfixture',NULL,NULL,'sightings',NULL,TRUE)->'sightings'),0,'discovery removes revoked species eligibility');
RESET ROLE;
SELECT extensions.ok((SELECT status='needs_id' AND current_taxon_id IS NULL AND resolved_taxon_id IS NULL AND suggested_taxa='[]'::JSONB AND hero_image_url='https://example.invalid/approved-public.jpg' FROM public.get_community_identification_detail(NULL,'00000000-0000-4000-8000-00000000fc21')),'community discussion remains with unresolved labels after revocation');
SELECT extensions.ok((SELECT count(*)>0 AND bool_and(community_taxon_common_name IS NULL AND community_taxon_scientific_name IS NULL AND community_request_display_name='Community request') FROM public.get_explore_notifications('00000000-0000-4000-8000-00000000fc01',20,NULL,NULL) WHERE community_request_id='00000000-0000-4000-8000-00000000fc21'),'legacy notification reader removes revoked taxon labels');
SELECT extensions.ok((SELECT count(*)>0 AND bool_and(community_taxon_common_name IS NULL AND community_taxon_scientific_name IS NULL AND community_request_display_name='Community request') FROM public.get_explore_notifications_with_reactions('00000000-0000-4000-8000-00000000fc01',20,NULL,NULL) WHERE community_request_id='00000000-0000-4000-8000-00000000fc21'),'reaction notification reader removes revoked taxon labels');
SELECT extensions.lives_ok($$SELECT internal.register_observation_publication(owner_id,request_id,publication_id,observation_revision,review_revision,media_manifest) FROM internal.observation_analysis_publications$$,'old publication retry survives admission closure');
SELECT extensions.ok((SELECT identification IS NULL FROM public.explore_analysis_public_projection),'old publication receipt never restores withdrawn authority');
-- Privacy remains stronger than historical publication.
UPDATE public.explore_posts SET unshared_at=now() WHERE id='00000000-0000-4000-8000-00000000fc31';
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,'00000000-0000-4000-8000-00000000fc31')),0,'unshared bound post hidden');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000fc01","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_public_projection),0,'direct owner projection hides unshared post');
RESET ROLE;
UPDATE public.explore_posts SET unshared_at=NULL,moderated_at=now() WHERE id='00000000-0000-4000-8000-00000000fc31';
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,'00000000-0000-4000-8000-00000000fc31')),0,'moderation hides bound post');
UPDATE public.explore_posts SET moderated_at=NULL WHERE id='00000000-0000-4000-8000-00000000fc31';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
-- Removing private history leaves a public unresolved marker, not legacy identity.
DELETE FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fc11';
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_analysis_publications),0,'history deletion erases private publication record');
SELECT extensions.ok((SELECT identification IS NULL FROM public.explore_analysis_public_projection),'history deletion retains unresolved public fence');
SELECT extensions.is((SELECT count(*)::INT FROM public.get_explore_post(NULL,'00000000-0000-4000-8000-00000000fc31')),1,'erased authority does not substitute legacy identity');
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000fc01');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_public_projection),0,'account erasure clears public projection');
SELECT * FROM extensions.finish();
ROLLBACK;
