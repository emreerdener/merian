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

SELECT extensions.ok(NOT (SELECT execution_status_api_enabled FROM internal.observation_history_rollout WHERE singleton),'execution status defaults closed');
SELECT extensions.ok(has_function_privilege('authenticated','public.get_owned_observation_analysis_execution(jsonb,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.get_owned_observation_analysis_execution(jsonb,integer)','EXECUTE') AND NOT has_function_privilege('service_role','public.get_owned_observation_analysis_execution(jsonb,integer)','EXECUTE'),'only authenticated owns the read');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000f701','00000000-0000-4000-8000-00000000f711');
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000f702','00000000-0000-4000-8000-00000000f712');
CREATE FUNCTION pg_temp.status_request(analysis UUID DEFAULT '00000000-0000-4000-8000-00000000f721',source UUID DEFAULT NULL) RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'observation_id','00000000-0000-4000-8000-00000000f711','analysis_id',analysis,'source_analysis_id',source,'request_digest',repeat('a',64));
$$;
GRANT EXECUTE ON FUNCTION pg_temp.status_request(UUID,UUID) TO authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000f701","role":"authenticated"}',TRUE);
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)$$,'55000','analysis_history_unavailable','status gate closed');
UPDATE internal.observation_history_rollout SET execution_status_api_enabled=TRUE,reader_enabled=FALSE;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)$$,'55000','analysis_history_unavailable','reader gate still required');
UPDATE internal.observation_history_rollout SET reader_enabled=TRUE;
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_analysis_execution(pg_temp.status_request(),9),pg_temp.status_request()||'{"owner_id":"00000000-0000-4000-8000-00000000f701","state":"absent"}'::JSONB,'absence echoes exact identity and carries no permission');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request(),8)$$,'22023','invalid_analysis_history','reader 9 required');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request()||'{"owner_id":"00000000-0000-4000-8000-00000000f702"}',9)$$,'22023','invalid_analysis_history','owner input forbidden');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request()||'{"schema_version":true}',9)$$,'22023','invalid_analysis_history','boolean schema forbidden');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request()-'source_analysis_id',9)$$,'22023','invalid_analysis_history','nullable source must be explicit');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request()||'{"source_analysis_id":"00000000-0000-4000-8000-00000000f721"}',9)$$,'22023','invalid_analysis_history','source cannot equal child');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request()||'{"observation_id":"00000000-0000-4000-8000-00000000f712"}',9)$$,'P0002','analysis_history_not_found','foreign observation is opaque');
RESET ROLE;
UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE;
SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000f701',pg_temp.funded_input('00000000-0000-4000-8000-00000000f711','00000000-0000-4000-8000-00000000f721'),repeat('a',64));
CREATE FUNCTION pg_temp.execution_snapshot() RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('intent',(SELECT to_jsonb(i) FROM internal.observation_analysis_intents i WHERE analysis_id='00000000-0000-4000-8000-00000000f721'),'quota',(SELECT to_jsonb(q) FROM internal.ai_quota_reservations q WHERE original_analysis_id='00000000-0000-4000-8000-00000000f721'),'history',(SELECT to_jsonb(h) FROM internal.observation_histories h WHERE observation_id='00000000-0000-4000-8000-00000000f711'),'usage',(SELECT jsonb_agg(to_jsonb(u)) FROM public.ai_usage_events u WHERE scan_id='00000000-0000-4000-8000-00000000f721'));
$$;
CREATE TEMP TABLE before_status(value JSONB);
INSERT INTO before_status SELECT pg_temp.execution_snapshot();
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)->>'state','admitted','admitted is observable without claiming');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request()||jsonb_build_object('request_digest',repeat('b',64)),9)$$,'22023','analysis_history_operation_conflict','digest conflict never absence');
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request('00000000-0000-4000-8000-00000000f721','00000000-0000-4000-8000-00000000f799'),9)$$,'22023','analysis_history_operation_conflict','source conflict never absence');
RESET ROLE;
SELECT extensions.is(pg_temp.execution_snapshot(),(SELECT value FROM before_status),'read never changes claim, quota, history or provider usage');
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000f701','00000000-0000-4000-8000-00000000f711','00000000-0000-4000-8000-00000000f721');
TRUNCATE before_status; INSERT INTO before_status SELECT pg_temp.execution_snapshot();
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)->>'state','dispatched','unknown dispatched result remains only status');
RESET ROLE;
SELECT extensions.is(pg_temp.execution_snapshot(),(SELECT value FROM before_status),'dispatched read neither redispatches nor refunds');
SELECT pg_temp.funded_draft('00000000-0000-4000-8000-00000000f701','00000000-0000-4000-8000-00000000f711','00000000-0000-4000-8000-00000000f721');
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)->>'state','draft','draft read exposes no private result or usage');
RESET ROLE;
SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000f701','00000000-0000-4000-8000-00000000f711','00000000-0000-4000-8000-00000000f721');
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)->>'state','complete','completed result still requires separate exact result recovery');
RESET ROLE;
SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000f701',pg_temp.funded_input('00000000-0000-4000-8000-00000000f711','00000000-0000-4000-8000-00000000f722','00000000-0000-4000-8000-00000000f721'),repeat('a',64));
SELECT internal.fail_observation_analysis(owner_id,observation_id,analysis_id,(quota->>'lease_token')::UUID,'cancelled_before_dispatch','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000f722';
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_analysis_execution(pg_temp.status_request('00000000-0000-4000-8000-00000000f722','00000000-0000-4000-8000-00000000f721'),9)->>'state','failed_terminal','terminal state retains exact non-null source');
RESET ROLE;
UPDATE internal.observation_history_rollout SET admission_enabled=FALSE,dispatch_enabled=FALSE;
SET LOCAL ROLE authenticated;
SELECT extensions.is(public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)->>'state','complete','read independent of inference admission and dispatch gates');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000f702","role":"authenticated"}',TRUE);
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request()||'{"observation_id":"00000000-0000-4000-8000-00000000f712"}',9)$$,'22023','analysis_history_operation_conflict','child of another owner is not absent');
RESET ROLE;
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-00000000f701","role":"authenticated"}',TRUE);
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000f711','00000000-0000-4000-8000-00000000f701');
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.get_owned_observation_analysis_execution(pg_temp.status_request(),9)$$,'P0002','analysis_history_not_found','deletion wins even previously completed status');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
