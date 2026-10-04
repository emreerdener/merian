\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.history_append_request(observation UUID, analysis UUID, source UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'source_analysis_id',source,'request_digest',REPEAT('a',64),
        'result_snapshot',JSONB_BUILD_OBJECT('scan_id',observation,'species_id',NULL,
            'scientific_name',NULL,'common_name','Unidentified plant','is_biological_subject',TRUE,
            'is_live_capture',TRUE,'confidence_score',0.8,'blur_score',0.2,'colors','[]'::JSONB,
            'estimated_size_cm',NULL,'inference_tier','flash','pet_identification',NULL,'candidates',NULL,
            'image_quality',NULL,'ai_reasoning','Synthetic fixture.','extracted_visual_traits','[]'::JSONB),
        'evidence_manifest','{"schema_version":1,"captured_media":[{"description":{"_0":{"freeText":"Synthetic observation."}}}]}'::JSONB);
$$;
CREATE FUNCTION pg_temp.seed_history_append(owner_id UUID, observation UUID, permit_initial BOOLEAN DEFAULT TRUE)
RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    VALUES(owner_id,'authenticated','authenticated',owner_id::TEXT || '@example.invalid','{}','{}',NOW(),NOW());
    INSERT INTO public.scan_ingestion_jobs(scan_id,user_id,status,stage,terminal_reason_code)
    VALUES(observation::TEXT,owner_id,'failed_terminal','server_replay_limit_reached','replay_exhausted');
    INSERT INTO public.scans(id,user_id,image_storage_urls,ai_confidence_score,is_biological_subject,inference_tier,geoprivacy,is_live_capture)
    VALUES(observation,owner_id,'{}',0.8,FALSE,'flash','private',TRUE);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=TRUE;
    INSERT INTO internal.observation_histories(observation_id,initial_selection_permitted) VALUES(observation,permit_initial);
    UPDATE internal.observation_history_rollout SET enrollment_enabled=FALSE;
END;
$$;
CREATE FUNCTION pg_temp.seed_funded_history(owner_id UUID,observation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
    PERFORM pg_temp.seed_history_append(owner_id,observation);
    INSERT INTO public.user_adult_eligibility_receipts(id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'self_attestation','Synthetic adult attestation','ios','1.0.3','275');
    INSERT INTO public.user_terms_acceptance_receipts(id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'2026-08-03',NOW(),'Synthetic terms acceptance','ios','1.0.3','275');
    INSERT INTO public.user_ai_consent_events(id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build)
    VALUES(gen_random_uuid(),owner_id,'google_gemini','2026-08-03.1','granted',NOW(),'Synthetic disclosure','Synthetic agreement','ios','1.0.3','275');
END;
$$;
CREATE FUNCTION pg_temp.funded_input(observation UUID,analysis UUID,source UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT (pg_temp.history_append_request(observation,analysis,source)-'result_snapshot') || '{"entitlement_protocol":3,"identification_protocol":6,"history_protocol":7,"expected_processor_permission":"google_gemini"}'::JSONB;
$$;
CREATE FUNCTION pg_temp.funded_provenance(analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT jsonb_build_object('version',1,'provider',q->>'provider','binding',q->>'binding','model',q->>'model','variant','multimodal','operation','scan_identification','policy_version',(q->>'policy_version')::BIGINT,
        'prompt','identify_vision_v1','schema','merian_identify_v1','confidence','unqualified','diagnostic_trigger',NULL,'prompt_diagnostic_trigger',NULL,'safety',NULL,'timeout_ms',90000,
        'generation','{"temperature":0.1,"seed":null,"top_k":null,"max_output_tokens":8192,"thinking_budget":1024}'::JSONB)
    FROM (SELECT quota AS q FROM internal.observation_analysis_intents WHERE analysis_id=analysis) s;
$$;
CREATE FUNCTION pg_temp.funded_dispatch(owner_id UUID,observation UUID,analysis UUID) RETURNS JSONB LANGUAGE SQL AS $$
    SELECT internal.dispatch_observation_analysis(owner_id,observation,analysis,(quota->>'lease_token')::UUID,pg_temp.funded_provenance(analysis)) FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;
CREATE FUNCTION pg_temp.funded_draft(owner_id UUID,observation UUID,analysis UUID) RETURNS VOID LANGUAGE SQL AS $$
    SELECT internal.record_observation_analysis_draft(owner_id,observation,analysis,(quota->>'lease_token')::UUID,
        pg_temp.history_append_request(observation,analysis,(input_snapshot->>'source_analysis_id')::UUID) || jsonb_build_object('result_snapshot',pg_temp.history_append_request(observation,analysis)->'result_snapshot' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis))),'{"input_tokens":100,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}')
    FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;
CREATE FUNCTION pg_temp.protected_input(observation UUID,analysis UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT pg_temp.funded_input(observation,analysis) || jsonb_build_object('schema_version',2,'history_protocol',8,'expected_processor_permission','google_gemini','evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id',media,'content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','description','text','Synthetic private observation'))));
$$;
CREATE FUNCTION pg_temp.protected_ready(owner_id UUID,observation UUID,analysis UUID,media UUID) RETURNS UUID LANGUAGE PLPGSQL AS $$
DECLARE receipt JSONB;
BEGIN
 receipt:=internal.reserve_observation_evidence(owner_id,observation,analysis,media,'image/jpeg',3,repeat('a',64));
 PERFORM internal.complete_observation_evidence(owner_id,observation,analysis,media,(receipt->>'object_id')::UUID);
 RETURN (receipt->>'object_id')::UUID;
END;
$$;
CREATE FUNCTION pg_temp.protected_draft(owner_id UUID,observation UUID,analysis UUID) RETURNS VOID LANGUAGE SQL AS $$
 SELECT internal.record_observation_analysis_draft(owner_id,observation,analysis,(quota->>'lease_token')::UUID,
 (input_snapshot-ARRAY['entitlement_protocol','identification_protocol','history_protocol','expected_processor_permission']) || jsonb_build_object('result_snapshot',pg_temp.history_append_request(observation,analysis)->'result_snapshot' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis))),'{"input_tokens":100,"candidate_tokens":30,"thinking_tokens":10,"total_tokens":140}')
 FROM internal.observation_analysis_intents WHERE analysis_id=analysis;
$$;

CREATE FUNCTION pg_temp.seed_publication_intent(owner_id UUID,observation UUID,analysis UUID,media UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM pg_temp.seed_funded_history(owner_id,observation);
 PERFORM pg_temp.protected_ready(owner_id,observation,analysis,media);
 PERFORM internal.admit_protected_observation_analysis(owner_id,pg_temp.protected_input(observation,analysis,media),repeat('a',64));
 PERFORM pg_temp.funded_dispatch(owner_id,observation,analysis);
 PERFORM pg_temp.protected_draft(owner_id,observation,analysis);
 PERFORM internal.complete_observation_analysis(owner_id,observation,analysis);
END;
$$;
CREATE FUNCTION pg_temp.publication_request(observation UUID,analysis UUID,operation UUID,media UUID) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'observation_id',observation,'analysis_id',analysis,'operation_id',operation,
 'expected_observation_revision',1,'expected_review_revision',0,'taxonomy_version_id',public.active_taxonomy_version_id(),
 'initial_taxon_id',NULL,'note','Synthetic public note','media_ids',jsonb_build_array(media));
$$;

CREATE FUNCTION pg_temp.seed_photo_moderation(owner_id UUID,observation UUID,analysis UUID,media UUID,operation UUID) RETURNS VOID LANGUAGE PLPGSQL AS $$
BEGIN
 PERFORM pg_temp.seed_publication_intent(owner_id,observation,analysis,media);
 PERFORM internal.prepare_observation_publication_intent(owner_id,pg_temp.publication_request(observation,analysis,operation,media));
END;
$$;
CREATE FUNCTION pg_temp.photo_execution_proof(receipt JSONB) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'policy_version','photo_publication_v1',
 'policy_sha256','b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9','request_sha256',repeat('b',64),
 'provider','gemini','model','gemini-2.5-flash','processor_permission','google_gemini','source',receipt->'source');
$$;
CREATE FUNCTION pg_temp.photo_execution_result(decision TEXT DEFAULT 'approved') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('decision',decision,'classification',CASE WHEN decision='approved' THEN 'allow' ELSE 'reject' END,'confidence',0.99,
 'categories','[]'::JSONB,'model','gemini-2.5-flash','usage',jsonb_build_object('input_tokens',100,'output_tokens',10,'total_tokens',110));
$$;
CREATE FUNCTION pg_temp.prepare_photo_execution(owner_id UUID,observation UUID,receipt JSONB) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.prepare_publication_photo_execution(owner_id,observation,(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,pg_temp.photo_execution_proof(receipt));
$$;


SELECT extensions.ok(NOT (SELECT publication_binding_enabled FROM internal.observation_history_rollout),'binding gate defaults closed');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.bind_approved_publication_photo_cohort(uuid,uuid,uuid)','EXECUTE'),'no live publisher grant');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) r WHERE has_table_privilege(r,'internal.publication_photo_bindings','SELECT,INSERT,UPDATE,DELETE')),'bindings are private');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,rejection_api_enabled=TRUE,publication_intent_enabled=TRUE,publication_moderation_enabled=TRUE;
UPDATE internal.ai_quota_policies SET enabled=TRUE WHERE operation='observation_photo_publication_moderation';
SELECT pg_temp.seed_photo_moderation('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa21','00000000-0000-4000-8000-00000000fa31','00000000-0000-4000-8000-00000000fa41');
CREATE TEMP TABLE copy_test(label TEXT PRIMARY KEY,receipt JSONB);
INSERT INTO copy_test VALUES('attempt',internal.admit_publication_photo_moderation('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa41','00000000-0000-4000-8000-00000000fa31',NULL,repeat('a',64)));
CREATE FUNCTION pg_temp.copy_reserve() RETURNS JSONB LANGUAGE SQL AS $$ SELECT internal.reserve_publication_photo_copy('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11',(receipt->>'attempt_id')::UUID) FROM copy_test WHERE label='attempt'; $$;
CREATE FUNCTION pg_temp.copy_complete(token UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$ SELECT internal.complete_publication_photo_copy('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11',(receipt->>'attempt_id')::UUID,(receipt->>'object_id')::UUID,COALESCE(token,(receipt->>'lease_token')::UUID)) FROM copy_test WHERE label='copy'; $$;
CREATE FUNCTION pg_temp.copy_abandon() RETURNS VOID LANGUAGE SQL AS $$ SELECT internal.abandon_publication_photo_copy('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11',(receipt->>'attempt_id')::UUID,(receipt->>'object_id')::UUID,(receipt->>'lease_token')::UUID) FROM copy_test WHERE label='copy'; $$;
UPDATE internal.observation_history_rollout SET publication_copy_enabled=TRUE,community_admission_enabled=TRUE,community_authority_enabled=TRUE;
SELECT pg_temp.prepare_photo_execution('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11',receipt) FROM copy_test WHERE label='attempt';
SELECT internal.dispatch_publication_photo_moderation('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID) FROM copy_test WHERE label='attempt';
SELECT internal.complete_publication_photo_execution('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11',(receipt->>'attempt_id')::UUID,(receipt->>'lease_token')::UUID,pg_temp.photo_execution_proof(receipt),pg_temp.photo_execution_result()) FROM copy_test WHERE label='attempt';
INSERT INTO copy_test VALUES('copy',pg_temp.copy_reserve());

CREATE FUNCTION pg_temp.bind_copy() RETURNS JSONB LANGUAGE SQL AS $$ SELECT internal.bind_approved_publication_photo_cohort('00000000-0000-4000-8000-00000000fa01','00000000-0000-4000-8000-00000000fa11','00000000-0000-4000-8000-00000000fa41'); $$;
SELECT extensions.throws_ok('SELECT pg_temp.bind_copy()','55000','analysis_history_unavailable','closed binding gate');
UPDATE internal.observation_history_rollout SET publication_binding_enabled=TRUE;
SELECT extensions.throws_ok('SELECT pg_temp.bind_copy()','55000','analysis_history_evidence_unavailable','unready cohort cannot publish');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_posts),0,'failed binding creates no partial post');
SELECT pg_temp.copy_complete();
SAVEPOINT expiry;
UPDATE internal.publication_photo_objects SET available_at=clock_timestamp()-INTERVAL '1 second';
SELECT extensions.throws_ok('SELECT pg_temp.bind_copy()','22023','analysis_history_operation_conflict','expired ready upload cannot publish');
ROLLBACK TO expiry;
INSERT INTO copy_test VALUES('publication',pg_temp.bind_copy());
SELECT extensions.is(pg_temp.bind_copy(),(SELECT receipt FROM copy_test WHERE label='publication'),'lost publication response replays after authority advancement');
SELECT extensions.is((SELECT count(*)::INT FROM internal.publication_photo_bindings),1,'cohort bound once');
SELECT extensions.is((SELECT url FROM public.explore_post_media),'https://media.merian.app/publication_media/v1/'||(SELECT receipt->>'object_id' FROM copy_test WHERE label='copy'),'URL derived from opaque public object only');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_analysis_public_projection),0,'needs-ID admission is not resolved publication');
SELECT extensions.throws_ok('SELECT pg_temp.copy_abandon()','22023','analysis_history_operation_conflict','late writer abort cannot erase committed publication');
UPDATE internal.publication_photo_objects SET available_at=clock_timestamp()-INTERVAL '1 second';
SELECT extensions.ok(internal.claim_publication_photo_erasure() IS NULL,'bound cohort survives original staging deadline');
UPDATE public.explore_posts SET location_sharing='private';
SELECT extensions.ok((SELECT revoked_at IS NULL FROM internal.publication_photo_objects),'hidden location is not unsharing');
SAVEPOINT removal;
UPDATE public.explore_posts SET unshared_at=clock_timestamp();
SELECT extensions.ok((SELECT revoked_at IS NOT NULL FROM internal.publication_photo_objects),'unshare revokes public object');
SELECT extensions.throws_ok('UPDATE public.explore_posts SET unshared_at=NULL','22023','analysis_history_operation_conflict','unhide requires a new publication');
SELECT extensions.ok((SELECT unshared_at IS NOT NULL FROM public.explore_posts),'cannot resurrect erased cohort');
SELECT extensions.is(pg_temp.bind_copy(),(SELECT receipt FROM copy_test WHERE label='publication'),'replay acknowledges history without undoing unshare');
SELECT extensions.ok(internal.claim_publication_photo_erasure() IS NOT NULL,'removed bound copy becomes cleanup eligible');
ROLLBACK TO removal;
UPDATE public.explore_posts SET moderated_at=clock_timestamp();
SELECT extensions.ok((SELECT revoked_at IS NOT NULL FROM internal.publication_photo_objects),'moderation revokes cohort');
SELECT extensions.throws_ok('UPDATE public.explore_posts SET moderated_at=NULL','22023','analysis_history_operation_conflict','moderation unhide requires a new publication');
SELECT extensions.ok((SELECT moderated_at IS NOT NULL FROM public.explore_posts),'moderation reversal does not republish erased bytes');
ROLLBACK TO removal;
UPDATE public.explore_posts SET media_health_status='quarantined';
SELECT extensions.ok((SELECT revoked_at IS NULL FROM internal.publication_photo_objects),'health quarantine preserves reversible recovery');
UPDATE public.explore_posts SET media_health_status='healthy';
SELECT extensions.ok((SELECT unshared_at IS NULL FROM public.explore_posts),'healthy recovery keeps approved bytes');
ROLLBACK TO removal;
DELETE FROM public.explore_posts;
SELECT extensions.ok((SELECT revoked_at IS NOT NULL FROM internal.publication_photo_objects),'post deletion leaves cleanup obligation');
SELECT extensions.throws_ok('SELECT pg_temp.bind_copy()','22023','analysis_history_operation_conflict','deleted publication replay cannot recreate post');
ROLLBACK TO removal;
DELETE FROM internal.observation_photo_copies;
UPDATE public.explore_posts SET location_sharing=location_sharing;
SELECT extensions.ok((SELECT unshared_at IS NOT NULL FROM public.explore_posts),'receipt cascade and no-op refresh hide without vetoing deletion');
ROLLBACK TO removal;
SELECT public.apply_user_tombstone('00000000-0000-4000-8000-00000000fa01');
SELECT extensions.ok((SELECT revoked_at IS NOT NULL FROM internal.publication_photo_objects),'account tombstone revokes bound objects');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM public.explore_posts WHERE unshared_at IS NULL),'account deletion leaves no visible post');
SELECT extensions.throws_ok('SELECT pg_temp.bind_copy()','P0002','analysis_history_not_found','deletion wins over replay');

-- Two-photo cohort: order is chosen by the immutable intent, and a partial
-- ready set must not create a request, post, binding or revision change.
CREATE TEMP TABLE cohort_fixture(owner_id UUID,observation UUID,analysis UUID,operation UUID,media_a UUID,media_b UUID);
INSERT INTO cohort_fixture VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
CREATE TEMP TABLE cohort_copies(media_id UUID,receipt JSONB);
DO $$
DECLARE f cohort_fixture; input JSONB; request JSONB; media UUID; attempt JSONB; copy JSONB;
BEGIN
 SELECT * INTO f FROM cohort_fixture;
 PERFORM pg_temp.seed_funded_history(f.owner_id,f.observation);
 PERFORM pg_temp.protected_ready(f.owner_id,f.observation,f.analysis,f.media_a);
 PERFORM pg_temp.protected_ready(f.owner_id,f.observation,f.analysis,f.media_b);
 input:=pg_temp.protected_input(f.observation,f.analysis,f.media_a);
 input:=jsonb_set(input,'{evidence_manifest,items}',(input#>'{evidence_manifest,items}')||jsonb_build_array(pg_temp.protected_input(f.observation,f.analysis,f.media_b)#>'{evidence_manifest,items,0}'));
 PERFORM internal.admit_protected_observation_analysis(f.owner_id,input,repeat('a',64));
 PERFORM pg_temp.funded_dispatch(f.owner_id,f.observation,f.analysis);
 PERFORM pg_temp.protected_draft(f.owner_id,f.observation,f.analysis);
 PERFORM internal.complete_observation_analysis(f.owner_id,f.observation,f.analysis);
 request:=jsonb_set(pg_temp.publication_request(f.observation,f.analysis,f.operation,f.media_a),'{media_ids}',jsonb_build_array(f.media_b,f.media_a));
 PERFORM internal.prepare_observation_publication_intent(f.owner_id,request);
 FOREACH media IN ARRAY ARRAY[f.media_a,f.media_b] LOOP
  attempt:=internal.admit_publication_photo_moderation(f.owner_id,f.observation,f.operation,media,NULL,repeat('a',64));
  PERFORM pg_temp.prepare_photo_execution(f.owner_id,f.observation,attempt);
  PERFORM internal.dispatch_publication_photo_moderation(f.owner_id,f.observation,(attempt->>'attempt_id')::UUID,(attempt->>'lease_token')::UUID);
  PERFORM internal.complete_publication_photo_execution(f.owner_id,f.observation,(attempt->>'attempt_id')::UUID,(attempt->>'lease_token')::UUID,pg_temp.photo_execution_proof(attempt),pg_temp.photo_execution_result());
  copy:=internal.reserve_publication_photo_copy(f.owner_id,f.observation,(attempt->>'attempt_id')::UUID);
  INSERT INTO cohort_copies VALUES(media,copy);
  IF media=f.media_b THEN PERFORM internal.complete_publication_photo_copy(f.owner_id,f.observation,(copy->>'attempt_id')::UUID,(copy->>'object_id')::UUID,(copy->>'lease_token')::UUID); END IF;
 END LOOP;
END;
$$;
CREATE FUNCTION pg_temp.bind_cohort() RETURNS JSONB LANGUAGE SQL AS $$ SELECT internal.bind_approved_publication_photo_cohort(owner_id,observation,operation) FROM cohort_fixture; $$;
SELECT extensions.throws_ok('SELECT pg_temp.bind_cohort()','55000','analysis_history_evidence_unavailable','partial ready cohort is rejected');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_posts WHERE scan_id=(SELECT observation FROM cohort_fixture)),0,'partial cohort exposes no post');
SELECT extensions.is((SELECT state_revision FROM internal.observation_histories WHERE observation_id=(SELECT observation FROM cohort_fixture)),1,'partial cohort does not advance authority');
SELECT internal.complete_publication_photo_copy(f.owner_id,f.observation,(c.receipt->>'attempt_id')::UUID,(c.receipt->>'object_id')::UUID,(c.receipt->>'lease_token')::UUID) FROM cohort_fixture f JOIN cohort_copies c ON c.media_id=f.media_a;
SELECT pg_temp.bind_cohort();
SELECT extensions.is((SELECT array_agg(b.object_id ORDER BY b.order_index) FROM internal.publication_photo_bindings b JOIN public.explore_posts p ON p.id=b.post_id WHERE p.scan_id=(SELECT observation FROM cohort_fixture)),
 (SELECT ARRAY[(SELECT (receipt->>'object_id')::UUID FROM cohort_copies WHERE media_id=f.media_b),(SELECT (receipt->>'object_id')::UUID FROM cohort_copies WHERE media_id=f.media_a)] FROM cohort_fixture f),'entire cohort follows requested order, not allocation order');
SELECT extensions.is((SELECT object_ids FROM internal.observation_photo_publications WHERE operation_id=(SELECT operation FROM cohort_fixture)),
 (SELECT array_agg(b.object_id ORDER BY b.order_index) FROM internal.publication_photo_bindings b JOIN public.explore_posts p ON p.id=b.post_id WHERE p.scan_id=(SELECT observation FROM cohort_fixture)),'immutable receipt records entire ordered cohort');
SELECT extensions.throws_ok('UPDATE internal.observation_photo_publications SET object_ids=ARRAY[gen_random_uuid()]','22023','analysis_history_evidence_immutable','publisher receipt cannot change');
SELECT * FROM extensions.finish();
ROLLBACK;
