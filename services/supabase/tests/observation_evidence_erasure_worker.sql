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

SELECT extensions.ok(NOT(SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout),'private erasure starts closed');
SELECT extensions.ok(NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN UNNEST(ARRAY['anon','authenticated']) role_name
 WHERE n.nspname='public' AND p.proname IN ('retire_expired_observation_evidence','claim_observation_evidence_erasure','finish_observation_evidence_erasure') AND has_function_privilege(role_name,p.oid,'EXECUTE')),'no client erasure RPC grants');
SELECT extensions.ok(NOT has_function_privilege('service_role','internal.expire_unbound_observation_evidence(uuid)','EXECUTE'),'primitive expiry remains private');
SELECT extensions.ok(NOT internal.valid_observation_erasure_cohort_items(NULL),'SQL null descriptor holds');
SELECT extensions.ok(NOT internal.valid_observation_erasure_cohort_items('null'),'JSON null descriptor holds');
SELECT extensions.ok(NOT internal.valid_observation_erasure_cohort_items('{}'),'object instead of array holds');
SELECT extensions.ok(NOT internal.valid_observation_erasure_cohort_items('[1,true,null,"synthetic"]'),'scalar members hold without throwing');
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11');
UPDATE internal.observation_history_rollout SET media_enabled=TRUE;
CREATE FUNCTION pg_temp.items() RETURNS JSONB LANGUAGE SQL AS $$
SELECT jsonb_build_array(jsonb_build_object('media_id','00000000-0000-4000-8000-00000000ef31','content_type','image/jpeg','byte_count',3,'sha256',repeat('a',64)),
jsonb_build_object('media_id','00000000-0000-4000-8000-00000000ef32','content_type','image/png','byte_count',4,'sha256',repeat('b',64)));
$$;
CREATE FUNCTION pg_temp.reserve() RETURNS JSONB LANGUAGE SQL AS $$
SELECT public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef21',pg_temp.items());
$$;
GRANT EXECUTE ON FUNCTION pg_temp.items(),pg_temp.reserve() TO service_role;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'closed gate retires nothing');
SELECT extensions.is(public.claim_observation_evidence_erasure(),NULL::JSONB,'closed gate issues no claim');
CREATE TEMP TABLE reserved AS SELECT pg_temp.reserve() value;
SELECT public.complete_owned_observation_evidence_upload('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef21','00000000-0000-4000-8000-00000000ef31',(SELECT (value#>>'{0,object_id}')::UUID FROM reserved));
RESET ROLE;
UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'future cohort untouched');
RESET ROLE;
ALTER TABLE internal.observation_evidence_upload_cohorts DISABLE TRIGGER guard_observation_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_upload_cohorts SET expires_at=transaction_timestamp()-INTERVAL '1 minute';
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-INTERVAL '1 minute';
ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE TRIGGER guard_observation_upload_cohort;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
CREATE TEMP TABLE frozen AS SELECT to_jsonb(c) value FROM internal.observation_evidence_upload_cohorts c;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),2,'ready and unready cohort members retire together');
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'empty retained cohort is not rediscovered');
SELECT extensions.throws_ok('SELECT pg_temp.reserve()','55000','analysis_history_evidence_unavailable','retired analysis cannot allocate replacement keys');
CREATE TEMP TABLE claim AS SELECT public.claim_observation_evidence_erasure() value;
SELECT extensions.is((SELECT count(*)::INTEGER FROM claim,jsonb_object_keys(value)),3,'claim exposes only opaque identity token and expiry');
SELECT extensions.is(public.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM claim),gen_random_uuid(),TRUE),FALSE,'wrong token cannot settle');
RESET ROLE;
SELECT extensions.is((SELECT to_jsonb(c) FROM internal.observation_evidence_upload_cohorts c),(SELECT value FROM frozen),'cleanup retains exact descriptor and fixed deadline');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_objects),0::BIGINT,'no partial receipt remains');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_erasure),2::BIGINT,'both opaque obligations survive');
UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=FALSE;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.claim_observation_evidence_erasure(),NULL::JSONB,'gate rollback blocks new I/O');
SELECT extensions.ok(public.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM claim),(SELECT (value->>'claim_token')::UUID FROM claim),TRUE),'original claim can finish after rollback');
SELECT extensions.is(public.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM claim),(SELECT (value->>'claim_token')::UUID FROM claim),TRUE),FALSE,'settlement cannot replay a consumed claim');
RESET ROLE;
UPDATE internal.observation_history_rollout SET private_evidence_erasure_enabled=TRUE;
SET LOCAL ROLE service_role;
CREATE TEMP TABLE late_claim AS SELECT public.claim_observation_evidence_erasure() value;
RESET ROLE;
UPDATE internal.observation_evidence_erasure SET claim_expires_at=clock_timestamp()-INTERVAL '1 second' WHERE object_id=(SELECT (value->>'object_id')::UUID FROM late_claim);
SET LOCAL ROLE service_role;
SELECT extensions.is(public.finish_observation_evidence_erasure((SELECT (value->>'object_id')::UUID FROM late_claim),(SELECT (value->>'claim_token')::UUID FROM late_claim),TRUE),FALSE,'expired claim cannot acknowledge');
CREATE TEMP TABLE replacement AS SELECT public.claim_observation_evidence_erasure() value;
SELECT extensions.is((SELECT value->>'object_id' FROM replacement),(SELECT value->>'object_id' FROM late_claim),'retry keeps opaque object identity');
SELECT extensions.isnt((SELECT value->>'claim_token' FROM replacement),(SELECT value->>'claim_token' FROM late_claim),'retry replaces only lease identity');
RESET ROLE;
-- A corrupt oldest cohort must hold without starving later valid work.
SET LOCAL ROLE service_role;
SELECT public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef24',jsonb_build_array(jsonb_set(pg_temp.items()->0,'{media_id}','"00000000-0000-4000-8000-00000000ef36"')));
RESET ROLE;
CREATE TEMP TABLE damaged_original AS SELECT items FROM internal.observation_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000ef24';
ALTER TABLE internal.observation_evidence_upload_cohorts DISABLE TRIGGER guard_observation_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_upload_cohorts SET expires_at=transaction_timestamp()-INTERVAL '3 minutes',items='[false]' WHERE analysis_id='00000000-0000-4000-8000-00000000ef24';
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-INTERVAL '3 minutes' WHERE analysis_id='00000000-0000-4000-8000-00000000ef24';
ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE TRIGGER guard_observation_upload_cohort;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
-- Legacy receipts have no frozen cohort: retire one per transaction.
SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef22','00000000-0000-4000-8000-00000000ef33','image/jpeg',3,repeat('a',64));
SELECT internal.reserve_observation_evidence('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef22','00000000-0000-4000-8000-00000000ef34','image/jpeg',3,repeat('a',64));
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-INTERVAL '1 second' WHERE analysis_id='00000000-0000-4000-8000-00000000ef22';
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),1,'one legacy receipt retires despite older empty cohort');
RESET ROLE;
ALTER TABLE internal.observation_evidence_upload_cohorts DISABLE TRIGGER guard_observation_upload_cohort;
UPDATE internal.observation_evidence_upload_cohorts SET items=jsonb_set((SELECT items FROM damaged_original),'{0,sha256}',to_jsonb(repeat('f',64))) WHERE analysis_id='00000000-0000-4000-8000-00000000ef24';
ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE TRIGGER guard_observation_upload_cohort;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),1,'valid-shaped but mismatched older receipt cannot starve remaining legacy work');
RESET ROLE;
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_objects WHERE analysis_id='00000000-0000-4000-8000-00000000ef24'),1::BIGINT,'corrupt cohort bytes remain held while later legacy work progresses');
ALTER TABLE internal.observation_evidence_upload_cohorts DISABLE TRIGGER guard_observation_upload_cohort;
UPDATE internal.observation_evidence_upload_cohorts SET items=(SELECT items FROM damaged_original) WHERE analysis_id='00000000-0000-4000-8000-00000000ef24';
ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE TRIGGER guard_observation_upload_cohort;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),1,'exact repaired fixture becomes eligible without renewing expiry');
RESET ROLE;
-- Historical partial cleanup still retires all extant members atomically.
SET LOCAL ROLE service_role;
SELECT public.reserve_owned_observation_evidence_cohort('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef25',
 jsonb_build_array(jsonb_set(pg_temp.items()->0,'{media_id}','"00000000-0000-4000-8000-00000000ef37"'),jsonb_set(pg_temp.items()->1,'{media_id}','"00000000-0000-4000-8000-00000000ef38"')));
RESET ROLE;
ALTER TABLE internal.observation_evidence_upload_cohorts DISABLE TRIGGER guard_observation_upload_cohort;
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_upload_cohorts SET expires_at=transaction_timestamp()-INTERVAL '1 minute' WHERE analysis_id='00000000-0000-4000-8000-00000000ef25';
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-INTERVAL '1 minute' WHERE analysis_id='00000000-0000-4000-8000-00000000ef25';
ALTER TABLE internal.observation_evidence_upload_cohorts ENABLE TRIGGER guard_observation_upload_cohort;
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SELECT internal.expire_unbound_observation_evidence('00000000-0000-4000-8000-00000000ef37');
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),1,'partial expired cohort retires remaining exact member');
RESET ROLE;
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_upload_cohorts WHERE analysis_id='00000000-0000-4000-8000-00000000ef25'),1::BIGINT,'partial cleanup retains identity fence');
-- An admitted provider owns evidence beyond the upload reservation deadline.
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,protected_analysis_enabled=TRUE;
SELECT pg_temp.protected_ready('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef23','00000000-0000-4000-8000-00000000ef35');
SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000ef01',pg_temp.protected_input('00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef23','00000000-0000-4000-8000-00000000ef35'),repeat('a',64));
ALTER TABLE internal.observation_evidence_objects DISABLE TRIGGER guard_observation_evidence_update;
UPDATE internal.observation_evidence_objects SET expires_at=transaction_timestamp()-INTERVAL '1 minute';
ALTER TABLE internal.observation_evidence_objects ENABLE TRIGGER guard_observation_evidence_update;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'admitted evidence is never expired');
RESET ROLE;
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef23');
SELECT pg_temp.protected_draft('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef23');
SELECT internal.complete_observation_analysis('00000000-0000-4000-8000-00000000ef01','00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef23');
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'completed result keeps its evidence');
RESET ROLE;
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000ef11','00000000-0000-4000-8000-00000000ef01');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_upload_cohorts),0::BIGINT,'deletion removes private descriptors');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_objects),0::BIGINT,'deletion wins over result evidence');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_erasure),8::BIGINT,'opaque cleanup survives deletion');
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_expired_observation_evidence(),0,'deleted parent cannot be rediscovered');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
