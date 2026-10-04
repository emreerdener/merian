\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();
CREATE FUNCTION pg_temp.history_append_request(observation UUID, analysis UUID, source UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE SQL AS $$
    SELECT JSONB_BUILD_OBJECT('schema_version',1,'observation_id',observation,'analysis_id',analysis,
        'source_analysis_id',source,'request_digest',REPEAT('a',64),
        'result_snapshot',JSONB_BUILD_OBJECT('scan_id',observation,'species_id',NULL,
            'scientific_name',NULL,'common_name','Synthetic object','is_biological_subject',FALSE,
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
 SELECT pg_temp.funded_input(observation,analysis) || jsonb_build_object('schema_version',2,'history_protocol',8,'expected_processor_permission','openai','evidence_manifest',jsonb_build_object('schema_version',2,'items',jsonb_build_array(jsonb_build_object('kind','image','media_id',media,'content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),jsonb_build_object('kind','description','text','Synthetic private observation'))));
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

SELECT extensions.ok(NOT(SELECT reader_enabled OR media_reader_enabled FROM internal.observation_history_rollout),'read gates remain closed');
SELECT extensions.ok(NOT has_function_privilege('authenticated','public.resolve_owned_observation_photo(uuid,uuid,uuid,uuid,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.resolve_owned_observation_photo(uuid,uuid,uuid,uuid,integer)','EXECUTE'),'clients cannot fetch internal object receipts');
SELECT extensions.ok(has_function_privilege('service_role','public.resolve_owned_observation_photo(uuid,uuid,uuid,uuid,integer)','EXECUTE'),'trusted adapter can resolve with explicit service authorization');
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811');
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT extensions.throws_ok($$SELECT public.resolve_owned_observation_photo('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821','00000000-0000-4000-8000-00000000e831',8)$$,'55000','analysis_history_unavailable','default gate rejects media resolution');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET media_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE,reader_enabled=TRUE,media_reader_enabled=TRUE;
SELECT internal.append_observation_analysis('00000000-0000-4000-8000-00000000e801',pg_temp.history_append_request('00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e820'));
SELECT pg_temp.protected_ready('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821','00000000-0000-4000-8000-00000000e831');
SELECT extensions.throws_ok($$SELECT public.resolve_owned_observation_photo('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821','00000000-0000-4000-8000-00000000e831',8)$$,'P0002','analysis_history_not_found','ready upload alone is not a readable history result');
SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000e801',pg_temp.protected_input('00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821','00000000-0000-4000-8000-00000000e831'),repeat('a',64));
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821');
SELECT pg_temp.protected_draft('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821');
SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000e801','00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821');
CREATE FUNCTION pg_temp.photo(owner_id UUID DEFAULT '00000000-0000-4000-8000-00000000e801',media UUID DEFAULT '00000000-0000-4000-8000-00000000e831',reader INTEGER DEFAULT 8) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.resolve_owned_observation_photo(owner_id,'00000000-0000-4000-8000-00000000e811','00000000-0000-4000-8000-00000000e821',media,reader);
$$;
SELECT extensions.is(pg_temp.photo()->>'media_id','00000000-0000-4000-8000-00000000e831','completed exact photo resolves');
SELECT extensions.throws_ok($$SELECT pg_temp.photo('00000000-0000-4000-8000-00000000e802')$$,'P0002','analysis_history_not_found','foreign or detached owner cannot resolve');
SELECT extensions.throws_ok($$SELECT pg_temp.photo(media:='00000000-0000-4000-8000-00000000e832')$$,'P0002','analysis_history_not_found','unreferenced media cannot resolve');
SELECT extensions.throws_ok($$SELECT pg_temp.photo(reader:=7)$$,'22023','invalid_analysis_history','old media reader rejected');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000e801"}',true);
GRANT EXECUTE ON FUNCTION pg_temp.photo(UUID,UUID,INTEGER) TO authenticated,service_role;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.photo()','42501',NULL,'normal role cannot resolve internal receipts');
RESET ROLE;
CREATE FUNCTION pg_temp.page(reader INTEGER,before_ordinal INTEGER DEFAULT NULL,page_limit INTEGER DEFAULT 20) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT public.get_owned_observation_analysis_page(jsonb_build_object('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000e811','before_ordinal',before_ordinal,'limit',page_limit),reader);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.page(INTEGER,INTEGER,INTEGER) TO authenticated;
SET LOCAL ROLE authenticated;
SELECT extensions.is(jsonb_array_length(pg_temp.page(8)->'items'),2,'protocol 8 reads mixed history');
SELECT extensions.is(((pg_temp.page(8)->'items'->0->>'snapshot')::JSONB->>'schema_version'),'2','newest snapshot is V2');
SELECT extensions.is(((pg_temp.page(8)->'items'->1->>'snapshot')::JSONB->>'schema_version'),'1','original V1 snapshot is retained');
SELECT extensions.is(pg_temp.page(8,NULL,1)->>'next_before_ordinal','2','mixed page resumes before last ordinal');
SELECT extensions.is(jsonb_array_length(pg_temp.page(8,2)->'items'),1,'cursor reads remaining V1 result');
SELECT extensions.throws_ok('SELECT pg_temp.page(7,2)','55000','analysis_history_reader_upgrade_required','old reader cannot bypass V2 with cursor');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000e802"}',true);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.page(7)','P0002','analysis_history_not_found','ownership checked before version disclosure');
RESET ROLE;
UPDATE public.scans SET is_tombstoned=TRUE WHERE id='00000000-0000-4000-8000-00000000e811';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT extensions.throws_ok('SELECT pg_temp.photo()','P0002','analysis_history_not_found','deletion fence supersedes issued-photo retries');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-00000000e801"}',true);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok('SELECT pg_temp.page(8)','P0002','analysis_history_not_found','deletion blocks new history reads');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
