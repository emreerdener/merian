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

SELECT extensions.ok(NOT (SELECT publication_intent_enabled FROM internal.observation_history_rollout),'preflight remains gated off');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated','service_role']) r WHERE n.nspname='internal' AND p.proname='lock_publication_consent_eligibility' AND has_function_privilege(r,p.oid,'EXECUTE')),'shared lock helper remains private');
SELECT extensions.ok(has_function_privilege('service_role','public.prepare_owned_observation_publication_consent(uuid,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('authenticated','public.prepare_owned_observation_publication_consent(uuid,uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','public.prepare_owned_observation_publication_consent(uuid,uuid,uuid)','EXECUTE'),'only service caller reaches owner RPC');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE,state_reader_enabled=TRUE,rejection_api_enabled=TRUE;
SELECT pg_temp.seed_publication_intent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe31');
CREATE FUNCTION pg_temp.consent(analysis UUID DEFAULT '00000000-0000-4000-8000-00000000fe21') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.prepare_owned_observation_publication_consent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11',analysis);
$$;
SELECT extensions.throws_ok('SELECT pg_temp.consent()','55000','analysis_history_unavailable','closed gate denies preflight');
UPDATE internal.observation_history_rollout SET publication_intent_enabled=TRUE;
CREATE TEMP TABLE original_consent AS SELECT pg_temp.consent() AS value;
SELECT extensions.is((SELECT value-ARRAY['schema_version','observation_id','analysis_id','expected_observation_revision','expected_review_revision','taxonomy_version_id','initial_taxon_id','media'] FROM original_consent),'{}'::JSONB,'closed response includes no private evidence or operation');
SELECT extensions.is((SELECT value->'media' FROM original_consent),'[{"media_id":"00000000-0000-4000-8000-00000000fe31","content_type":"image/jpeg","byte_count":3,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'::JSONB,'candidate contains only immutable metadata');
SELECT extensions.is((SELECT value->'initial_taxon_id' FROM original_consent),'null'::JSONB,'initial taxon fixed null');
SELECT extensions.is((SELECT (value->>'taxonomy_version_id')::UUID FROM original_consent),public.active_taxonomy_version_id(),'active taxonomy version returned');
SELECT extensions.is((SELECT value->>'expected_observation_revision' FROM original_consent),'1','current observation revision returned');
SELECT extensions.is((SELECT value->>'expected_review_revision' FROM original_consent),'0','current review revision returned');
SELECT extensions.is((SELECT count(*)::INT FROM internal.observation_publication_intents),0,'preflight does not admit an operation');
SELECT extensions.throws_ok($$SELECT public.prepare_owned_observation_publication_consent('00000000-0000-4000-8000-00000000fe02','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21')$$,'P0002','analysis_history_not_found','foreign owner opaque');
SET LOCAL ROLE service_role;
SELECT extensions.lives_ok($$SELECT public.prepare_owned_observation_publication_consent('00000000-0000-4000-8000-00000000fe01','00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21')$$,'actual service role can read authorized owner');
RESET ROLE;
-- Candidate reads intentionally do not promise ready private transport.
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET ready_at=NULL WHERE media_id='00000000-0000-4000-8000-00000000fe31';
SELECT extensions.is(pg_temp.consent(),(SELECT value FROM original_consent),'readiness does not rewrite frozen candidate metadata');
SELECT extensions.throws_ok($$SELECT internal.prepare_observation_publication_intent('00000000-0000-4000-8000-00000000fe01',pg_temp.publication_request('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe41','00000000-0000-4000-8000-00000000fe31'))$$,'P0002','analysis_history_not_found','actual admission still requires ready receipt');
UPDATE internal.observation_evidence_objects SET ready_at=now() WHERE media_id='00000000-0000-4000-8000-00000000fe31';
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
-- Synthetic imported fixture tests projection independently of funded completion.
-- Disable only the completion-proof insert guard while seeding the frozen V2 row.
ALTER TABLE internal.observation_analysis_results DISABLE TRIGGER guard_observation_media_binding;
-- Explicit historical analysis remains legal; no selected-analysis restriction.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000fe22',observation_id,2,repeat('b',64),result_snapshot,
 jsonb_build_object('schema_version',2,'items',(SELECT jsonb_agg(jsonb_build_object('kind','image','media_id',('00000000-0000-4000-8000-'||lpad((100-n)::TEXT,12,'0'))::UUID,'content_type','image/jpeg','byte_count',10,'sha256',repeat('b',64)) ORDER BY n) FROM generate_series(1,64) n)),now()
FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000fe21';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000fe22',review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000fe21';
ALTER TABLE internal.observation_analysis_results ENABLE TRIGGER guard_observation_media_binding;
SELECT extensions.is(jsonb_array_length(pg_temp.consent('00000000-0000-4000-8000-00000000fe22')->'media'),64,'all 64 candidates preserved without silently selecting six');
SELECT extensions.is(pg_temp.consent('00000000-0000-4000-8000-00000000fe22')#>>'{media,0,media_id}','00000000-0000-4000-8000-000000000099','manifest order preserved instead of UUID sorting');
SELECT extensions.is((SELECT selected_analysis_id FROM internal.observation_histories WHERE observation_id='00000000-0000-4000-8000-00000000fe11'),'00000000-0000-4000-8000-00000000fe21'::UUID,'historical read changes no selection');
-- Legacy evidence denial follows stale-revision denial in the existing resolver.
INSERT INTO internal.observation_analysis_results(analysis_id,observation_id,ordinal,request_digest,result_snapshot,evidence_manifest,completed_at)
SELECT '00000000-0000-4000-8000-00000000fe23',observation_id,3,repeat('c',64),result_snapshot,'{"schema_version":1,"captured_media":[]}',now() FROM internal.observation_analysis_results WHERE analysis_id='00000000-0000-4000-8000-00000000fe21';
INSERT INTO internal.observation_analysis_authorities(observation_id,analysis_id,review_snapshot)
SELECT observation_id,'00000000-0000-4000-8000-00000000fe23',review_snapshot FROM internal.observation_analysis_authorities WHERE analysis_id='00000000-0000-4000-8000-00000000fe21';
SELECT extensions.throws_ok($$SELECT pg_temp.consent('00000000-0000-4000-8000-00000000fe23')$$,'55000','analysis_history_evidence_unavailable','V1 unavailable');
SELECT extensions.throws_ok($$SELECT internal.resolve_publication_intent_sources('00000000-0000-4000-8000-00000000fe01',pg_temp.publication_request('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe23','00000000-0000-4000-8000-00000000fe41','00000000-0000-4000-8000-00000000fe31')||'{"expected_review_revision":1}')$$,'40001','analysis_history_revision_conflict','revision denial precedes evidence denial');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000fe01"}',TRUE);
SELECT public.review_owned_observation_analysis(pg_temp.publication_request('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe21','00000000-0000-4000-8000-00000000fe42','00000000-0000-4000-8000-00000000fe31')-ARRAY['taxonomy_version_id','initial_taxon_id','note','media_ids']||'{"action":"reject","undo_operation_id":null}',9);
SELECT set_config('request.jwt.claims','{"role":"service_role"}',TRUE);
SELECT extensions.is(pg_temp.consent()->>'expected_review_revision','1','AI rejection retains unreviewed community-intake scope and returns current review revision');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000fe11','00000000-0000-4000-8000-00000000fe01');
SELECT extensions.throws_ok($$SELECT pg_temp.consent('00000000-0000-4000-8000-00000000fe22')$$,'P0002','analysis_history_not_found','deletion wins all historical reads');
SELECT * FROM extensions.finish();
ROLLBACK;
