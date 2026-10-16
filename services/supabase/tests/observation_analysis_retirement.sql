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

SELECT extensions.ok(NOT(SELECT execution_retirement_api_enabled FROM internal.observation_history_rollout),'retirement defaults closed');
SELECT extensions.ok(has_function_privilege('service_role','public.retire_owned_observation_analysis_execution(uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('authenticated','public.retire_owned_observation_analysis_execution(uuid,jsonb,integer)','EXECUTE') AND NOT has_function_privilege('anon','public.retire_owned_observation_analysis_execution(uuid,jsonb,integer)','EXECUTE'),'only service Edge may settle retirement');
SELECT extensions.ok(NOT has_table_privilege('service_role','internal.observation_analysis_retirement_receipts','SELECT,INSERT,UPDATE,DELETE'),'service cannot directly access receipts');
UPDATE internal.entitlement_rollout_config SET entitlement_mode='complimentary',required_client_protocol=3 WHERE config_key='current';
SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f811');
UPDATE internal.observation_history_rollout SET admission_enabled=TRUE,dispatch_enabled=TRUE,append_enabled=TRUE,media_enabled=TRUE,protected_analysis_enabled=TRUE,orchestration_enabled=TRUE;
CREATE FUNCTION pg_temp.retirement_request(analysis UUID DEFAULT '00000000-0000-4000-8000-00000000f821',operation UUID DEFAULT '00000000-0000-4000-8000-00000000f841') RETURNS JSONB LANGUAGE SQL AS $$
 SELECT jsonb_build_object('schema_version',1,'operation_id',operation,'observation_id','00000000-0000-4000-8000-00000000f811','analysis_id',analysis,'source_analysis_id',NULL,'request_digest',repeat('a',64));
$$;
GRANT EXECUTE ON FUNCTION pg_temp.retirement_request(UUID,UUID) TO service_role,authenticated;
CREATE TEMP TABLE evidence_fixture AS SELECT pg_temp.protected_ready('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f821','00000000-0000-4000-8000-00000000f831') AS id;
SELECT internal.admit_protected_observation_analysis('00000000-0000-4000-8000-00000000f801',pg_temp.protected_input('00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f821','00000000-0000-4000-8000-00000000f831'),repeat('a',64));
CREATE TEMP TABLE worker AS SELECT internal.claim_observation_analysis('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f821') AS value;
CREATE TEMP TABLE original_history AS SELECT to_jsonb(h) AS value FROM internal.observation_histories h WHERE observation_id='00000000-0000-4000-8000-00000000f811';
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request(),9)$$,'42501','permission denied for function retire_owned_observation_analysis_execution','authenticated cannot bypass Edge');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request(),9)$$,'55000','analysis_history_unavailable','closed gate cannot retire');
RESET ROLE;
UPDATE internal.observation_history_rollout SET execution_retirement_api_enabled=TRUE;
CREATE FUNCTION pg_temp.reject_retirement_receipt() RETURNS TRIGGER LANGUAGE PLPGSQL AS $$ BEGIN RAISE EXCEPTION 'synthetic_receipt_failure'; END; $$;
CREATE TRIGGER synthetic_receipt_failure BEFORE INSERT ON internal.observation_analysis_retirement_receipts FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_retirement_receipt();
SET LOCAL ROLE service_role;
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request(),9)$$,'P0001','synthetic_receipt_failure','receipt failure rolls entire retirement back');
RESET ROLE;
SELECT extensions.ok((SELECT state='admitted' AND work_token IS NOT NULL FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000f821') AND (SELECT state='reserved' FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f821') AND (SELECT count(*)=1 FROM internal.observation_evidence_objects WHERE analysis_id='00000000-0000-4000-8000-00000000f821'),'failed save retains claim, funding and private evidence');
DROP TRIGGER synthetic_receipt_failure ON internal.observation_analysis_retirement_receipts;
CREATE TEMP TABLE retired(value JSONB); GRANT ALL ON retired TO service_role;
SET LOCAL ROLE service_role;
INSERT INTO retired SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request(),9);
SELECT extensions.is((SELECT value FROM retired),pg_temp.retirement_request()||'{"state":"retired_before_dispatch"}'::JSONB,'receipt has exact original identity only');
RESET ROLE;
SELECT extensions.ok((SELECT state='failed_terminal' AND terminal_reason='retired_before_dispatch' AND work_token IS NULL AND work_expires_at IS NULL FROM internal.observation_analysis_intents WHERE analysis_id='00000000-0000-4000-8000-00000000f821'),'live work claim atomically retired');
SELECT extensions.ok((SELECT state='refunded' FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f821') AND (SELECT state='released' FROM internal.complimentary_scan_usage WHERE client_scan_id='00000000-0000-4000-8000-00000000f821'),'only proven unused reservation and held credit released');
SELECT extensions.is((SELECT count(*) FROM internal.identification_invocations WHERE scan_id='00000000-0000-4000-8000-00000000f821'),0::BIGINT,'retirement invokes no provider');
SELECT extensions.is((SELECT count(*) FROM internal.observation_evidence_objects WHERE analysis_id='00000000-0000-4000-8000-00000000f821'),0::BIGINT,'private evidence retired in same transaction');
SELECT extensions.ok(EXISTS(SELECT 1 FROM internal.observation_evidence_erasure WHERE object_id=(SELECT id FROM evidence_fixture) AND erased_at IS NULL),'retirement atomically persists opaque independent erasure obligation');
SELECT extensions.is((SELECT to_jsonb(h) FROM internal.observation_histories h WHERE observation_id='00000000-0000-4000-8000-00000000f811'),(SELECT value FROM original_history),'selection and history unchanged');
SELECT extensions.throws_ok($$SELECT public.advance_owned_observation_analysis('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f821',(SELECT (value->>'work_token')::UUID FROM worker),'dispatch',jsonb_build_object('provenance',pg_temp.funded_provenance('00000000-0000-4000-8000-00000000f821')))$$,'22023','analysis_history_operation_conflict','stale worker cannot dispatch');
SELECT extensions.is(internal.claim_observation_analysis('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f821')->>'claimed','false','terminal intent cannot be claimed again');

SELECT pg_temp.seed_funded_history('00000000-0000-4000-8000-00000000f802','00000000-0000-4000-8000-00000000f812');
SELECT extensions.throws_ok($$SELECT internal.perform_ghost_profile_merge('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f802')$$,'55000','ghost_merge_source_history_requires_attention','retired intent still fences ownership transfer');
SELECT extensions.ok((SELECT owner_id='00000000-0000-4000-8000-00000000f801' AND receipt=(SELECT value FROM retired) FROM internal.observation_analysis_retirement_receipts WHERE analysis_id='00000000-0000-4000-8000-00000000f821') AND (SELECT state='refunded' FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f821'),'merge denial preserves receipt and settlement');
UPDATE internal.observation_history_rollout SET execution_retirement_api_enabled=FALSE;
SET LOCAL ROLE service_role;
SELECT extensions.is(public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request(),9),(SELECT value FROM retired),'lost reply recovers exact receipt before fresh gate');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request()||jsonb_build_object('request_digest',repeat('b',64)),9)$$,'22023','analysis_history_operation_conflict','operation cannot rebind after gate closure');
RESET ROLE;
UPDATE internal.observation_history_rollout SET execution_retirement_api_enabled=TRUE;
SELECT extensions.throws_ok($$UPDATE internal.observation_analysis_retirement_receipts SET receipt=receipt WHERE analysis_id='00000000-0000-4000-8000-00000000f821'$$,'22023','analysis_history_operation_conflict','receipt immutable even for no-op update');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f821','00000000-0000-4000-8000-00000000f849'),9)$$,'22023','analysis_history_operation_conflict','new retirement UUID cannot replace completed operation');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f829','00000000-0000-4000-8000-00000000f849'),9)$$,'P0002','analysis_history_not_found','absence is not retirement proof');
SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000f801',pg_temp.funded_input('00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f822'),repeat('a',64));
SELECT pg_temp.funded_dispatch('00000000-0000-4000-8000-00000000f801','00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f822');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f822','00000000-0000-4000-8000-00000000f842'),9)$$,'22023','analysis_history_operation_conflict','unknown dispatched outcome cannot retire');
SELECT extensions.is((SELECT state FROM internal.ai_quota_reservations WHERE original_analysis_id='00000000-0000-4000-8000-00000000f822'),'committed','uncertain provider funding remains charged');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_retirement_receipts),1::BIGINT,'denied paths create no receipts');

-- Damaged durable evidence cannot be recast as never-dispatched work.
SELECT internal.admit_observation_analysis('00000000-0000-4000-8000-00000000f801',pg_temp.funded_input('00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f823'),repeat('a',64));
CREATE TEMP TABLE pristine_intent AS SELECT to_jsonb(i) AS value FROM internal.observation_analysis_intents i WHERE analysis_id='00000000-0000-4000-8000-00000000f823';
UPDATE internal.observation_analysis_intents SET invocation_id='00000000-0000-4000-8000-00000000f891' WHERE analysis_id='00000000-0000-4000-8000-00000000f823';
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f823','00000000-0000-4000-8000-00000000f843'),9)$$,'22023','analysis_history_operation_conflict','admitted label with invocation cannot retire');
UPDATE internal.observation_analysis_intents SET invocation_id=NULL,provider_outcome='{}' WHERE analysis_id='00000000-0000-4000-8000-00000000f823';
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f823','00000000-0000-4000-8000-00000000f843'),9)$$,'22023','analysis_history_operation_conflict','admitted label with outcome cannot retire');
UPDATE internal.observation_analysis_intents SET provider_outcome=NULL,quota=quota||'{"attempt_count":999}' WHERE analysis_id='00000000-0000-4000-8000-00000000f823';
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f823','00000000-0000-4000-8000-00000000f843'),9)$$,'22023','analysis_history_operation_conflict','different quota generation cannot retire');
UPDATE internal.observation_analysis_intents SET quota=(SELECT value->'quota' FROM pristine_intent) WHERE analysis_id='00000000-0000-4000-8000-00000000f823';
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f823','00000000-0000-4000-8000-00000000f843')||jsonb_build_object('request_digest',repeat('b',64)),9)$$,'22023','analysis_history_operation_conflict','different immutable request cannot retire');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f802',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f823','00000000-0000-4000-8000-00000000f843'),9)$$,'P0002','analysis_history_not_found','foreign owner cannot retire');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request()||'{"schema_version":true}',9)$$,'22023','invalid_analysis_history','malformed schema fails before replay');

SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f823','00000000-0000-4000-8000-00000000f843'),8)$$,'22023','invalid_analysis_history','reader 9 required before mutation');
UPDATE internal.complimentary_scan_usage SET state='released',settled_at=clock_timestamp(),settlement_reason='synthetic_release' WHERE client_scan_id='00000000-0000-4000-8000-00000000f823';
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request('00000000-0000-4000-8000-00000000f823','00000000-0000-4000-8000-00000000f843'),9)$$,'22023','analysis_history_operation_conflict','non-held complimentary evidence cannot retire');
SELECT extensions.is((SELECT to_jsonb(i) FROM internal.observation_analysis_intents i WHERE analysis_id='00000000-0000-4000-8000-00000000f823'),(SELECT value FROM pristine_intent),'denials preserve original admitted state');
INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES('00000000-0000-4000-8000-00000000f811','00000000-0000-4000-8000-00000000f801');
SELECT extensions.is((SELECT count(*) FROM internal.observation_analysis_retirement_receipts),0::BIGINT,'private retirement receipt follows parent deletion');
SELECT extensions.throws_ok($$SELECT public.retire_owned_observation_analysis_execution('00000000-0000-4000-8000-00000000f801',pg_temp.retirement_request(),9)$$,'P0002','analysis_history_not_found','deletion wins replay');
SELECT * FROM extensions.finish();
ROLLBACK;
