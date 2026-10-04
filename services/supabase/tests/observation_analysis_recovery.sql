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

SELECT extensions.ok(NOT(SELECT orchestration_enabled FROM internal.observation_history_rollout WHERE singleton),'orchestration remains closed');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated']) AS r WHERE n.nspname='public' AND p.proname IN ('begin_owned_observation_analysis','claim_observation_analysis_recovery','list_observation_analysis_recovery','advance_owned_observation_analysis') AND has_function_privilege(r,p.oid,'EXECUTE')),'only trusted service can orchestrate analyses');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911');
CREATE FUNCTION pg_temp.begin_work() RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.begin_owned_observation_analysis('00000000-0000-4000-8000-00000000a901',pg_temp.funded_input('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921'),repeat('a',64)); $$;
SELECT extensions.throws_ok('SELECT pg_temp.begin_work()','55000','analysis_history_unavailable','closed orchestration creates no intent');
UPDATE internal.observation_history_rollout SET orchestration_enabled=TRUE,admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE;
UPDATE internal.observation_history_rollout SET append_enabled=FALSE;
SELECT extensions.throws_ok('SELECT pg_temp.begin_work()','55000','analysis_history_unavailable','partial rollout refuses admission before a hold');
SELECT extensions.is((SELECT count(*) FROM internal.complimentary_scan_usage WHERE user_id='00000000-0000-4000-8000-00000000a901'),0::BIGINT,'partial rollout consumes no hold');
UPDATE internal.observation_history_rollout SET append_enabled=TRUE;
CREATE TEMP TABLE claim AS SELECT pg_temp.begin_work() AS value;
SELECT extensions.is((SELECT value->>'state' FROM claim),'admitted','first request claims admitted intent');
SELECT extensions.is(pg_temp.begin_work()->'claimed','false'::JSONB,'simultaneous retry cannot take active claim');
CREATE FUNCTION pg_temp.advance(operation TEXT,payload JSONB DEFAULT '{}') RETURNS JSONB LANGUAGE SQL AS $$ SELECT public.advance_owned_observation_analysis('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921',(SELECT (value->>'work_token')::UUID FROM claim),operation,payload); $$;
SELECT extensions.is(pg_temp.advance('materialize'),'[]'::JSONB,'description requires no private objects');
SELECT extensions.is(pg_temp.advance('dispatch',jsonb_build_object('provenance',pg_temp.funded_provenance('00000000-0000-4000-8000-00000000a921')))->'may_dispatch','true'::JSONB,'claimed dispatch admits one execution');
SELECT extensions.is(pg_temp.begin_work()->'claimed','false'::JSONB,'dispatched outcome is not permission for new inference');
SELECT extensions.is(public.list_observation_analysis_recovery(),'[]'::JSONB,'uncertain execution never enters automatic recovery');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('fail','{"reason":"timeout"}')$$,'22023','invalid_analysis_history','timeout cannot release hold');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('fail','{"reason":"provider_refusal"}')$$,'22023','invalid_analysis_history','terminal claim needs durable provider evidence');
CREATE TEMP TABLE outcome AS SELECT jsonb_build_object('quota_token',quota->'lease_token','value',jsonb_build_object('schema_version',1,'provenance',pg_temp.funded_provenance(analysis_id),'outcome',jsonb_build_object('kind','draft','result',(pg_temp.history_append_request(observation_id,analysis_id)->'result_snapshot')-'species_id' || jsonb_build_object('identification_provenance',pg_temp.funded_provenance(analysis_id))),'usage','{}'::JSONB)) AS value FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE analysis_id='00000000-0000-4000-8000-00000000a921';
SELECT pg_temp.advance('outcome',(SELECT value FROM outcome));
SELECT extensions.is(jsonb_array_length(public.list_observation_analysis_recovery()),1,'received outcome becomes recoverable even after claim expiry');
SELECT extensions.lives_ok($$SELECT pg_temp.advance('outcome',(SELECT value FROM outcome))$$,'lost outcome response supports exact retry');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('outcome',(SELECT jsonb_set(value,'{value,outcome,kind}','"refusal"') FROM outcome))$$,'22023','analysis_history_operation_conflict','received outcome cannot be replaced');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('release')$$,'22023','analysis_history_operation_conflict','stale worker cannot change recovery scheduling');
UPDATE claim SET value=public.claim_observation_analysis_recovery('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921');
SELECT extensions.is((SELECT value->'claimed' FROM claim),'true'::JSONB,'recovery takes expired claim without provider dispatch');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000a921'),'held','received outcome alone does not consume credit');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('draft',jsonb_build_object('draft',pg_temp.history_append_request('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921') || jsonb_build_object('result_snapshot',(SELECT value#>'{value,outcome,result}' FROM outcome) || '{"confidence_score":0.01}'::JSONB || jsonb_build_object('species_id',NULL,'identification_provenance',pg_temp.funded_provenance('00000000-0000-4000-8000-00000000a921')))))$$,'22023','invalid_analysis_history','same provenance cannot authorize a different result');
SELECT pg_temp.advance('draft',jsonb_build_object('draft',pg_temp.history_append_request('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a921') || jsonb_build_object('result_snapshot',(SELECT value#>'{value,outcome,result}' FROM outcome) || jsonb_build_object('species_id',NULL,'identification_provenance',pg_temp.funded_provenance('00000000-0000-4000-8000-00000000a921')))));
SELECT extensions.is(pg_temp.advance('complete')->>'state','complete','draft completion is atomic');
SELECT extensions.is(pg_temp.begin_work(),' {"state":"complete","claimed":false}'::JSONB,'lost completion replay returns only terminal state');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE scan_id='00000000-0000-4000-8000-00000000a921'),1::BIGINT,'all retries retain one provider execution');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000a921'),'consumed','only durable completion consumes credit');
-- Live worker can prove it never entered invoke after a lost dispatch ACK.
SELECT public.begin_owned_observation_analysis('00000000-0000-4000-8000-00000000a901',pg_temp.funded_input('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a922'),repeat('a',64));
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a922');
SELECT public.advance_owned_observation_analysis(owner_id,observation_id,analysis_id,work_token,'cancel_uninvoked','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000a922';
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000a922'),'released','proven live-worker non-dispatch releases hold');
SELECT public.begin_owned_observation_analysis('00000000-0000-4000-8000-00000000a901',pg_temp.funded_input('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a923'),repeat('a',64));
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000a901','00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a923');
UPDATE internal.observation_analysis_intents SET work_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE analysis_id='00000000-0000-4000-8000-00000000a923';
SELECT extensions.throws_ok($$SELECT public.advance_owned_observation_analysis(owner_id,observation_id,analysis_id,work_token,'cancel_uninvoked','{}') FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000a923'$$,'22023','analysis_history_operation_conflict','expired worker cannot manufacture cancellation proof');
SELECT extensions.is((SELECT state FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000a923'),'held','crash ambiguity retains hold');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000a911','00000000-0000-4000-8000-00000000a901');
SELECT extensions.throws_ok($$SELECT pg_temp.advance('outcome',(SELECT value FROM outcome))$$,'P0002','analysis_history_not_found','deletion wins late provider response');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000a921'),0::BIGINT,'deletion removes outcome and all worker state');
SELECT * FROM extensions.finish();
ROLLBACK;
