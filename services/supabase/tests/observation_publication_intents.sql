\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
-- BEGIN PUBLICATION INTENT HELPERS
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
-- END PUBLICATION INTENT HELPERS
SELECT extensions.ok(NOT (SELECT publication_intent_enabled FROM internal.observation_history_rollout),'intent gate defaults closed');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated','service_role']) r
 WHERE n.nspname='internal' AND p.proname IN ('prepare_observation_publication_intent','revalidate_observation_publication_intent','resolve_publication_intent_sources') AND has_function_privilege(r,p.oid,'EXECUTE')),'no API role can invoke preparation or revalidation');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_publication_intents','SELECT') AND NOT has_table_privilege('authenticated','internal.observation_publication_intents','INSERT'),'private storage has no API access');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,rejection_api_enabled=TRUE;
SELECT pg_temp.seed_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe31');
CREATE TEMP TABLE publication_fixture AS SELECT pg_temp.publication_request('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe41','00000000-0000-4000-8000-00000000fe31') AS request;
CREATE FUNCTION pg_temp.prepare_fixture(delta JSONB DEFAULT '{}') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT internal.prepare_observation_publication_intent('00000000-0000-4000-8000-00000000fe01',request||delta) FROM publication_fixture;
$$;
SELECT extensions.throws_ok('SELECT pg_temp.prepare_fixture()','55000','analysis_history_unavailable','closed gate stores no intent');
UPDATE internal.observation_history_rollout SET publication_intent_enabled=TRUE;
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"url":"https://example.invalid/untrusted.jpg"}')$$,'22023','invalid_analysis_history','caller URLs are never source evidence');
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"media_ids":[]}')$$,'22023','invalid_analysis_history','empty media refused');
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"media_ids":["00000000-0000-4000-8000-00000000fe31","00000000-0000-4000-8000-00000000fe31"]}')$$,'22023','invalid_analysis_history','duplicate media refused');
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"expected_observation_revision":true}')$$,'22023','invalid_analysis_history','boolean revision refused');
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture(jsonb_build_object('note',repeat('x',1001)))$$,'22023','invalid_analysis_history','oversize note refused');
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"media_ids":["00000000-0000-4000-8000-00000000fe39"]}')$$,'P0002','analysis_history_not_found','unnamed source refused');
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"expected_review_revision":1}')$$,'40001','analysis_history_revision_conflict','stale review refused');
SELECT extensions.throws_ok($$SELECT internal.prepare_observation_publication_intent('00000000-0000-4000-8000-00000000fe02',request) FROM publication_fixture$$,'P0002','analysis_history_not_found','foreign owner cannot prepare');
CREATE TEMP TABLE prepared AS SELECT pg_temp.prepare_fixture() AS value;
SELECT extensions.is(pg_temp.prepare_fixture(),(SELECT value FROM prepared),'lost response replays the identical preparation');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_intents),1,'one operation remains');
SELECT extensions.is((SELECT value->'sources'->0 FROM prepared),(SELECT jsonb_build_object('media_id',media_id,'object_id',object_id,'content_type',content_type,'byte_count',byte_count,'sha256',sha256) FROM internal.observation_evidence_objects WHERE media_id='00000000-0000-4000-8000-00000000fe31'),'sources bind exact verified private content and opaque object identity');
SELECT extensions.is((SELECT count(*)::INT FROM public.explore_posts WHERE scan_id='00000000-0000-4000-8000-00000000fe11'),0,'preparation publishes nothing');
SELECT extensions.ok((SELECT state_revision=1 AND selected_analysis_id='00000000-0000-4000-8000-00000000fe21' FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fe11'),'preparation changes no selection or authority');
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"note":"changed"}')$$,'22023','analysis_history_operation_conflict','retry cannot replace frozen intent');
SELECT extensions.throws_ok($$UPDATE internal.observation_publication_intents SET sources='[]'$$,'22023','analysis_history_evidence_immutable','private preparation is immutable');
SELECT extensions.is(internal.revalidate_observation_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41'),(SELECT value FROM prepared),'fresh revalidation matches frozen sources');
UPDATE internal.observation_history_rollout SET publication_intent_enabled=FALSE;
SELECT extensions.is(pg_temp.prepare_fixture(),(SELECT value FROM prepared),'closure preserves historical preparation replay');
SELECT extensions.throws_ok($$SELECT internal.revalidate_observation_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41')$$,'55000','analysis_history_unavailable','historical replay cannot authorize work after gate closure');
UPDATE internal.observation_history_rollout SET publication_intent_enabled=TRUE;
-- Unsupported snapshots never gain a protected-photo proof by naming another result's media.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000fe22',observation_id,2,repeat('b',64),result_snapshot,'{"schema_version":1,"captured_media":[]}',now()
FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000fe21';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000fe22',review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000fe21';
SELECT extensions.throws_ok($$SELECT pg_temp.prepare_fixture('{"operation_id":"00000000-0000-4000-8000-00000000fe43","analysis_id":"00000000-0000-4000-8000-00000000fe22"}')$$,'55000','analysis_history_evidence_unavailable','legacy V1 cannot authorize private photo publication');
-- Fault injection proves revalidation checks durable receipt facts, not only an old intent.
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET sha256=repeat('b',64) WHERE media_id='00000000-0000-4000-8000-00000000fe31';
SELECT extensions.throws_ok($$SELECT internal.revalidate_observation_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41')$$,'55000','analysis_history_evidence_unavailable','changed content cannot pass revalidation');
UPDATE internal.observation_evidence_objects SET sha256=repeat('a',64),ready_at=NULL WHERE media_id='00000000-0000-4000-8000-00000000fe31';
SELECT extensions.throws_ok($$SELECT internal.revalidate_observation_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41')$$,'P0002','analysis_history_not_found','unready receipt cannot pass revalidation');
UPDATE internal.observation_evidence_objects SET ready_at=now() WHERE media_id='00000000-0000-4000-8000-00000000fe31';
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT internal.revalidate_observation_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41')$$,'42501',NULL,'actual service role has no execution grant');
RESET ROLE;
-- A real owner review invalidates execution but does not rewrite historical intent.
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000fe01"}',TRUE);
SELECT public.review_owned_observation_analysis((SELECT request-ARRAY['taxonomy_version_id','initial_taxon_id','note','media_ids']||'{"action":"reject","undo_operation_id":null,"operation_id":"00000000-0000-4000-8000-00000000fe42"}' FROM publication_fixture),9);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.is(pg_temp.prepare_fixture(),(SELECT value FROM prepared),'authority change preserves historical evidence only');
SELECT extensions.throws_ok($$SELECT internal.revalidate_observation_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41')$$,'40001','analysis_history_revision_conflict','review invalidates prepared execution');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe01');
SELECT extensions.throws_ok('SELECT pg_temp.prepare_fixture()','P0002','analysis_history_not_found','deletion wins historical replay');
SELECT extensions.throws_ok($$SELECT internal.revalidate_observation_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe41')$$,'P0002','analysis_history_not_found','deletion wins revalidation');
DELETE FROM public.scans WHERE id='00000000-0000-4000-8000-00000000fe11';
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_intents),0,'scan deletion cascades private intent');
SELECT * FROM extensions.finish();
ROLLBACK;
